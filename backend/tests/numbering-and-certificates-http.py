"""Isolated nfse_access_test only; no transmission, no actual certificates."""
import base64
from concurrent.futures import ThreadPoolExecutor
import json
import subprocess
import urllib.request
import urllib.error
import importlib.util
from pathlib import Path
spec=importlib.util.spec_from_file_location('certificate_fixture',Path(__file__).with_name('certificates-regression.py'))
fixtures=importlib.util.module_from_spec(spec);spec.loader.exec_module(fixtures)
fixture=fixtures.fixture

def sql(command):
    return subprocess.run(['runuser','-u','postgres','--','psql','-v','ON_ERROR_STOP=1','-At','-d','nfse_access_test','-c',command],capture_output=True,text=True,check=True).stdout.strip()

def request(path, method='GET', body=None, token=None):
    req=urllib.request.Request('http://127.0.0.1:19002'+path,method=method,
        headers={'Content-Type':'application/json; charset=utf-8',**({'Authorization':'Bearer '+token} if token else {})},
        data=json.dumps(body).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(req,timeout=30) as response:return response.status,json.load(response)
    except urllib.error.HTTPError as error:return error.code,json.load(error)

sql("UPDATE admin_users SET enabled=true,failed_attempts=0,locked_until=NULL WHERE username='regression-admin'")
admin=request('/v1/admin/auth/login','POST',{'username':'regression-admin','password':'Admin-regression-2026'})[1]['access_token']
tenant=request('/v1/auth/login','POST',{'cnpj':'99999999999999','password':'Regression-password-2026'})[1]['access_token']
company=sql("select id from companies where document='99999999999999'")
sql("insert into fiscal_profiles(company_id,municipality_code,municipality_name,state_code,street,house_number,district,postal_code) values('%s','3136702','Teste','MG','Rua','1','Centro','36000000') on conflict do nothing"%company)
path='/v1/admin/companies/'+company
assert request(path+'/numbering',token=tenant)[0]==403
assert request(path+'/certificate',token=tenant)[0]==403
assert request(path+'/certificate','POST',{},tenant)[0]==403
status,config=request(path+'/numbering',token=admin);assert status==200,(status,config)
initial=next(s['next_number'] for s in config['sequences'] if s['environment']=='homologacao' and s['series']=='901')
body={'environment':'homologacao','series':'901','next_number':'501','expected_next_number':initial}
result=request(path+'/numbering','PATCH',body,admin);assert result[0]==200,result
assert request(path+'/numbering','PATCH',body,admin)[0]==409 # stale screen
assert request(path+'/numbering','PATCH',dict(body,next_number='500',expected_next_number='501'),admin)[0]==409
assert request(path+'/numbering','PATCH',dict(body,next_number=502,expected_next_number='501'),admin)[0]==422
drafts=[sql("insert into drafts(company_id,amount_cents,settings_snapshot) values('%s',10000,'{}') returning id"%company).splitlines()[0] for _ in range(6)]
def reserve(draft):
    return json.loads(sql("select reserve_homologation('%s','%s',now()-interval '1 minute',current_date)"%(company,draft)))
with ThreadPoolExecutor(max_workers=6) as pool:attempts=list(pool.map(reserve,drafts))
assert sorted(a['attempt']['dps_number'] for a in attempts)==list(range(501,507))
with ThreadPoolExecutor(max_workers=6) as pool:repeats=list(pool.map(reserve,[drafts[0]]*6))
assert all(not r['created'] for r in repeats)
assert len({r['attempt']['id'] for r in repeats})==1
same_draft=sql("insert into drafts(company_id,amount_cents,settings_snapshot) values('%s',10000,'{}') returning id"%company).splitlines()[0]
with ThreadPoolExecutor(max_workers=6) as pool:simultaneous=list(pool.map(reserve,[same_draft]*6))
assert sum(r['created'] for r in simultaneous)==1
assert len({r['attempt']['id'] for r in simultaneous})==1
body['expected_next_number']='506';body['next_number']='800'
assert request(path+'/numbering','PATCH',body,admin)[0]==409 # emission after page load
for environment,series,number,expected in [('homologacao','902','1',None),('homologacao','901','506','508'),('producao','901','501',None)]:
    result=request(path+'/numbering','PATCH',dict(environment=environment,series=series,next_number=number,expected_next_number=expected),admin)
    assert result[0]==(409 if number=='506' else 200),result
assert sql("select next_number from dps_sequences where company_id='%s' and environment='homologacao' and series='901'"%company)=='508'
try:sql("update dps_sequences set next_number=1 where company_id='%s' and series='901'"%company)
except subprocess.CalledProcessError:pass
else:raise AssertionError('database accepted sequence rewind')
assert request(path+'/certificate',token=admin)==(200,{'configured':False})
pfx=fixture();payload={'pfx_base64':base64.b64encode(pfx).decode(),'password':'Senha-certificado-2026'}
status,cert=request(path+'/certificate','POST',payload,admin)
assert status==200,(status,cert)
assert cert['configured'] and cert['source']=='encrypted' and 'password' not in cert and 'pfx_base64' not in cert
assert request(path+'/certificate','POST',dict(payload,password='wrong'),admin)[0]==422
assert request(path+'/certificate',token=admin)[1]['fingerprint_sha256']==cert['fingerprint_sha256']
assert 'company_certificate_uploaded' in sql("select action from admin_audit where company_id='%s'"%company)
print('PASS: sequencias atomicas, concorrencia, repeticao idempotente, tela desatualizada, ambientes, isolamento, certificado e senha invalida.')
