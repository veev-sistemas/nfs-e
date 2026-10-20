"""Recover a saved, signed fictitious event through GET. Never calls a fiscal service."""
exec((__import__('pathlib').Path(__file__).parent/'environment-cancellation-regression.py').read_text().split('admin=request(',1)[0])
import os
from pathlib import Path
import xml.etree.ElementTree as ET

root=Path(__file__).resolve().parents[1]
fixtures=root/'build/nested-events'
xml=(fixtures/'event-valid.xml').read_text(encoding='utf-8-sig')
bad_xml=(fixtures/'event-tampered.xml').read_text(encoding='utf-8-sig')
ns={'n':'http://www.sped.fazenda.gov.br/nfse'}
info=ET.fromstring(xml).find('n:infEvento/n:pedRegEvento/n:infPedReg',ns)
key=info.find('n:chNFSe',ns).text
company=sql("insert into companies(name,document) values('Saved event regression','11111111000191') returning id").splitlines()[0]
sql("select set_company_password('%s','Saved-event-password-2026')"%company)
tenant=request('/v1/auth/login','POST',{'cnpj':'11111111000191','password':'Saved-event-password-2026'})[1]['access_token']

def fixture(access_key,content):
    invoice=sql("""insert into invoices(company_id,environment,access_key,invoice_number,issuer_document,amount_cents,xml_content,xml_sha256,status,source)
    values('%s','homologacao','%s','123','11111111000191',10000,'<NFSe/>','fixture','authorized_homologation','sefin_api') returning id"""%(company,access_key)).splitlines()[0]
    attempt=json.loads(sql("select reserve_cancellation('%s','%s',2,'Servico nao prestado em teste local')"%(company,invoice)))['attempt']['id']
    sql("select finish_cancellation('%s','%s','unknown','{}',null)"%(company,attempt))
    folder=Path(os.environ['NFSE_QA_DATA'])/company/('cancel-'+attempt);folder.mkdir(parents=True)
    (folder/'resposta.txt').write_text(content,encoding='utf-8-sig')
    return invoice,attempt

invoice,attempt=fixture(key,xml)
url='/v1/invoices/'+invoice+'/cancellation'
status,result=request(url,token=tenant)
if result.get('status')!='cancelled':
    error=Path(os.environ['NFSE_QA_DATA'])/company/('cancel-'+attempt)/'reconcile-error.txt'
    if error.exists():print(error.read_text(encoding='utf-8-sig'))
assert status==200 and result['status']=='cancelled',(status,result)
assert result['result']['recovered_from_saved_event'] is True
assert request(url,token=tenant)[1]['id']==attempt
assert sql("select status from invoices where id='%s'"%invoice)=='cancelled'
assert sql("select count(*) from cancellation_attempts where invoice_id='%s'"%invoice)=='1'
other,other_attempt=fixture('7'*50,bad_xml)
assert request('/v1/invoices/'+other+'/cancellation',token=tenant)[1]['status']=='unknown'
assert sql("select status from invoices where id='%s'"%other)=='authorized_homologation'
print('PASS: evento salvo com duas assinaturas confirmado por GET; adulteracao bloqueada; repeticao idempotente; nenhuma nova transmissao.')
