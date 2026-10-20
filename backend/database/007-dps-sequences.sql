BEGIN;
-- Uma sequencia persistente por empresa, ambiente e serie. Nunca apagar ao trocar serie.
CREATE TABLE dps_sequences (
  company_id uuid NOT NULL REFERENCES companies(id),
  environment text NOT NULL CHECK(environment IN ('homologacao','producao')),
  series varchar(5) NOT NULL CHECK(series ~ '^(0|[1-9][0-9]{0,4})$'),
  next_number bigint NOT NULL CHECK(next_number BETWEEN 1 AND 999999999999999),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(company_id,environment,series)
);
INSERT INTO dps_sequences(company_id,environment,series,next_number)
SELECT company_id,'homologacao',homologation_series::bigint::text,next_homologation_number
FROM fiscal_profiles;
INSERT INTO dps_sequences(company_id,environment,series,next_number)
SELECT company_id,environment,dps_series::bigint::text,max(dps_number)+1
FROM emission_attempts GROUP BY company_id,environment,dps_series::bigint::text
ON CONFLICT(company_id,environment,series) DO UPDATE
SET next_number=greatest(dps_sequences.next_number,excluded.next_number);

CREATE FUNCTION guard_dps_sequence() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP='DELETE' THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Sequencias DPS nao podem ser apagadas.';
  END IF;
  IF (NEW.company_id,NEW.environment,NEW.series) IS DISTINCT FROM (OLD.company_id,OLD.environment,OLD.series)
     OR NEW.next_number<OLD.next_number THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Nao e permitido voltar a numeracao ou alterar a identidade da sequencia.';
  END IF;
  NEW.updated_at:=now(); RETURN NEW;
END $$;
CREATE TRIGGER dps_sequence_guard BEFORE UPDATE OR DELETE ON dps_sequences
FOR EACH ROW EXECUTE FUNCTION guard_dps_sequence();

-- Perfil e emissor continuam usando a mesma trava, inclusive durante ajustes administrativos.
CREATE FUNCTION sync_homologation_sequence() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE previous_number bigint;
BEGIN
  NEW.homologation_series:=NEW.homologation_series::bigint::text;
  INSERT INTO dps_sequences(company_id,environment,series,next_number)
    VALUES(NEW.company_id,'homologacao',NEW.homologation_series,NEW.next_homologation_number)
    ON CONFLICT DO NOTHING;
  SELECT next_number INTO previous_number FROM dps_sequences
    WHERE company_id=NEW.company_id AND environment='homologacao' AND series=NEW.homologation_series FOR UPDATE;
  IF NEW.next_homologation_number<previous_number THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Numero DPS ja reservado. Atualize a sequencia antes de salvar.';
  END IF;
  UPDATE dps_sequences SET next_number=NEW.next_homologation_number
    WHERE company_id=NEW.company_id AND environment='homologacao' AND series=NEW.homologation_series;
  RETURN NEW;
END $$;
UPDATE fiscal_profiles SET homologation_series=homologation_series::bigint::text,
  next_homologation_number=(SELECT next_number FROM dps_sequences s WHERE s.company_id=fiscal_profiles.company_id
    AND s.environment='homologacao' AND s.series=fiscal_profiles.homologation_series::bigint::text);
CREATE TRIGGER fiscal_profile_sequence BEFORE INSERT OR UPDATE OF homologation_series,next_homologation_number
ON fiscal_profiles FOR EACH ROW EXECUTE FUNCTION sync_homologation_sequence();
COMMIT;
