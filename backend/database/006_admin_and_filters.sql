BEGIN;

-- Normaliza cadastros, nunca XMLs ou snapshots de notas ja emitidas.
CREATE FUNCTION normalize_customer_name() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.name := upper(btrim(NEW.name)); RETURN NEW; END $$;
CREATE TRIGGER customers_uppercase BEFORE INSERT OR UPDATE OF name ON customers
FOR EACH ROW EXECUTE FUNCTION normalize_customer_name();
UPDATE customers SET name=upper(btrim(name)) WHERE name IS DISTINCT FROM upper(btrim(name));

CREATE FUNCTION invoice_issue_time(p_xml text,p_fallback timestamptz)
RETURNS timestamptz LANGUAGE plpgsql AS $$
DECLARE value text;
BEGIN
  IF p_xml ~* '<![[:space:]]*(DOCTYPE|ENTITY)' THEN RETURN p_fallback; END IF;
  value := (xpath('string(/n:NFSe/n:infNFSe/n:dhProc)',XMLPARSE(DOCUMENT p_xml),
    ARRAY[ARRAY['n','http://www.sped.fazenda.gov.br/nfse']]))[1]::text;
  RETURN coalesce(nullif(value,'')::timestamptz,p_fallback);
EXCEPTION WHEN OTHERS THEN RETURN p_fallback;
END $$;
ALTER TABLE invoices ADD COLUMN issued_at timestamptz;
UPDATE invoices SET issued_at=invoice_issue_time(xml_content,imported_at);
ALTER TABLE invoices ALTER COLUMN issued_at SET NOT NULL;
CREATE FUNCTION set_invoice_issue_time() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.issued_at := invoice_issue_time(NEW.xml_content,NEW.imported_at); RETURN NEW; END $$;
CREATE TRIGGER invoices_issue_time BEFORE INSERT OR UPDATE OF xml_content,imported_at ON invoices
FOR EACH ROW EXECUTE FUNCTION set_invoice_issue_time();
CREATE INDEX invoices_company_issued ON invoices(company_id,issued_at DESC,id);

CREATE TABLE admin_users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  username text NOT NULL UNIQUE CHECK(username ~ '^[a-z0-9][a-z0-9._@-]{2,99}$'),
  password_hash text NOT NULL,
  enabled boolean NOT NULL DEFAULT true,
  failed_attempts integer NOT NULL DEFAULT 0,
  locked_until timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE admin_sessions (
  token_hash text PRIMARY KEY,
  admin_id uuid NOT NULL REFERENCES admin_users(id),
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX admin_sessions_user ON admin_sessions(admin_id);
CREATE TABLE admin_audit (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  admin_id uuid NOT NULL REFERENCES admin_users(id),
  company_id uuid REFERENCES companies(id),
  action text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
-- Bootstrap/reset de administrador somente no console privado do banco.
CREATE FUNCTION set_admin_password(p_username text,p_password text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_admin_id uuid;
BEGIN
  IF p_username !~ '^[a-z0-9][a-z0-9._@-]{2,99}$' OR octet_length(p_password) NOT BETWEEN 12 AND 72 THEN
    RAISE EXCEPTION 'Usuario ou senha invalidos' USING ERRCODE='22023';
  END IF;
  INSERT INTO admin_users(username,password_hash) VALUES(p_username,crypt(p_password,gen_salt('bf',12)))
  ON CONFLICT(username) DO UPDATE SET password_hash=excluded.password_hash,
    failed_attempts=0,locked_until=NULL,updated_at=now()
  RETURNING id INTO v_admin_id;
  DELETE FROM admin_sessions s WHERE s.admin_id=v_admin_id;
END $$;
CREATE FUNCTION login_admin(p_username text,p_password text) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE account admin_users; token text;
BEGIN
  SELECT * INTO account FROM admin_users WHERE username=p_username FOR UPDATE;
  IF NOT FOUND THEN
    PERFORM crypt(p_password,'$2a$12$abcdefghijklmnopqrstuu');
    RETURN jsonb_build_object('error','Usuario ou senha invalidos.');
  END IF;
  IF account.locked_until>now() THEN RETURN jsonb_build_object('error','Usuario ou senha invalidos.'); END IF;
  IF crypt(p_password,account.password_hash)<>account.password_hash OR NOT account.enabled THEN
    UPDATE admin_users SET
      failed_attempts=CASE WHEN locked_until<=now() THEN 1 ELSE failed_attempts+1 END,
      locked_until=CASE WHEN locked_until<=now() THEN NULL WHEN failed_attempts+1>=5 THEN now()+interval '15 minutes' ELSE NULL END
    WHERE id=account.id;
    INSERT INTO admin_audit(admin_id,action) VALUES(account.id,'login_failed');
    RETURN jsonb_build_object('error','Usuario ou senha invalidos.');
  END IF;
  UPDATE admin_users SET failed_attempts=0,locked_until=NULL WHERE id=account.id;
  DELETE FROM admin_sessions WHERE admin_id=account.id AND expires_at<=now();
  token := 'admin_' || encode(gen_random_bytes(32),'hex');
  INSERT INTO admin_sessions(token_hash,admin_id,expires_at)
    VALUES(encode(digest(token,'sha256'),'hex'),account.id,now()+interval '1 hour');
  INSERT INTO admin_audit(admin_id,action) VALUES(account.id,'login');
  RETURN jsonb_build_object('access_token',token,'username',account.username,'expires_in',3600);
END $$;
REVOKE ALL ON FUNCTION set_admin_password(text,text),login_admin(text,text) FROM PUBLIC;
COMMIT;
