"""Local isolated DB + HTTP regression. Both fiscal network flags are disabled."""
import json
import subprocess
import urllib.request
import urllib.error
from concurrent.futures import ThreadPoolExecutor

def sql(statement):
    return subprocess.check_output(['runuser','-u','postgres','--','psql','-XAt','-v','ON_ERROR_STOP=1','-d','nfse_access_test','-c',statement],text=True).strip()

def request(path,method='GET',body=None,token=None):
    req=urllib.request.Request('http://127.0.0.1:19002'+path,method=method,
        headers={'Content-Type':'application/json; charset=utf-8',**({'Authorization':'Bearer '+token} if token else {})},
        data=json.dumps(body).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(req,timeout=30) as response:return response.status,json.load(response)
    except urllib.error.HTTPError as error:return error.code,json.load(error)

admin=request('/v1/admin/auth/login','POST',{'username':'regression-admin','password':'Admin-regression-2026'})[1]['access_token']
tenant=request('/v1/auth/login','POST',{'cnpj':'99999999999999','password':'Regression-password-2026'})[1]['access_token']
company=sql("select id from companies where document='99999999999999'")
env='/v1/admin/companies/'+company+'/environment'
assert request(env,'PATCH',{'environment':'homologacao'},tenant)[0]==403
assert request(env,'PATCH',{'environment':'invalid'},admin)[0]==422
assert request(env,'PATCH',{'environment':'homologacao'},admin)[0]==200
assert request('/v1/emission-config',token=tenant)[1]['active_environment']=='homologacao'
assert request('/v1/drafts','POST',{'environment':'producao','amount_cents':10000},tenant)[0]==422
assert request('/v1/drafts','POST',{'environment':'homologacao','amount_cents':10000},tenant)[0]==201
assert 'environment_homologacao' in sql("select string_agg(action,',') from admin_audit where company_id='%s'"%company)

invoice=sql("select id from invoices where company_id='%s' and status='authorized_production' limit 1"%company)
sql("update invoices set source='sefin_api' where id='%s'"%invoice)
key=sql("select access_key from invoices where id='%s'"%invoice)
url='/v1/invoices/'+invoice
body={'reason_code':'2','reason':'Servico nao prestado, teste local','confirm_cancellation':True}
assert request(url+'/cancel','POST',dict(body,confirm_cancellation='true'),tenant)[0]==422
assert request(url+'/cancel','POST',dict(body,reason_code='99'),tenant)[0]==422
assert request(url+'/cancel','POST',body,tenant)[0]==422 # server disabled, never transmits
assert sql("select count(*) from cancellation_attempts")=='0'
other='00000000-0000-4000-8000-000000000000'
assert request('/v1/invoices/'+other+'/cancel','POST',body,tenant)[0]==422
assert request('/v1/invoices/'+other+'/cancellation',token=tenant)[0]==404

def reserve(_):
    return json.loads(sql("select reserve_cancellation('%s','%s',2,'Servico nao prestado, teste local')"%(company,invoice)))
with ThreadPoolExecutor(max_workers=6) as pool: reservations=list(pool.map(reserve,range(6)))
assert sum(a['created'] for a in reservations)==1
attempt=reservations[0]['attempt']['id']
sql("select finish_cancellation('%s','%s','unknown','{}',null)"%(company,attempt))
assert request(url+'/cancel','POST',body,tenant)[1]['status']=='unknown' # no retry, despite disabled transport
assert request(url+'/cancellation',token=tenant)[1]['status']=='unknown'
assert request(url+'/cancellation/xml',token=tenant)[0]==404
assert sql("select status from invoices where id='%s'"%invoice)=='authorized_production'

# A different synthetic authorized invoice: reject wrong key/env/author, then confirm.
second=sql("""insert into invoices(company_id,environment,access_key,invoice_number,issuer_document,amount_cents,xml_content,xml_sha256,status,source)
select company_id,environment,repeat('8',50),'888',issuer_document,amount_cents,xml_content,'fixture','authorized_production','sefin_api'
from invoices where id='%s' returning id"""%invoice).splitlines()[0]
second_key='8'*50
second_attempt=json.loads(sql("select reserve_cancellation('%s','%s',1,'Erro de emissao em teste local')"%(company,second)))['attempt']['id']
event='<evento xmlns="http://www.sped.fazenda.gov.br/nfse"><infEvento><pedRegEvento><infPedReg><tpAmb>1</tpAmb><CNPJAutor>99999999999999</CNPJAutor><chNFSe>'+second_key+'</chNFSe><e101101><cMotivo>1</cMotivo><xMotivo>Erro de emissao em teste local</xMotivo></e101101></infPedReg></pedRegEvento></infEvento></evento>'
for wrong in [event.replace(second_key,key),event.replace('<tpAmb>1','<tpAmb>2'),event.replace('99999999999999','11111111111111')]:
    try:sql("select finish_cancellation('%s','%s','cancelled','{}',$xml$%s$xml$)"%(company,second_attempt,wrong))
    except subprocess.CalledProcessError:pass
    else:raise AssertionError('mismatched cancellation accepted')
    assert sql("select status from invoices where id='%s'"%second)=='authorized_production'
sql("select finish_cancellation('%s','%s','cancelled','{}',$xml$%s$xml$)"%(company,second_attempt,event))
assert sql("select status from invoices where id='%s'"%second)=='cancelled'
assert request('/v1/invoices/'+second+'/pdf',token=tenant)[0]==422
status,notes=request('/v1/invoices?environment=producao&status=cancelled',token=tenant)
assert status==200 and [n['id'] for n in notes]==[second],(status,notes)
assert all(n['status'].startswith('authorized_') for n in request('/v1/invoices?status=authorized',token=tenant)[1])
assert request('/v1/invoices?status=invalid',token=tenant)[0]==422

# XML recipient takes precedence over mutable customer names, preserves Unicode.
sql("""update invoices set xml_content=replace(xml_content,'<tpAmb>1</tpAmb>','<tpAmb>1</tpAmb><toma><xNome>TOMADOR JOSÉ &amp; FILHOS</xNome></toma>') where id='%s'"""%second)
note=request('/v1/invoices?environment=producao&status=cancelled',token=tenant)[1][0]
assert note['customer_name']=='TOMADOR JOSÉ & FILHOS',note
print('PASS: ambiente alteravel somente no admin, filtros e tomador, cancelamento concorrente/idempotente, resultado inconclusivo sem reenvio, evento vinculado a chave/CNPJ/ambiente. Sem transmissao fiscal.')
