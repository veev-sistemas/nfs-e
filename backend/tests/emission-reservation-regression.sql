-- Banco de testes apos migracao 004; executar com psql -v ON_ERROR_STOP=1.
BEGIN;
DO $$
DECLARE c uuid; d uuid; a jsonb; b jsonb;
BEGIN
  INSERT INTO companies(name,document) VALUES('Reserva teste','33333333333333') RETURNING id INTO c;
  INSERT INTO fiscal_profiles(company_id,municipality_code,municipality_name,state_code,street,house_number,district,postal_code)
  VALUES(c,'3136702','Juiz de Fora','MG','Rua teste','1','Centro','36033000');
  INSERT INTO drafts(company_id,amount_cents,settings_snapshot) VALUES(c,10000,'{}') RETURNING id INTO d;
  a:=reserve_homologation(c,d,now()-interval '1 minute',current_date);
  b:=reserve_homologation(c,d,now()-interval '1 minute',current_date);
  IF a->>'created'<>'true' OR b->>'created'<>'false' OR a#>>'{attempt,id}'<>b#>>'{attempt,id}' THEN
    RAISE EXCEPTION 'Reserva repetida nao preservou tentativa';
  END IF;
  IF (SELECT next_homologation_number FROM fiscal_profiles WHERE company_id=c)<>2 THEN
    RAISE EXCEPTION 'Numeracao foi consumida duas vezes';
  END IF;
  BEGIN
    PERFORM reserve_homologation(c,gen_random_uuid(),now(),current_date);
    RAISE EXCEPTION 'Aceitou rascunho inexistente';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
  END;
END;
$$;
ROLLBACK;
