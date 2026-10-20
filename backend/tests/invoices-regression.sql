-- Rodar com psql -v ON_ERROR_STOP=1 apos a migracao 003, em banco de testes.
-- Todos os dados desta verificacao sao revertidos.
BEGIN;
DO $$
DECLARE
  tenant uuid;
  other_tenant uuid;
  document text := '11111111111111';
  access text;
  payload text;
  first_result jsonb;
  repeated_result jsonb;
BEGIN
  INSERT INTO companies(name,document) VALUES ('Teste importacao',document) RETURNING id INTO tenant;
  INSERT INTO companies(name,document) VALUES ('Outra empresa','22222222222222') RETURNING id INTO other_tenant;
  access := '3136702' || '2' || '2' || document || repeat('0',27);
  payload := '<NFSe xmlns="http://www.sped.fazenda.gov.br/nfse"><infNFSe Id="NFS' || access ||
    '"><nNFSe>1</nNFSe><emit><CNPJ>' || document || '</CNPJ></emit><DPS><infDPS><tpAmb>2</tpAmb><prest><CNPJ>' || document ||
    '</CNPJ></prest><valores><vServPrest><vServ>100.00</vServ></vServPrest></valores></infDPS></DPS></infNFSe></NFSe>';
  first_result := import_homologation_invoice(tenant,NULL,payload);
  repeated_result := import_homologation_invoice(tenant,NULL,payload);
  IF first_result->>'id' <> repeated_result->>'id' OR first_result->>'amount_cents' <> '10000' OR
     first_result->>'status' <> 'imported' THEN RAISE EXCEPTION 'Falha de importacao/idempotencia'; END IF;
  BEGIN
    PERFORM import_homologation_invoice(other_tenant,NULL,payload);
    RAISE EXCEPTION 'Aceitou CNPJ de outra empresa';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
  END;
  BEGIN
    PERFORM import_homologation_invoice(tenant,NULL,replace(payload,'<tpAmb>2</tpAmb>','<tpAmb>1</tpAmb>'));
    RAISE EXCEPTION 'Aceitou producao';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
  END;
  BEGIN
    PERFORM import_homologation_invoice(tenant,NULL,replace(payload,'100.00','200.00'));
    RAISE EXCEPTION 'Sobrescreveu XML com mesma chave';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  BEGIN
    PERFORM import_homologation_invoice(tenant,NULL,'<!DOCTYPE NFSe [<!ENTITY x SYSTEM "file:///etc/passwd">]>' || payload);
    RAISE EXCEPTION 'Aceitou DTD';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
  END;
  BEGIN
    PERFORM import_homologation_invoice(tenant,gen_random_uuid(),payload);
    RAISE EXCEPTION 'Aceitou rascunho inexistente';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
  END;
END;
$$;
ROLLBACK;
