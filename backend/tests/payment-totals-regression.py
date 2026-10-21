"""Isolated nfse_access_test only. No fiscal transmission."""
import json
import subprocess
import urllib.request
import urllib.error

def sql(statement):
    return subprocess.check_output(['runuser','-u','postgres','--','psql','-XAt','-v','ON_ERROR_STOP=1','-d','nfse_access_test','-c',statement],text=True).strip()

def request(path,method='GET',body=None,token=None):
    req=urllib.request.Request('http://127.0.0.1:19002'+path,method=method,
        headers={'Content-Type':'application/json',**({'Authorization':'Bearer '+token} if token else {})},
        data=json.dumps(body).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(req,timeout=30) as res:return res.status,json.load(res)
    except urllib.error.HTTPError as e:return e.code,json.load(e)

document='44444444444444'
company=sql("insert into companies(name,document) values('PAYMENT QA','%s') returning id"%document).splitlines()[0]
sql("select set_company_password('%s','Payments-regression-2026')"%company)
sql("insert into fiscal_defaults(company_id,settings) values('%s','{\"service_code\":\"090103\",\"service_description\":\"TESTE\",\"tax_regime\":\"simples_nacional\"}')"%company)
token=request('/v1/auth/login','POST',{'cnpj':document,'password':'Payments-regression-2026'})[1]['access_token']
methods=['dinheiro','pix','boleto','cartao_credito','cartao_debito']
drafts=[]
for method in methods:
    status,draft=request('/v1/drafts','POST',{'amount_cents':12345,'payment_method':method},token)
    assert status==201 and draft['payment_method']==method,(status,draft)
    drafts.append(draft)
assert {d['payment_method'] for d in request('/v1/drafts',token=token)[1]}==set(methods)
for invalid in ['cheque','PIX','',[],True,42]:
    assert request('/v1/drafts','POST',{'amount_cents':100,'payment_method':invalid},token)[0]==422,invalid
status,legacy=request('/v1/drafts','POST',{'amount_cents':100},token)
assert status==201 and legacy['payment_method'] is None

for n,draft in enumerate(drafts+[legacy]):
    xml='<NFSe xmlns="http://www.sped.fazenda.gov.br/nfse"><infNFSe><dhProc>2026-10-21T12:00:00Z</dhProc><DPS><infDPS><toma><xNome>CLIENTE PAGAMENTO</xNome></toma></infDPS></DPS></infNFSe></NFSe>'
    sql("insert into invoices(company_id,draft_id,environment,access_key,invoice_number,issuer_document,amount_cents,xml_content,xml_sha256) values('%s','%s','homologacao','%s','%s','%s',%s,'%s','fixture')"%(company,draft['id'],str(7000+n).zfill(50),7000+n,document,draft['amount_cents'],xml))
# More than 100 records, including one cancelled and one production invoice.
sql("""insert into invoices(company_id,environment,access_key,invoice_number,issuer_document,amount_cents,xml_content,xml_sha256)
select '%s','homologacao',lpad(n::text,50,'0'),n::text,'%s',100,
'<NFSe xmlns="http://www.sped.fazenda.gov.br/nfse"><infNFSe><dhProc>2026-10-21T12:00:00Z</dhProc></infNFSe></NFSe>','fixture'
from generate_series(8000,8109) n"""%(company,document))
sql("update invoices set status='cancelled' where company_id='%s' and invoice_number='8000'"%company)
sql("""insert into invoices(company_id,environment,access_key,invoice_number,issuer_document,amount_cents,xml_content,xml_sha256)
values('%s','producao','%s','9000','%s',999999,'<NFSe xmlns="http://www.sped.fazenda.gov.br/nfse"><infNFSe><dhProc>2026-10-21T12:00:00Z</dhProc></infNFSe></NFSe>','fixture')"""%(company,str(9000).zfill(50),document))

path='/v1/invoices?include_totals=1&environment=homologacao&date_from=2026-10-21&date_to=2026-10-21'
status,result=request(path,token=token)
assert status==200,(status,result)
s=result['summary']
assert len(result['invoices'])==100 and s['count']==116,s
assert s['cancelled_count']==1 and int(s['cancelled_cents'])==100,s
assert int(s['total_cents'])==5*12345+11000,s
groups={g['payment_method']:g for g in s['by_payment']}
for method in methods:assert groups[method]['count']==1 and int(groups[method]['total_cents'])==12345
assert groups['nao_informado']['count']==110
assert sum(int(g['total_cents']) for g in groups.values())==int(s['total_cents'])
assert any(n['payment_method']=='pix' for n in request(path+'&search=7001',token=token)[1]['invoices'])
assert request(path+'&search=CLIENTE%20PAGAMENTO',token=token)[1]['summary']['count']==6
assert request(path+'&status=cancelled',token=token)[1]['summary']['total_cents']=='0'
assert request(path+'&search=not-found',token=token)[1]['summary']['count']==0
assert request('/v1/invoices?include_totals=1&environment=producao',token=token)[1]['summary']['count']==1
assert request('/v1/invoices?include_totals=1&date_from=2026-01-01&date_to=2026-01-01',token=token)[1]['summary']['count']==0
assert isinstance(request('/v1/invoices',token=token)[1],list) # backwards compatibility
assert request(path)[0]==401
other=request('/v1/auth/login','POST',{'cnpj':'99999999999999','password':'Regression-password-2026'})[1]['access_token']
assert request(path+'&search=CLIENTE%20PAGAMENTO',token=other)[1]['summary']['count']==0
print('OK: pagamentos persistidos, rejeição de métodos inválidos, legado sem informação, totais além de 100, canceladas separadas, filtros/busca e isolamento por empresa/ambiente.')
