"""Local isolated database/API; no real customer data or fiscal sends."""
import json,subprocess,urllib.request,urllib.error

def sql(s):return subprocess.check_output(['runuser','-u','postgres','--','psql','-XqAt','-v','ON_ERROR_STOP=1','-d','nfse_access_test','-c',s],text=True).strip()
def api(path,method='GET',body=None,token=None):
 req=urllib.request.Request('http://127.0.0.1:19002/v1/'+path,method=method,data=json.dumps(body).encode() if body is not None else None,headers={'Content-Type':'application/json',**({'Authorization':'Bearer '+token} if token else {})})
 try:
  with urllib.request.urlopen(req,timeout=20) as r:return r.status,json.load(r)
 except urllib.error.HTTPError as e:return e.code,json.load(e)
token=api('auth/login','POST',{'cnpj':'99999999999999','password':'Regression-password-2026'})[1]['access_token']
base={'name':'Contato de teste','document':'12345678901'}
status,legacy=api('customers','POST',base,token);assert status==201,(status,legacy)
assert 'email' not in legacy
full=dict(base,phone='(21) 99999-0000',email='cliente@example.com',postal_code='27600-000',municipality_code='3306107',municipality_name='Valença',state_code='RJ',district='CENTRO',street='RUA TESTE',house_number='74',complement='SALA 2')
status,customer=api('customers/'+legacy['id'],'PATCH',full,token);assert status==200,(status,customer)
assert customer['phone']=='21999990000' and customer['postal_code']=='27600000'
assert next(c for c in api('customers',token=token)[1] if c['id']==legacy['id'])['email']=='cliente@example.com'
for changes in [{'phone':'abc'},{'email':'bad'},{'postal_code':'123'},{'state_code':'MG'},{'street':''}]:
 assert api('customers/'+legacy['id'],'PATCH',dict(full,**changes),token)[0]==422,changes
other=api('auth/login','POST',{'cnpj':'44444444444444','password':'Payments-regression-2026'})[1]['access_token']
assert api('customers/'+legacy['id'],'PATCH',full,other)[0]==404
assert api('postal-codes/abc',token=token)[0]==422
assert api('postal-codes/01001000')[0]==401
# Freeze contact/address in reservation; later edits cannot change the attempt.
company=sql("select id from companies where document='99999999999999'")
status,draft=api('drafts','POST',{'environment':'homologacao','customer_id':legacy['id'],'amount_cents':100},token);assert status==201,(status,draft)
attempt=json.loads(sql("select reserve_emission('%s','%s',now()-interval '1 minute',current_date,'homologacao')"%(company,draft['id'])))['attempt']
assert attempt['request_snapshot']['customer']['street']=='RUA TESTE'
assert api('customers/'+legacy['id'],'PATCH',base,token)[0]==200
stored=json.loads(sql("select request_snapshot::text from emission_attempts where id='%s'"%attempt['id']))
assert stored['customer']['email']=='cliente@example.com'
assert 'email' not in next(c for c in api('customers',token=token)[1] if c['id']==legacy['id'])
print('OK: contato/endereço opcionais, edição, validação, isolamento e snapshot imutável; CEP autenticado.')
