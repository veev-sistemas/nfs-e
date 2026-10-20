"""Only for isolated nfse_access_test, started by access-http-regression.sh."""
import json
import subprocess
import urllib.request
import urllib.error

BASE='http://127.0.0.1:19002'

def request(path, method='GET', body=None, token=None):
    req=urllib.request.Request(BASE+path,method=method,
        headers={'Content-Type':'application/json; charset=utf-8',**({'Authorization':'Bearer '+token} if token else {})},
        data=json.dumps(body).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(req,timeout=20) as res: return res.status,json.load(res)
    except urllib.error.HTTPError as error: return error.code,json.load(error)

def sql(command):
    result=subprocess.run(['runuser','-u','postgres','--','psql','-v','ON_ERROR_STOP=1',
        '-At','-d','nfse_access_test','-c',command],capture_output=True,text=True,check=True)
    return result.stdout.strip()

def login_company(document,password):
    status,result=request('/v1/auth/login','POST',{'cnpj':document,'password':password})
    assert status==200,(status,result)
    return result['access_token']

tenant=login_company('99999999999999','Regression-password-2026')
assert request('/v1/admin/companies')[0]==401
assert request('/v1/admin/companies',token=tenant)[0]==403
assert request('/v1/admin/companies','POST',{},tenant)[0]==403
assert request('/v1/admin/companies',token='admin_'+'a'*64)[0]==401
assert request('/v1/admin/auth/login','POST',{'username':'regression-admin','password':'Wrong-password-2026'})[0]==401
status,result=request('/v1/admin/auth/login','POST',{'username':'regression-admin','password':'Admin-regression-2026'})
assert status==200,(status,result)
admin=result['access_token']
assert request('/v1/admin/auth/me',token=admin)==(200,{'username':'regression-admin'})
assert request('/v1/auth/me',token=admin)[0]==401

registration={'name':'EMPRESA DE ENSAIO <script>','cnpj':'12.345.678/0001-99','password':'Company-regression-2026',
    'fiscal_profile':{'municipality_code':'3136702','municipality_name':'Juiz de Fora','state_code':'MG',
        'street':'RUA DE TESTE','house_number':'1','district':'CENTRO','postal_code':'36000000','homologation_series':'901'}}
status,company=request('/v1/admin/companies','POST',registration,admin)
assert status==201,(status,company)
company_id=company['id']
assert 'password' not in company and company['access_enabled'] is True
assert request('/v1/admin/companies','POST',registration,admin)[0]==409
bad=dict(registration,cnpj='77777777777777',fiscal_profile=dict(registration['fiscal_profile'],postal_code='ABC'))
assert request('/v1/admin/companies','POST',bad,admin)[0]==422
assert sql("select count(*) from companies where document='77777777777777'")=='0'
listing=request('/v1/admin/companies',token=admin)[1]
assert next(c for c in listing if c['id']==company_id)['has_fiscal_profile'] is True
assert all('password_hash' not in c and 'password' not in c for c in listing)
new_token=login_company('12345678000199','Company-regression-2026')
key='b'*64
sql("insert into api_keys(company_id,token_hash) values('%s',encode(digest('%s','sha256'),'hex'))"%(company_id,key))
assert request('/v1/admin/companies/'+company_id+'/access','PATCH',{'enabled':'false'},admin)[0]==422
assert request('/v1/admin/companies/'+company_id+'/access','PATCH',{'enabled':False},admin)[0]==200
assert request('/v1/auth/me',token=new_token)[0]==401
assert request('/v1/auth/me',token=key)[0]==401
assert request('/v1/auth/me',token=tenant)[0]==200
assert request('/v1/admin/companies/'+company_id+'/access','PATCH',{'enabled':True},admin)[0]==200
assert request('/v1/auth/me',token=new_token)[0]==401
new_token=login_company('12345678000199','Company-regression-2026')
assert request('/v1/admin/companies/'+company_id+'/password','POST',{'password':'short'},admin)[0]==422
assert request('/v1/auth/me',token=new_token)[0]==200
assert request('/v1/admin/companies/'+company_id+'/password','POST',{'password':'New-company-password-2026'},admin)[0]==200
assert request('/v1/auth/me',token=new_token)[0]==401
assert request('/v1/auth/login','POST',{'cnpj':'12345678000199','password':'Company-regression-2026'})[0]==401
new_token=login_company('12345678000199','New-company-password-2026')
assert request('/v1/admin/companies',token=new_token)[0]==403
actions=sql("select string_agg(action,',') from admin_audit where company_id='%s'"%company_id)
for action in ['company_created','company_blocked','company_unblocked','company_password_reset']: assert action in actions

status,customer=request('/v1/customers','POST',{'name':' José da Silva ','document':'11144477735'},tenant)
assert status==201 and customer['name']=='JOSÉ DA SILVA',(status,customer)
sql("update customers set name='joão oliveira' where id='%s'"%customer['id'])
assert next(c for c in request('/v1/customers',token=tenant)[1] if c['id']==customer['id'])['name']=='JOÃO OLIVEIRA'

# More than 100 later invoices: filtering must happen in SQL before LIMIT.
issuer_company=sql("select id from companies where document='99999999999999'")
sql("""insert into invoices(company_id,environment,access_key,invoice_number,issuer_document,amount_cents,xml_content,xml_sha256)
select '%s','homologacao',lpad(n::text,50,'0'),n::text,'99999999999999',10000,
'<NFSe xmlns="http://www.sped.fazenda.gov.br/nfse"><infNFSe><dhProc>2026-10-20T12:00:00Z</dhProc></infNFSe></NFSe>','fixture'
from generate_series(100,204) n"""%issuer_company)
for n,when in [(1,'2026-10-19T03:00:00Z'),(2,'2026-10-20T02:59:59Z'),(3,'2026-10-19T02:59:59Z'),(4,'2026-10-20T03:00:00Z')]:
    sql("""insert into invoices(company_id,environment,access_key,invoice_number,issuer_document,amount_cents,xml_content,xml_sha256)
    values('%s','homologacao','%s','%s','99999999999999',10000,
    '<NFSe xmlns="http://www.sped.fazenda.gov.br/nfse"><infNFSe><dhProc>%s</dhProc></infNFSe></NFSe>','fixture')"""%(issuer_company,str(n).zfill(50),n,when))
assert len(request('/v1/invoices',token=tenant)[1])==100
status,notes=request('/v1/invoices?date_from=2026-10-19&date_to=2026-10-19',token=tenant)
assert status==200 and {n['invoice_number'] for n in notes}=={'1','2'},(status,notes)
assert all(n['issued_at']!=n['imported_at'] for n in notes)
assert request('/v1/invoices?date_from=2026-10-19&date_to=2026-10-19',token=new_token)==(200,[])
assert {n['invoice_number'] for n in request('/v1/invoices?date_to=2026-10-18',token=tenant)[1]}=={'3'}
for query in ['date_from=2026-10-20&date_to=2026-10-19','date_from=wrong','date_to=2026-02-30',"date_from=2026-10-19%27"]:
    assert request('/v1/invoices?'+query,token=tenant)[0]==422,query

assert request('/v1/admin/auth/logout','POST',token=admin)[0]==200
assert request('/v1/admin/companies',token=admin)[0]==401
status,result=request('/v1/admin/auth/login','POST',{'username':'regression-admin','password':'Admin-regression-2026'})
assert status==200
admin=result['access_token']
sql("update admin_sessions set expires_at=now()-interval '1 second'")
assert request('/v1/admin/companies',token=admin)[0]==401
sql("update admin_users set enabled=false where username='regression-admin'")
assert request('/v1/admin/auth/login','POST',{'username':'regression-admin','password':'Admin-regression-2026'})[0]==401
print('OK: admin separado, cadastro atomico, bloqueio, reset, auditoria, isolamento, expiracao/logout; tomador em caixa alta; datas inclusivas em Brasilia e filtro antes do limite.')
