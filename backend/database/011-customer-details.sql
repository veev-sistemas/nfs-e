BEGIN;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS details jsonb NOT NULL DEFAULT '{}'::jsonb CHECK(jsonb_typeof(details)='object');
CREATE OR REPLACE FUNCTION reserve_emission(p_company uuid,p_draft uuid,p_issued timestamptz,p_competence date,p_environment text)
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
    'customer',(SELECT jsonb_build_object('name',name,'document',document)||details FROM customers WHERE id=d.customer_id AND company_id=p_company))
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
COMMIT;
