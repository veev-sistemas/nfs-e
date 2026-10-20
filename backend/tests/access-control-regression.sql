\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE c uuid; session_token text; r jsonb; i integer;
BEGIN
  INSERT INTO companies(name,document) VALUES('Access regression','99999999999999') RETURNING id INTO c;
  PERFORM set_company_password(c,'Regression-password-2026');
  FOR i IN 1..5 LOOP
    r:=login_company('99999999999999','Wrong-password-2026');
    IF NOT r ? 'error' THEN RAISE EXCEPTION 'Invalid login accepted'; END IF;
  END LOOP;
  r:=login_company('99999999999999','Regression-password-2026');
  IF NOT r ? 'error' THEN RAISE EXCEPTION 'Lockout ignored'; END IF;
  UPDATE company_users SET locked_until=now()-interval '1 second' WHERE company_id=c;
  r:=login_company('99999999999999','Regression-password-2026');
  session_token:=r->>'access_token';
  IF session_token IS NULL THEN RAISE EXCEPTION 'Valid login rejected'; END IF;
  IF NOT EXISTS(SELECT 1 FROM access_sessions WHERE token_hash=encode(digest(session_token,'sha256'),'hex')) THEN
    RAISE EXCEPTION 'Session not stored'; END IF;
  PERFORM set_company_access(c,false);
  IF EXISTS(SELECT 1 FROM access_sessions s JOIN company_users u ON u.id=s.user_id WHERE u.company_id=c) THEN
    RAISE EXCEPTION 'Block failed to revoke sessions'; END IF;
  r:=login_company('99999999999999','Regression-password-2026');
  IF NOT r ? 'error' THEN RAISE EXCEPTION 'Blocked company logged in'; END IF;
  PERFORM set_company_access(c,true);
  PERFORM set_company_password(c,'Replacement-password-2026');
  r:=login_company('99999999999999','Regression-password-2026');
  IF NOT r ? 'error' THEN RAISE EXCEPTION 'Old password accepted'; END IF;
  r:=login_company('99999999999999','Replacement-password-2026');
  IF NOT r ? 'access_token' THEN RAISE EXCEPTION 'Replacement password rejected'; END IF;
END $$;
ROLLBACK;
