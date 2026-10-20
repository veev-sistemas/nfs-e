"""Run against an isolated local database seeded by access-http-regression.sh."""
import json
import urllib.request
import urllib.error
import subprocess

BASE = 'http://127.0.0.1:19002'


def request(path, method='GET', body=None, token=None):
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    req = urllib.request.Request(BASE + path, headers=headers, method=method,
        data=json.dumps(body).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, json.load(error)


def sql(command):
    subprocess.run(['runuser', '-u', 'postgres', '--', 'psql', '-v',
        'ON_ERROR_STOP=1', '-d', 'nfse_access_test', '-c', command], check=True,
        stdout=subprocess.DEVNULL)


status, data = request('/v1/auth/login', 'POST',
    {'cnpj': '99.999.999/9999-99', 'password': 'Regression-password-2026'})
assert status == 200, (status, data)
token = data['access_token']
assert request('/v1/auth/me', token=token)[1]['document'] == '99999999999999'
assert request('/v1/settings', token=token) == (200, {})
assert request('/v1/drafts', token=token) == (200, [])
assert request('/v1/invoices', token=token) == (200, [])
sql("INSERT INTO drafts(company_id,customer_id,amount_cents,settings_snapshot) "
    "SELECT id,NULL,10000,'{}' FROM companies WHERE document='99999999999999'; "
    "INSERT INTO emission_attempts(company_id,draft_id,dps_number,dps_series,issued_at,competence,status,request_snapshot) "
    "SELECT company_id,id,1,'901',now(),current_date,'unknown','{}' FROM drafts")
drafts = request('/v1/drafts', token=token)
assert drafts[0] == 200 and drafts[1][0]['attempt_status'] == 'unknown'
assert drafts[1][0]['attempt_id']
defaults = {'tax_regime':'simples_nacional','service_code':'090103',
    'service_description':'Teste local','send_ibs_cbs':False,'cclass_trib':'200048',
    'cst_ibs_cbs':'200','cind_op':'030101'}
status, settings = request('/v1/settings','PATCH',defaults,token)
assert status == 200 and settings['send_ibs_cbs'] is False
assert settings['cclass_trib'] == '200048'
assert settings['cind_op'] == '030101' and settings['cst_ibs_cbs'] == '200'
status, snapshot = request('/v1/drafts','POST',{'amount_cents':10000},token)
assert status == 201, (status,snapshot)
assert snapshot['settings']['send_ibs_cbs'] is False
assert snapshot['settings']['cclass_trib'] == '200048'
assert snapshot['settings']['cind_op'] == '030101'
assert request('/v1/settings','PATCH',{'send_ibs_cbs':True},token)[0] == 200
saved = request('/v1/drafts',token=token)[1]
assert next(d for d in saved if d['id']==snapshot['id'])['settings']['send_ibs_cbs'] is False
assert request('/v1/settings','PATCH',{'send_ibs_cbs':'false'},token)[0] == 422
assert request('/v1/settings','PATCH',{'cclass_trib':1},token)[0] == 422
assert request('/v1/settings','PATCH',{'cclass_trib':'00001'},token)[0] == 422
assert request('/v1/settings','PATCH',{'cind_op':30101},token)[0] == 422
assert request('/v1/settings','PATCH',{'cind_op':'03010'},token)[0] == 422
assert request('/v1/settings','PATCH',{'cst_ibs_cbs':200},token)[0] == 422
assert request('/v1/settings','PATCH',{'cst_ibs_cbs':'20'},token)[0] == 422
assert request('/v1/settings','PATCH',{'send_ibs_cbs':False},token)[0] == 200
sql("INSERT INTO companies(name,document) VALUES('Other company','88888888888888'); "
    "INSERT INTO customers(company_id,name,document) SELECT id,'Other customer','11111111111' "
    "FROM companies WHERE document='88888888888888'")
assert request('/v1/customers', token=token) == (200, [])
assert request('/v1/auth/me')[0] == 401
assert request('/v1/auth/me', token='x'*64)[0] == 401
assert request('/v1/auth/logout', 'POST', token=token)[0] == 200
assert request('/v1/auth/me', token=token)[0] == 401
status, data = request('/v1/auth/login', 'POST',
    {'cnpj': '99999999999999', 'password': 'Regression-password-2026'})
token = data['access_token']
company = data['company_id']
sql("UPDATE access_sessions SET expires_at=now()-interval '1 second'")
assert request('/v1/auth/me', token=token)[0] == 401
status, data = request('/v1/auth/login', 'POST',
    {'cnpj': '99999999999999', 'password': 'Regression-password-2026'})
token = data['access_token']
key = 'a'*64
sql("INSERT INTO api_keys(company_id,token_hash) VALUES('%s',encode(digest('%s','sha256'),'hex'))" % (company, key))
assert request('/v1/auth/me', token=key)[0] == 200
sql("SELECT set_company_access('%s',false)" % company)
assert request('/v1/auth/me', token=token)[0] == 401
assert request('/v1/auth/me', token=key)[0] == 401
assert request('/v1/auth/login', 'POST', {'cnpj': '99999999999999',
    'password': 'Regression-password-2026'})[0] == 401
sql("SELECT set_company_access('%s',true)" % company)
assert request('/v1/auth/me', token=token)[0] == 401
assert request('/v1/auth/me', token=key)[0] == 200
print('OK: login, isolation, expiry, logout, invalid credentials, company block and API key block.')
