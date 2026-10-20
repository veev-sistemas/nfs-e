"""Validate actual XML emitted by DpsNt009Probe; no network or fiscal transmission."""
import copy
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
fixtures = Path(sys.argv[1])
schema = root/'deploy/schemas/DPS_v1.01.xsd'
ns = '{http://www.sped.fazenda.gov.br/nfse}'

def validate(path, valid):
    result = subprocess.run(['xmllint','--noout','--schema',str(schema),str(path)],capture_output=True)
    assert (result.returncode == 0) == valid, result.stderr.decode()

for name in ['dps-producao.xml','dps-producao-ibs.xml']:
    result=subprocess.run(['xmllint','--noout','--schema',str(root/'deploy/schemas-production/DPS_v1.01.xsd'),str(fixtures/name)],capture_output=True)
    assert result.returncode==0,result.stderr.decode()
    production=ET.parse(fixtures/name).getroot().find(ns+'infDPS')
    assert production.find(ns+'tpAmb').text=='1' and production.find(ns+'finNFSe') is None
    if 'ibs' in name:
        assert production.find(ns+'IBSCBS').find(ns+'finNFSe').text=='0'
        assert production.find(ns+'IBSCBS').find(ns+'valores').find(ns+'trib').find(ns+'gIBSCBS').find(ns+'CST').text=='200'
for name in ['dps-sem-tomador.xml','dps-com-tomador.xml']:
    path = fixtures/name
    validate(path,True)
    tree = ET.parse(path)
    info = tree.getroot().find(ns+'infDPS')
    tags = [node.tag for node in info]
    assert tags.count(ns+'finNFSe') == 1
    assert tags.index(ns+'finNFSe') + 1 == tags.index(ns+'cLocEmi')
    assert info.find(ns+'finNFSe').text == '0'
    assert info.find(ns+'IBSCBS') is None
    service = info.find(ns+'serv').find(ns+'cServ')
    assert [node.tag for node in service] == [ns+name for name in ['cTribNac','cTribMun','cNBS','cIntContrib','xDescServ']]
    old_order = copy.deepcopy(tree)
    old_service = old_order.getroot().find(ns+'infDPS').find(ns+'serv').find(ns+'cServ')
    description = old_service.find(ns+'xDescServ')
    old_service.remove(description)
    old_service.insert(2,description)
    bad = fixtures/'negative-old-order.xml'
    old_order.write(bad,encoding='utf-8',xml_declaration=True)
    validate(bad,False)
    bad.unlink()
    missing = copy.deepcopy(tree)
    missing_info = missing.getroot().find(ns+'infDPS')
    missing_info.remove(missing_info.find(ns+'finNFSe'))
    bad = fixtures/'negative.xml'
    missing.write(bad,encoding='utf-8',xml_declaration=True)
    validate(bad,False)
    wrong = copy.deepcopy(tree)
    wrong.getroot().find(ns+'infDPS').find(ns+'finNFSe').text = '1'
    wrong.write(bad,encoding='utf-8',xml_declaration=True)
    validate(bad,False)
    bad.unlink()
path = fixtures/'dps-ibs-cbs.xml'
validate(path, True)
tree = ET.parse(path)
info = tree.getroot().find(ns+'infDPS')
assert info.find(ns+'indDest') is None
group = info.find(ns+'IBSCBS')
assert [n.tag for n in group] == [ns+'cIndOp',ns+'indDest',ns+'valores']
assert group.find(ns+'indDest').text == '0'
assert group.find(ns+'cIndOp').text == '030101'
trib = group.find(ns+'valores').find(ns+'trib')
assert [n.tag for n in trib] == [ns+'CST',ns+'cClassTrib']
assert trib.find(ns+'CST').text == '200'
assert trib.find(ns+'cClassTrib').text == '200048'
# Reproduce DPS8 rejection: indDest must not be a direct child of infDPS.
wrong_dest = copy.deepcopy(tree)
i = wrong_dest.getroot().find(ns+'infDPS')
group_wrong = i.find(ns+'IBSCBS')
dest = group_wrong.find(ns+'indDest')
group_wrong.remove(dest)
i.insert(list(i).index(i.find(ns+'serv')),dest)
bad = fixtures/'negative-dps8-inddest.xml'
wrong_dest.write(bad,encoding='utf-8',xml_declaration=True)
validate(bad,False)
bad.unlink()
# The previous ACBr placement must fail local validation too.
old = copy.deepcopy(tree)
t = old.getroot().find(ns+'infDPS').find(ns+'IBSCBS').find(ns+'valores').find(ns+'trib')
g = ET.Element(ns+'gIBSCBS')
for child in list(t):
    t.remove(child)
    g.append(child)
t.append(g)
bad = fixtures/'negative-old-ibs.xml'
old.write(bad,encoding='utf-8',xml_declaration=True)
validate(bad,False)
bad.unlink()
print('OK: IBS/CBS ligado/desligado, CST 200, classe 200048, cIndOp 030101 e ordem NT009; formato antigo rejeitado. Sem transmissao.')
