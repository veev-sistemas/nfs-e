BEGIN;
ALTER TABLE drafts ADD COLUMN environment text NOT NULL DEFAULT 'homologacao'
  CHECK(environment IN ('homologacao','producao'));
CREATE FUNCTION immutable_draft_environment() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.environment<>OLD.environment THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='O ambiente do rascunho nao pode ser alterado.';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER draft_environment_guard BEFORE UPDATE OF environment ON drafts
FOR EACH ROW EXECUTE FUNCTION immutable_draft_environment();

CREATE TABLE company_emission_config (
  company_id uuid PRIMARY KEY REFERENCES companies(id),
  production_enabled boolean NOT NULL DEFAULT false,
  production_series varchar(5) CHECK(production_series ~ '^(0|[1-9][0-9]{0,4})$'),
  CHECK(NOT production_enabled OR production_series IS NOT NULL)
);
ALTER TABLE emission_attempts DROP CONSTRAINT emission_attempts_environment_check;
ALTER TABLE emission_attempts ADD CHECK(environment IN ('homologacao','producao'));
ALTER TABLE invoices DROP CONSTRAINT invoices_environment_check;
ALTER TABLE invoices ADD CHECK(environment IN ('homologacao','producao'));
ALTER TABLE invoices DROP CONSTRAINT invoices_status_check;
ALTER TABLE invoices ADD CHECK(status IN ('imported','authorized_homologation','authorized_production'));

CREATE FUNCTION reserve_emission(p_company uuid,p_draft uuid,p_issued timestamptz,p_competence date,p_environment text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  current_attempt emission_attempts%ROWTYPE;
  d drafts%ROWTYPE;
  profile fiscal_profiles%ROWTYPE;
  config company_emission_config%ROWTYPE;
  chosen_series text;
  chosen_number bigint;
  payload jsonb;
BEGIN
  IF p_environment NOT IN ('homologacao','producao') OR p_environment IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Ambiente invalido.';
  END IF;
  SELECT * INTO profile FROM fiscal_profiles WHERE company_id=p_company FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Perfil fiscal nao configurado.'; END IF;
  SELECT * INTO d FROM drafts WHERE id=p_draft AND company_id=p_company FOR UPDATE;
  IF NOT FOUND OR d.environment<>p_environment THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Rascunho ausente ou de outro ambiente.';
  END IF;
  SELECT * INTO current_attempt FROM emission_attempts WHERE company_id=p_company AND draft_id=p_draft;
  IF FOUND THEN RETURN jsonb_build_object('created',false,'attempt',to_jsonb(current_attempt)-'signed_dps'-'invoice_xml'-'response_text'); END IF;
  IF p_issued IS NULL OR p_competence IS NULL OR p_issued>now() OR p_competence>(now() AT TIME ZONE 'America/Sao_Paulo')::date THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Data de emissao ou competencia invalida.';
  END IF;
  IF p_environment='producao' THEN
    SELECT * INTO config FROM company_emission_config WHERE company_id=p_company FOR UPDATE;
    IF NOT FOUND OR NOT config.production_enabled THEN
      RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Producao nao liberada para esta empresa.';
    END IF;
    chosen_series:=config.production_series;
    SELECT next_number INTO chosen_number FROM dps_sequences
      WHERE company_id=p_company AND environment='producao' AND series=chosen_series FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Configure a numeracao de producao.'; END IF;
  ELSE
    chosen_series:=profile.homologation_series;
    chosen_number:=profile.next_homologation_number;
  END IF;
  SELECT jsonb_build_object('company',jsonb_build_object('id',c.id,'document',c.document,'name',c.name),
    'profile',to_jsonb(profile)-'next_homologation_number','settings',d.settings_snapshot,
    'environment',p_environment,'amount_cents',d.amount_cents,
    'customer',(SELECT jsonb_build_object('name',name,'document',document) FROM customers WHERE id=d.customer_id AND company_id=p_company))
    INTO payload FROM companies c WHERE c.id=p_company;
  INSERT INTO emission_attempts(company_id,draft_id,environment,dps_number,dps_series,issued_at,competence,request_snapshot)
    VALUES(p_company,p_draft,p_environment,chosen_number,chosen_series,p_issued,p_competence,payload) RETURNING * INTO current_attempt;
  IF p_environment='producao' THEN
    UPDATE dps_sequences SET next_number=next_number+1
      WHERE company_id=p_company AND environment='producao' AND series=chosen_series;
  ELSE
    UPDATE fiscal_profiles SET next_homologation_number=next_homologation_number+1 WHERE company_id=p_company;
  END IF;
  RETURN jsonb_build_object('created',true,'attempt',to_jsonb(current_attempt)-'signed_dps'-'invoice_xml'-'response_text');
END $$;

CREATE OR REPLACE FUNCTION reserve_homologation(p_company uuid,p_draft uuid,p_issued timestamptz,p_competence date)
RETURNS jsonb LANGUAGE sql AS $$ SELECT reserve_emission(p_company,p_draft,p_issued,p_competence,'homologacao') $$;
CREATE FUNCTION import_invoice(p_company uuid, p_draft uuid, p_xml text, p_environment text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  doc xml;
  ns text[][] := ARRAY[ARRAY['n','http://www.sped.fazenda.gov.br/nfse']];
  invoice_id text;
  issuer text;
  number_text text;
  env text;
  amount bigint;
  fingerprint text;
  row_invoice invoices%ROWTYPE;
BEGIN
  IF p_environment NOT IN ('homologacao','producao') OR p_environment IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Ambiente invalido.';
  END IF;
  IF p_xml IS NULL OR octet_length(p_xml) > 524288 OR
     p_xml ~* '<![[:space:]]*(DOCTYPE|ENTITY)' THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='XML ausente, muito grande ou com DTD/entidade nao permitida.';
  END IF;
  BEGIN
    doc := XMLPARSE(DOCUMENT p_xml);
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='XML invalido.';
  END;
  IF cardinality(xpath('/n:NFSe/n:infNFSe', doc, ns)) <> 1 THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Esperado XML de NFS-e Nacional, nao DPS.';
  END IF;
  invoice_id := (xpath('string(/n:NFSe/n:infNFSe/@Id)', doc, ns))[1]::text;
  issuer := (xpath('string(/n:NFSe/n:infNFSe/n:emit/n:CNPJ)', doc, ns))[1]::text;
  number_text := (xpath('string(/n:NFSe/n:infNFSe/n:nNFSe)', doc, ns))[1]::text;
  env := (xpath('string(/n:NFSe/n:infNFSe/n:DPS/n:infDPS/n:tpAmb)', doc, ns))[1]::text;
  IF invoice_id IS NULL OR invoice_id !~ '^NFS[0-9]{50}$' OR
     env IS DISTINCT FROM (CASE WHEN p_environment='producao' THEN '1' ELSE '2' END) OR number_text IS NULL OR number_text !~ '^[0-9]+$' THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Chave, numero ou ambiente invalido.';
  END IF;
  IF substr(invoice_id,13,14) IS DISTINCT FROM issuer OR
     (xpath('string(/n:NFSe/n:infNFSe/n:DPS/n:infDPS/n:prest/n:CNPJ)',doc,ns))[1]::text IS DISTINCT FROM issuer THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Identificacao do prestador inconsistente no XML.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM companies WHERE id=p_company AND document=issuer) THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='CNPJ do XML difere da empresa autenticada.';
  END IF;
  BEGIN
    amount := round(((xpath('string(/n:NFSe/n:infNFSe/n:DPS/n:infDPS/n:valores/n:vServPrest/n:vServ)',doc,ns))[1]::text)::numeric * 100)::bigint;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Valor do servico invalido.';
  END;
  IF amount IS NULL OR amount <= 0 THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Valor do servico deve ser positivo.';
  END IF;
  IF p_draft IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM drafts WHERE id=p_draft AND company_id=p_company AND amount_cents=amount AND environment=p_environment
  ) THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Rascunho nao encontrado nesta empresa ou valor divergente.';
  END IF;
  IF p_environment='producao' AND (
    (xpath('string(/n:NFSe/n:infNFSe/n:cStat)',doc,ns))[1]::text IS DISTINCT FROM '100' OR
    NOT EXISTS(SELECT 1 FROM emission_attempts a WHERE a.company_id=p_company AND a.draft_id=p_draft
      AND a.environment=p_environment AND a.status='authorized'
      AND a.dps_number::text=(xpath('string(/n:NFSe/n:infNFSe/n:DPS/n:infDPS/n:nDPS)',doc,ns))[1]::text
      AND a.dps_series=(xpath('string(/n:NFSe/n:infNFSe/n:DPS/n:infDPS/n:serie)',doc,ns))[1]::text)
  ) THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='XML de producao sem autorizacao ou divergente da DPS reservada.'; END IF;
  fingerprint := encode(digest(p_xml,'sha256'),'hex');
  INSERT INTO invoices(company_id,draft_id,environment,access_key,invoice_number,issuer_document,amount_cents,xml_content,xml_sha256)
  VALUES(p_company,p_draft,p_environment,substr(invoice_id,4),number_text,issuer,amount,p_xml,fingerprint)
  ON CONFLICT(environment,access_key) DO NOTHING
  RETURNING * INTO row_invoice;
  IF row_invoice.id IS NULL THEN
    SELECT * INTO row_invoice FROM invoices WHERE environment=p_environment AND access_key=substr(invoice_id,4);
    IF row_invoice.company_id <> p_company OR row_invoice.xml_sha256 <> fingerprint OR
       row_invoice.draft_id IS DISTINCT FROM p_draft THEN
      RAISE EXCEPTION USING ERRCODE='23505', MESSAGE='Chave existente com conteudo ou vinculo diferente.';
    END IF;
  END IF;
  RETURN to_jsonb(row_invoice) - 'xml_content';
END;
$$;

CREATE OR REPLACE FUNCTION import_homologation_invoice(p_company uuid,p_draft uuid,p_xml text)
RETURNS jsonb LANGUAGE sql AS $$ SELECT import_invoice(p_company,p_draft,p_xml,'homologacao') $$;

COMMIT;
