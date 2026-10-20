"""ONLY nfse_access_test; SQL/HTTP guards and synthetic XML. No fiscal network calls."""
import importlib.util
import json
from pathlib import Path
import subprocess
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

def sql(command):
    return subprocess.run(['runuser','-u','postgres','--','psql','-v','ON_ERROR_STOP=1','-At','-d','nfse_access_test','-c',command],capture_output=True,text=True,check=True).stdout.strip()

def request(path, method='GET', body=None, token=None):
    req=urllib.request.Request('http://127.0.0.1:19002'+path,method=method,headers={'Content-Type':'application/json',**({'Authorization':'Bearer '+token} if token else {})},data=json.dumps(body).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(req,timeout=30) as response:return response.status,json.load(response)
    except urllib.error.HTTPError as error:return error.code,json.load(error)

admin=request('/v1/admin/auth/login','POST',{'username':'regression-admin','password':'Admin-regression-2026'})[1]['access_token']
tenant=request('/v1/auth/login','POST',{'cnpj':'99999999999999','password':'Regression-password-2026'})[1]['access_token']
company=sql("select id from companies where document='99999999999999'")
path='/v1/admin/companies/'+company+'/production'
assert request(path,token=tenant)[0]==403
assert request(path,'PATCH',{'enabled':True,'series':'901'},tenant)[0]==403
assert request(path,'PATCH',{'enabled':True,'series':'902'},admin)[0]==422 # missing sequence
assert request(path,'PATCH',{'enabled':'true','series':'901'},admin)[0]==422
assert request(path,'PATCH',{'enabled':True,'series':'901'},admin)[0]==200 # synthetic cert installed by prior test
config=request('/v1/emission-config',token=tenant)[1]
assert config['production_enabled'] and config['production_available'] is False and config['server_enabled'] is False
assert request('/v1/admin/companies/'+company+'/environment','PATCH',{'environment':'producao'},admin)[0]==200
status,draft=request('/v1/drafts','POST',{'environment':'producao','amount_cents':10000},tenant)
assert status==201,(status,draft)
assert draft['environment']=='producao'
before=sql("select next_number from dps_sequences where company_id='%s' and environment='producao' and series='901'"%company)
body={'issued_at':'2026-10-19T10:00:00-03:00','competence':'2026-10-19'}
url='/v1/drafts/'+draft['id']+'/emit-production'
assert request(url,'POST',body,tenant)[0]==422 # explicit confirmation required
assert request(url,'POST',dict(body,confirm_production='true'),tenant)[0]==422
assert request(url,'POST',dict(body,confirm_production=True),tenant)[0]==422 # server disabled; no network
assert sql("select count(*) from emission_attempts where draft_id='%s'"%draft['id'])=='0'
assert sql("select next_number from dps_sequences where company_id='%s' and environment='producao' and series='901'"%company)==before
assert all(d['environment']=='producao' for d in request('/v1/drafts?environment=producao',token=tenant)[1])
assert draft['id'] not in {d['id'] for d in request('/v1/drafts?environment=homologacao',token=tenant)[1]}
try:sql("select reserve_homologation('%s','%s',now()-interval '1 minute',current_date)"%(company,draft['id']))
except subprocess.CalledProcessError:pass
else:raise AssertionError('cross-environment reservation accepted')
try:sql("update drafts set environment='homologacao' where id='%s'"%draft['id'])
except subprocess.CalledProcessError:pass
else:raise AssertionError('draft environment changed')

def reserve(_):return json.loads(sql("select reserve_emission('%s','%s',now()-interval '1 minute',current_date,'producao')"%(company,draft['id'])))
with ThreadPoolExecutor(max_workers=5) as pool:attempts=list(pool.map(reserve,range(5)))
assert sum(a['created'] for a in attempts)==1
attempt=attempts[0]['attempt'];assert attempt['environment']=='producao' and attempt['dps_number']==int(before)
assert sql("select next_number from dps_sequences where company_id='%s' and environment='homologacao' and series='901'"%company)=='508'

key='0'*9+'99999999999999'+'0'*27
xml=f'''<NFSe xmlns="http://www.sped.fazenda.gov.br/nfse"><infNFSe Id="NFS{key}"><nNFSe>99</nNFSe><cStat>100</cStat><dhProc>2026-10-19T10:00:00-03:00</dhProc><emit><CNPJ>99999999999999</CNPJ></emit><DPS><infDPS><tpAmb>1</tpAmb><nDPS>{before}</nDPS><serie>901</serie><prest><CNPJ>99999999999999</CNPJ></prest><valores><vServPrest><vServ>100.00</vServ></vServPrest></valores></infDPS></DPS></infNFSe></NFSe>'''
def imported(source,environment='producao'):
    return sql("select import_invoice('%s','%s',$xml$%s$xml$,'%s')->>'id'"%(company,draft['id'],source,environment))
try:imported(xml)
except subprocess.CalledProcessError:pass
else:raise AssertionError('unconfirmed production imported')
sql("update emission_attempts set status='authorized' where id='%s'"%attempt['id'])
for bad in [xml.replace('<tpAmb>1','<tpAmb>2'),xml.replace('<serie>901','<serie>902'),xml.replace('<vServ>100.00','<vServ>101.00'),xml.replace('<cStat>100','<cStat>101')]:
    try:imported(bad)
    except subprocess.CalledProcessError:pass
    else:raise AssertionError('inconsistent production XML accepted')
invoice=imported(xml)
sql("update invoices set status='authorized_production' where id='%s'"%invoice)
assert imported(xml)==invoice # exact retry is idempotent
assert any(n['id']==invoice for n in request('/v1/invoices?environment=producao',token=tenant)[1])
assert all(n['id']!=invoice for n in request('/v1/invoices?environment=homologacao',token=tenant)[1])
assert request('/v1/invoices?environment=invalid',token=tenant)[0]==422
assert request(path,'PATCH',{'enabled':False},admin)[0]==200
assert request('/v1/emission-config',token=tenant)[1]['production_enabled'] is False
print('PASS: producao bloqueada no servidor, confirmacao explicita, ambientes imutaveis/separados, reserva concorrente e XML vinculado a DPS autorizada. Nenhuma transmissao.')
