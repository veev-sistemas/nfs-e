BEGIN;
CREATE TABLE fiscal_profiles (
  company_id uuid PRIMARY KEY REFERENCES companies(id),
  municipality_code varchar(7) NOT NULL CHECK (municipality_code ~ '^[0-9]{7}$'),
  municipality_name text NOT NULL,
  state_code varchar(2) NOT NULL,
  street text NOT NULL,
  house_number text NOT NULL,
  district text NOT NULL,
  postal_code varchar(8) NOT NULL CHECK (postal_code ~ '^[0-9]{8}$'),
  municipal_registration text,
  next_homologation_number bigint NOT NULL DEFAULT 1 CHECK (next_homologation_number BETWEEN 1 AND 999999999999999),
  homologation_series varchar(5) NOT NULL DEFAULT '901' CHECK (homologation_series ~ '^[0-9]{1,5}$')
);
CREATE TABLE emission_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id),
  draft_id uuid NOT NULL,
  environment text NOT NULL DEFAULT 'homologacao' CHECK(environment='homologacao'),
  dps_number bigint NOT NULL,
  dps_series varchar(5) NOT NULL,
  issued_at timestamptz NOT NULL,
  competence date NOT NULL,
  status text NOT NULL DEFAULT 'reserved' CHECK(status IN ('reserved','prepared','sending','authorized','rejected','unknown','local_error')),
  request_snapshot jsonb NOT NULL,
  signed_dps text,
  result jsonb,
  response_text text,
  invoice_xml text,
  invoice_id uuid REFERENCES invoices(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id,draft_id),
  UNIQUE(company_id,environment,dps_series,dps_number),
  FOREIGN KEY(company_id,draft_id) REFERENCES drafts(company_id,id)
);
CREATE INDEX attempts_company_created ON emission_attempts(company_id,created_at DESC);
ALTER TABLE invoices DROP CONSTRAINT invoices_status_check;
ALTER TABLE invoices ADD CONSTRAINT invoices_status_check CHECK(status IN ('imported','authorized_homologation'));

CREATE FUNCTION reserve_homologation(p_company uuid,p_draft uuid,p_issued timestamptz,p_competence date)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  current_attempt emission_attempts%ROWTYPE;
  d drafts%ROWTYPE;
  profile fiscal_profiles%ROWTYPE;
  payload jsonb;
BEGIN
  -- Serializa a numeracao da empresa, incluindo duas requisicoes concorrentes.
  SELECT * INTO profile FROM fiscal_profiles WHERE company_id=p_company FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Perfil fiscal nao configurado.'; END IF;
  SELECT * INTO current_attempt FROM emission_attempts WHERE company_id=p_company AND draft_id=p_draft;
  IF FOUND THEN RETURN jsonb_build_object('created',false,'attempt',to_jsonb(current_attempt)-'signed_dps'-'invoice_xml'-'response_text'); END IF;
  SELECT * INTO d FROM drafts WHERE id=p_draft AND company_id=p_company;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Rascunho nao encontrado.'; END IF;
  IF p_issued IS NULL OR p_competence IS NULL OR p_issued>now() OR p_competence>(now() AT TIME ZONE 'America/Sao_Paulo')::date THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Data de emissao ou competencia invalida.';
  END IF;
  SELECT jsonb_build_object('company',jsonb_build_object('id',c.id,'document',c.document,'name',c.name),
    'profile',to_jsonb(profile)-'next_homologation_number', 'settings',d.settings_snapshot,
    'amount_cents',d.amount_cents,'customer',(SELECT jsonb_build_object('name',name,'document',document) FROM customers WHERE id=d.customer_id AND company_id=p_company))
    INTO payload FROM companies c WHERE c.id=p_company;
  INSERT INTO emission_attempts(company_id,draft_id,dps_number,dps_series,issued_at,competence,request_snapshot)
  VALUES(p_company,p_draft,profile.next_homologation_number,profile.homologation_series,p_issued,p_competence,payload)
  RETURNING * INTO current_attempt;
  UPDATE fiscal_profiles SET next_homologation_number=next_homologation_number+1 WHERE company_id=p_company;
  RETURN jsonb_build_object('created',true,'attempt',to_jsonb(current_attempt)-'signed_dps'-'invoice_xml'-'response_text');
END;
$$;
COMMIT;
