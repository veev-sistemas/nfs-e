BEGIN;
ALTER TABLE companies ADD COLUMN access_enabled boolean NOT NULL DEFAULT true;
CREATE TABLE company_users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL UNIQUE REFERENCES companies(id),
  password_hash text NOT NULL,
  failed_attempts integer NOT NULL DEFAULT 0,
  locked_until timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE access_sessions (
  token_hash text PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES company_users(id),
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX access_sessions_user ON access_sessions(user_id);
CREATE TABLE access_audit (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES companies(id),
  action text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Administrative functions: execute only with the private database console.
-- Passwords use bcrypt; its input limit is 72 bytes, including UTF-8 characters.
CREATE FUNCTION set_company_password(p_company uuid, p_password text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF octet_length(p_password) NOT BETWEEN 12 AND 72 THEN
    RAISE EXCEPTION 'Senha deve ter de 12 a 72 bytes' USING ERRCODE='22023';
  END IF;
  PERFORM 1 FROM companies WHERE id=p_company FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Empresa inexistente'; END IF;
  INSERT INTO company_users(company_id,password_hash)
  VALUES(p_company,crypt(p_password,gen_salt('bf',12)))
  ON CONFLICT(company_id) DO UPDATE SET password_hash=EXCLUDED.password_hash,
    failed_attempts=0,locked_until=NULL,updated_at=now();
  DELETE FROM access_sessions WHERE user_id IN
    (SELECT id FROM company_users WHERE company_id=p_company);
  INSERT INTO access_audit(company_id,action) VALUES(p_company,'password_reset');
END $$;

CREATE FUNCTION set_company_access(p_company uuid,p_enabled boolean) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  UPDATE companies SET access_enabled=p_enabled WHERE id=p_company;
  IF NOT FOUND THEN RAISE EXCEPTION 'Empresa inexistente'; END IF;
  DELETE FROM access_sessions WHERE user_id IN
    (SELECT id FROM company_users WHERE company_id=p_company);
  INSERT INTO access_audit(company_id,action)
    VALUES(p_company,CASE WHEN p_enabled THEN 'unblocked' ELSE 'blocked' END);
END $$;

CREATE FUNCTION login_company(p_document text,p_password text) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE c companies; u company_users; token text; valid boolean;
BEGIN
  SELECT * INTO c FROM companies WHERE document=p_document FOR UPDATE;
  IF NOT FOUND THEN
    -- Comparable bcrypt cost for unknown accounts; no CNPJ enumeration.
    PERFORM crypt(p_password,'$2a$12$abcdefghijklmnopqrstuu');
    RETURN jsonb_build_object('error','CNPJ ou senha invalidos.');
  END IF;
  SELECT * INTO u FROM company_users WHERE company_id=c.id FOR UPDATE;
  IF NOT FOUND THEN
    PERFORM crypt(p_password,'$2a$12$abcdefghijklmnopqrstuu');
    RETURN jsonb_build_object('error','CNPJ ou senha invalidos.');
  END IF;
  IF u.locked_until > now() THEN
    RETURN jsonb_build_object('error','CNPJ ou senha invalidos.');
  END IF;
  valid := crypt(p_password,u.password_hash)=u.password_hash;
  IF NOT valid OR NOT c.access_enabled THEN
    UPDATE company_users SET
      failed_attempts=CASE WHEN locked_until <= now() THEN 1 ELSE failed_attempts+1 END,
      locked_until=CASE WHEN locked_until <= now() THEN NULL
        WHEN failed_attempts+1>=5 THEN now()+interval '15 minutes' ELSE NULL END
      WHERE id=u.id;
    INSERT INTO access_audit(company_id,action) VALUES(c.id,'login_failed');
    RETURN jsonb_build_object('error','CNPJ ou senha invalidos.');
  END IF;
  UPDATE company_users SET failed_attempts=0,locked_until=NULL WHERE id=u.id;
  DELETE FROM access_sessions WHERE user_id=u.id AND expires_at<=now();
  token := 'session_' || encode(gen_random_bytes(32),'hex');
  INSERT INTO access_sessions(token_hash,user_id,expires_at)
    VALUES(encode(digest(token,'sha256'),'hex'),u.id,now()+interval '8 hours');
  INSERT INTO access_audit(company_id,action) VALUES(c.id,'login');
  RETURN jsonb_build_object('access_token',token,'token_type','Bearer',
    'expires_in',28800,'company_id',c.id,'name',c.name,'document',c.document);
END $$;
REVOKE ALL ON FUNCTION set_company_password(uuid,text),set_company_access(uuid,boolean),
  login_company(text,text) FROM PUBLIC;
COMMIT;
