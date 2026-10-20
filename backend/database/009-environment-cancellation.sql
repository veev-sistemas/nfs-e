BEGIN;
ALTER TABLE company_emission_config ADD COLUMN active_environment text NOT NULL DEFAULT 'homologacao'
  CHECK(active_environment IN ('homologacao','producao'));
ALTER TABLE invoices DROP CONSTRAINT invoices_status_check;
ALTER TABLE invoices ADD CHECK(status IN ('imported','authorized_homologation','authorized_production','cancelled'));
CREATE TABLE cancellation_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id),
  invoice_id uuid NOT NULL REFERENCES invoices(id),
  status text NOT NULL CHECK(status IN ('sending','unknown','rejected','cancelled')),
  reason_code integer NOT NULL CHECK(reason_code IN (1,2,9)),
  reason text NOT NULL CHECK(length(reason) BETWEEN 15 AND 255),
  event_xml text,
  result jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX cancellation_unresolved ON cancellation_attempts(invoice_id)
  WHERE status IN ('sending','unknown','cancelled');
CREATE INDEX cancellation_company ON cancellation_attempts(company_id,invoice_id,created_at DESC);

-- Row lock + partial unique index prevent retransmission across processes.
CREATE FUNCTION reserve_cancellation(p_company uuid,p_invoice uuid,p_code integer,p_reason text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE i invoices%ROWTYPE; a cancellation_attempts%ROWTYPE;
BEGIN
  SELECT * INTO i FROM invoices WHERE id=p_invoice AND company_id=p_company FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Nota nao encontrada.'; END IF;
  SELECT * INTO a FROM cancellation_attempts WHERE invoice_id=i.id AND status IN ('sending','unknown','cancelled') LIMIT 1;
  IF FOUND THEN RETURN jsonb_build_object('created',false,'attempt',to_jsonb(a)-'event_xml'); END IF;
  IF i.status NOT IN ('authorized_homologation','authorized_production') OR i.source<>'sefin_api' THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Somente notas autorizadas pela SEFIN podem ser canceladas.';
  END IF;
  INSERT INTO cancellation_attempts(company_id,invoice_id,status,reason_code,reason)
    VALUES(p_company,p_invoice,'sending',p_code,p_reason) RETURNING * INTO a;
  RETURN jsonb_build_object('created',true,'attempt',to_jsonb(a)-'event_xml');
END $$;

CREATE FUNCTION finish_cancellation(p_company uuid,p_attempt uuid,p_status text,p_result jsonb,p_xml text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE a cancellation_attempts%ROWTYPE; i invoices%ROWTYPE; doc xml;
  ns text[][]:=ARRAY[ARRAY['n','http://www.sped.fazenda.gov.br/nfse']];
BEGIN
  SELECT * INTO a FROM cancellation_attempts WHERE id=p_attempt AND company_id=p_company FOR UPDATE;
  IF NOT FOUND OR a.status<>'sending' OR p_status NOT IN ('unknown','rejected','cancelled') THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Estado de cancelamento invalido.';
  END IF;
  IF p_status='cancelled' THEN
    SELECT * INTO STRICT i FROM invoices WHERE id=a.invoice_id AND company_id=p_company FOR UPDATE;
    IF p_xml IS NULL OR octet_length(p_xml)>524288 OR p_xml ~* '<![[:space:]]*(DOCTYPE|ENTITY)' THEN
      RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Evento de cancelamento invalido.';
    END IF;
    doc:=XMLPARSE(DOCUMENT p_xml);
    IF cardinality(xpath('/n:evento/n:infEvento/n:pedRegEvento/n:infPedReg/n:e101101',doc,ns))<>1
      OR (xpath('string(/n:evento/n:infEvento/n:pedRegEvento/n:infPedReg/n:chNFSe)',doc,ns))[1]::text IS DISTINCT FROM i.access_key
      OR (xpath('string(/n:evento/n:infEvento/n:pedRegEvento/n:infPedReg/n:CNPJAutor)',doc,ns))[1]::text IS DISTINCT FROM i.issuer_document
      OR (xpath('string(/n:evento/n:infEvento/n:pedRegEvento/n:infPedReg/n:tpAmb)',doc,ns))[1]::text IS DISTINCT FROM (CASE i.environment WHEN 'producao' THEN '1' ELSE '2' END) THEN
      RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='Evento nao corresponde a nota e ao ambiente.';
    END IF;
    UPDATE invoices SET status='cancelled' WHERE id=i.id;
  END IF;
  UPDATE cancellation_attempts SET status=p_status,result=p_result,event_xml=nullif(p_xml,''),updated_at=now() WHERE id=a.id;
END $$;
REVOKE ALL ON cancellation_attempts FROM PUBLIC;
REVOKE ALL ON FUNCTION reserve_cancellation(uuid,uuid,integer,text),finish_cancellation(uuid,uuid,text,jsonb,text) FROM PUBLIC;
COMMIT;
