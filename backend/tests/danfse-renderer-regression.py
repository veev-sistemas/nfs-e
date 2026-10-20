"""Casos locais com XML sintetico; nao utiliza notas ou certificados reais."""
import importlib.util
from pathlib import Path
from tempfile import TemporaryDirectory
from pypdf import PdfReader

renderer_path = Path(__file__).resolve().parents[1] / 'deploy/render-danfse.py'
spec = importlib.util.spec_from_file_location('danfse', renderer_path)
renderer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(renderer)
doc = '11111111111111'
key = '0' * 9 + doc + '0' * 27
fixture = f'''<NFSe xmlns="http://www.sped.fazenda.gov.br/nfse"><infNFSe Id="NFS{key}">
<xLocEmi>Juiz de Fora</xLocEmi><xLocPrestacao>Juiz de Fora</xLocPrestacao><nNFSe>99</nNFSe>
<cStat>100</cStat><ambGer>2</ambGer><dhProc>2026-10-19T11:31:18-03:00</dhProc>
<emit><CNPJ>{doc}</CNPJ><xNome>PRESTADOR DE TESTE</xNome><enderNac><cMun>3136702</cMun><UF>MG</UF></enderNac></emit>
<valores><vLiq>100.00</vLiq></valores><DPS><infDPS><tpAmb>2</tpAmb><tpEmit>1</tpEmit>
<nDPS>1</nDPS><serie>901</serie><dhEmi>2026-10-19T11:30:00-03:00</dhEmi><dCompet>2026-10-19</dCompet>
<prest><CNPJ>{doc}</CNPJ><regTrib><opSimpNac>3</opSimpNac><regApTribSN>1</regApTribSN><regEspTrib>0</regEspTrib></regTrib></prest>
<serv><locPrest><cLocPrestacao>3136702</cLocPrestacao></locPrest><cServ><cTribNac>090103</cTribNac><cNBS>103031100</cNBS><xDescServ>TESTE &lt;b&gt;literal&lt;/b&gt;</xDescServ></cServ></serv>
<valores><vServPrest><vServ>100.00</vServ></vServPrest><trib><tribMun><tribISSQN>1</tribISSQN><tpRetISSQN>1</tpRetISSQN></tribMun><totTrib><pTotTribSN>13.46</pTotTribSN></totTrib></trib></valores>
</infDPS></DPS></infNFSe></NFSe>'''

with TemporaryDirectory() as tmp:
    xml, pdf = Path(tmp) / 'fixture.xml', Path(tmp) / 'fixture.pdf'
    xml.write_text(fixture, encoding='utf-8')
    renderer.generate(xml, pdf, doc, key)
    reader = PdfReader(pdf)
    assert len(reader.pages) == 1
    text = reader.pages[0].extract_text()
    assert 'NFS-e SEM VALIDADE JURÍDICA' in text
    assert key in text and 'R$ 100,00' in text and '<b>literal</b>' in text
    assert '13,46%' in text
    tests = [
        ('CNPJ divergente', fixture, {'expected_doc': '22222222222222'}),
        ('chave divergente', fixture, {'expected_key': '9' * 50}),
        ('hash divergente', fixture, {'expected_hash': '0' * 64}),
        ('producao bloqueada', fixture.replace('<tpAmb>2', '<tpAmb>1'), {}),
        ('DTD bloqueado', '<!DOCTYPE NFSe [<!ENTITY x "teste">]>' + fixture, {}),
        ('IBS/CBS incompleto', fixture.replace('</infDPS>', '<IBSCBS/></infDPS>'), {}),
    ]
    for name, source, options in tests:
        xml.write_text(source, encoding='utf-8')
        try:
            renderer.generate(xml, pdf, **options)
        except ValueError:
            continue
        raise AssertionError(name)
    declared = '''<IBSCBS><cIndOp>030101</cIndOp><indDest>0</indDest><valores><trib>
    <CST>200</CST><cClassTrib>200048</cClassTrib></trib></valores></IBSCBS>'''
    returned = '''<IBSCBS><cLocalidadeIncid>3136702</cLocalidadeIncid><xLocalidadeIncid>Juiz de Fora</xLocalidadeIncid>
    <valores><vBC>100.00</vBC><uf><pIBSUF>0.10</pIBSUF><pRedAliqUF>40.00</pRedAliqUF><pAliqEfetUF>0.06</pAliqEfetUF></uf>
    <mun><pIBSMun>0.00</pIBSMun><pRedAliqMun>40.00</pRedAliqMun><pAliqEfetMun>0.00</pAliqEfetMun></mun>
    <fed><pCBS>0.90</pCBS><pRedAliqCBS>40.00</pRedAliqCBS><pAliqEfetCBS>0.54</pAliqEfetCBS></fed></valores>
    <totCIBS><vTotNF>100.00</vTotNF><gIBS><vIBSTot>0.06</vIBSTot><gIBSUFTot><vIBSUF>0.06</vIBSUF></gIBSUFTot>
    <gIBSMunTot><vIBSMun>0.00</vIBSMun></gIBSMunTot></gIBS><gCBS><vCBS>0.54</vCBS></gCBS></totCIBS></IBSCBS>'''
    with_ibs = fixture.replace('</infDPS>',declared+'</infDPS>').replace('</infNFSe>',returned+'</infNFSe>')
    xml.write_text(with_ibs,encoding='utf-8')
    renderer.generate(xml,pdf,doc,key)
    reader = PdfReader(pdf)
    assert len(reader.pages) == 1
    content = reader.pages[0].extract_text()
    for value in ['200 / 200048','030101 / 3136702 / Juiz de Fora / MG',
                  'R$ 0,06','R$ 0,54','R$ 0,60','R$ 0,00','0,06%','0,54%',
                  '40,00% / 40,00% / 40,00%','O DESTINATÁRIO É O PRÓPRIO']:
        assert value in content,value
    # vTotNF is an authoritative returned value, not vLiq + computed tax.
    assert 'R$ 100,60' not in content
    for source in [with_ibs.replace('<vCBS>0.54</vCBS>',''),
                   with_ibs.replace('<vCBS>0.54</vCBS>','<vCBS>NaN</vCBS>'),
                   with_ibs.replace('<CST>200</CST>','<CST>000</CST>')]:
        xml.write_text(source,encoding='utf-8')
        try:
            renderer.generate(xml,pdf,doc,key)
        except ValueError:
            continue
        raise AssertionError('IBS/CBS invalido nao bloqueado')
print('OK: PDF com/sem IBS/CBS, pagina unica, classificacao/aliquotas/valores retornados, soma de tributos, vTotNF preservado e bloqueios de integridade.')
