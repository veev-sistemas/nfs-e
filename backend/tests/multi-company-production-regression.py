"""Local nfse_access_test only. Configuration GETs; never sends fiscal documents."""
import json,os,subprocess,tempfile,time,urllib.request
from pathlib import Path
root=Path(__file__).resolve().parents[1]
def sql(s):
 return subprocess.check_output(['runuser','-u','postgres','--','psql','-XqAt','-v','ON_ERROR_STOP=1','-d','nfse_access_test','-c',s],text=True).strip()
def api(path,body=None,token=None):
 req=urllib.request.Request('http://127.0.0.1:19003/v1/'+path,data=json.dumps(body).encode() if body else None,headers={'Content-Type':'application/json',**({'Authorization':'Bearer '+token} if token else {})})
 with urllib.request.urlopen(req,timeout=5) as r:return json.load(r)
with tempfile.TemporaryDirectory(prefix='nfse-multi-') as folder:
 for font in ['arial.ttf','arialbd.ttf','micross.ttf']:Path(folder,font).touch()
 env=dict(os.environ,NFSE_ENABLE_PRODUCTION='1',NFSE_ENABLE_HOMOLOGATION='0',NFSE_PRODUCTION_ALLOWED_CNPJ='00000000000000',NFSE_DANFSE_FONT_DIR=folder,NFSE_PORT='19003',NFSE_BIND='127.0.0.1',NFSE_DB_HOST='127.0.0.1',NFSE_DB_PORT='5432',NFSE_DB_NAME='nfse_access_test',NFSE_DB_USER='nfse_access_runner',NFSE_DB_PASSWORD='local-regression-only')
 with open('/tmp/nfse-multi-production.log','w') as log:
  process=subprocess.Popen([str(root/'build/linux-api/NfseBackend')],env=env,stdout=log,stderr=log)
  ids=[]
  try:
   for _ in range(50):
    try:
     urllib.request.urlopen('http://127.0.0.1:19003/health',timeout=1).close();break
    except Exception:time.sleep(.1)
   for document in ['55555555555555','66666666666666']:
    company=sql("insert into companies(name,document) values('Multi QA','%s') on conflict(document) do update set access_enabled=true returning id"%document);ids.append(company)
    sql("select set_company_password('%s','Multi-regression-2026')"%company)
    sql("insert into company_emission_config(company_id,production_enabled,production_series) values('%s',true,'1') returning company_id"%company)
    sql("insert into dps_sequences(company_id,environment,series,next_number) values('%s','producao','1',411) returning company_id"%company)
    token=api('auth/login',{'cnpj':document,'password':'Multi-regression-2026'})['access_token']
    config=api('emission-config',token=token)
    assert config['production_available'] and config['server_enabled'],config
    sql("update company_emission_config set production_enabled=false where company_id='%s' returning company_id"%company)
    assert not api('emission-config',token=token)['production_available']
    sql("update company_emission_config set production_enabled=true where company_id='%s' returning company_id"%company)
   print('OK: dois CNPJs liberados independentemente do antigo piloto; bloqueio individual preservado; nenhuma emissÃ£o.')
  finally:
   process.terminate();process.wait(timeout=10)
   for company in ids:sql("update companies set access_enabled=false where id='%s' returning id"%company)

