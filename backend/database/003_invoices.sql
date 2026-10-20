BEGIN;
CREATE UNIQUE INDEX drafts_company_id_unique ON drafts(company_id, id);
CREATE TABLE invoices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id),
  draft_id uuid,
  environment text NOT NULL CHECK (environment = 'homologacao'),
  access_key varchar(50) NOT NULL CHECK (access_key ~ '^[0-9]{50}$'),
  invoice_number text NOT NULL,
  issuer_document varchar(14) NOT NULL,
  amount_cents bigint NOT NULL CHECK (amount_cents > 0),
  status text NOT NULL DEFAULT 'imported' CHECK (status = 'imported'),
  source text NOT NULL DEFAULT 'external_xml',
  xml_content text NOT NULL,
  xml_sha256 text NOT NULL,
  imported_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (environment, access_key),
  FOREIGN KEY (company_id, draft_id) REFERENCES drafts(company_id, id)
);
CREATE INDEX invoices_company_created ON invoices(company_id, imported_at DESC);

-- XML recebido e importado, nao autenticado nem consultado novamente pela API.
-- Nenhuma funcao SECURITY DEFINER: utiliza os privilegios da conexao.
CREATE FUNCTION import_homologation_invoice(p_company uuid, p_draft uuid, p_xml text)
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
     env IS DISTINCT FROM '2' OR number_text IS NULL OR number_text !~ '^[0-9]+$' THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Chave, numero ou ambiente de homologacao invalido.';
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
    SELECT 1 FROM drafts WHERE id=p_draft AND company_id=p_company AND amount_cents=amount
  ) THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Rascunho nao encontrado nesta empresa ou valor divergente.';
  END IF;
  fingerprint := encode(digest(p_xml,'sha256'),'hex');
  INSERT INTO invoices(company_id,draft_id,environment,access_key,invoice_number,issuer_document,amount_cents,xml_content,xml_sha256)
  VALUES(p_company,p_draft,'homologacao',substr(invoice_id,4),number_text,issuer,amount,p_xml,fingerprint)
  ON CONFLICT(environment,access_key) DO NOTHING
  RETURNING * INTO row_invoice;
  IF row_invoice.id IS NULL THEN
    SELECT * INTO row_invoice FROM invoices WHERE environment='homologacao' AND access_key=substr(invoice_id,4);
    IF row_invoice.company_id <> p_company OR row_invoice.xml_sha256 <> fingerprint OR
       row_invoice.draft_id IS DISTINCT FROM p_draft THEN
      RAISE EXCEPTION USING ERRCODE='23505', MESSAGE='Chave existente com conteudo ou vinculo diferente.';
    END IF;
  END IF;
  RETURN to_jsonb(row_invoice) - 'xml_content';
END;
$$;
COMMIT;
