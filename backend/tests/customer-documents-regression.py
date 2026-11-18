"""Read locally generated fictitious DPS and verify DANFSe fields. No transmission."""
import importlib.util,xml.etree.ElementTree as ET,sys
from pathlib import Path
from pypdf import PdfReader
root=Path(__file__).resolve().parents[1]
folder=Path(sys.argv[1]);n={'n':'http://www.sped.fazenda.gov.br/nfse'}
dps=ET.parse(folder/'dps-tomador-contato.xml').getroot()
t=dps.find('.//n:toma',n)
assert t.find('n:fone',n).text=='21999990000'
assert t.find('n:email',n).text=='cliente@example.com'
assert t.find('n:end/n:endNac/n:cMun',n).text=='3306107'
assert t.find('n:end/n:xLgr',n).text=='RUA DE TESTE'
spec=importlib.util.spec_from_file_location('renderer',root/'deploy/render-danfse.py');renderer=importlib.util.module_from_spec(spec);spec.loader.exec_module(renderer)
doc='11111111000191';key='0'*9+doc+'0'*27
xml=f'<NFSe xmlns="http://www.sped.fazenda.gov.br/nfse"><infNFSe Id="NFS{key}"><xLocEmi>Juiz de Fora</xLocEmi><nNFSe>99</nNFSe><cStat>100</cStat><ambGer>2</ambGer><dhProc>2026-11-18T12:00:00Z</dhProc><emit><CNPJ>{doc}</CNPJ><xNome>FICTICIO</xNome><enderNac><cMun>3136702</cMun><UF>MG</UF></enderNac></emit><valores><vLiq>100.00</vLiq></valores>'+ET.tostring(dps,encoding='unicode')+'</infNFSe></NFSe>'
p=folder/'nota-ficticia.xml';p.write_text(xml,encoding='utf-8');pdf=folder/'nota-ficticia.pdf'
renderer.generate(p,pdf,doc,key)
text=''.join(page.extract_text() for page in PdfReader(pdf).pages)
for value in ['cliente@example.com','RUA DE TESTE','SALA 2','CENTRO','27600-000','3306107']:
 assert value in text,value
assert '21999990000' in text.replace(' ','').replace('-','').replace('(','').replace(')','')
print('OK: contato e endereco no XML real gerado e no texto do DANFSe ficticio.')
