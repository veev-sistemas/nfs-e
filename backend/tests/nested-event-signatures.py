"""Generate fictitious unsigned event + A1 fixtures for SignNestedEventProbe; no network."""
from datetime import datetime,timedelta,timezone
from pathlib import Path
import sys
from cryptography import x509
from cryptography.hazmat.primitives import hashes,serialization
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=True)
key='31367022211111111000191'+'0'*27
xml=f'''<evento xmlns="http://www.sped.fazenda.gov.br/nfse" versao="1.01"><infEvento Id="EVT{key}101101001"><verAplic>FICTICIO-SEM-REDE</verAplic><ambGer>2</ambGer><nSeqEvento>1</nSeqEvento><dhProc>2026-10-20T10:01:00-03:00</dhProc><nDFSe>1</nDFSe><pedRegEvento versao="1.01"><infPedReg Id="PRE{key}101101"><tpAmb>2</tpAmb><verAplic>FICTICIO-SEM-REDE</verAplic><dhEvento>2026-10-20T10:00:00-03:00</dhEvento><CNPJAutor>11111111000191</CNPJAutor><chNFSe>{key}</chNFSe><e101101><xDesc>Cancelamento de NFS-e</xDesc><cMotivo>2</cMotivo><xMotivo>Servico nao prestado em teste local</xMotivo></e101101></infPedReg></pedRegEvento></infEvento></evento>'''
(out/'event-unsigned.xml').write_text(xml,encoding='utf-8')
for name in ['inner-test','outer-test']:
    private=rsa.generate_private_key(public_exponent=65537,key_size=2048)
    now=datetime.now(timezone.utc)
    dn=x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,name)]+[
        x509.NameAttribute(NameOID.ORGANIZATIONAL_UNIT_NAME,('PUBLIC FICTITIOUS CERTIFICATE '+str(n)+' ').ljust(64,'X')) for n in range(45)])
    cert=x509.CertificateBuilder().subject_name(dn).issuer_name(dn).public_key(private.public_key()).serial_number(x509.random_serial_number()).not_valid_before(now-timedelta(days=1)).not_valid_after(now+timedelta(days=1)).sign(private,hashes.SHA256())
    (out/(name+'.pfx')).write_bytes(pkcs12.serialize_key_and_certificates(name.encode(),private,cert,None,serialization.BestAvailableEncryption(b'Nested-test-2026')))
print('Generated two entirely fictitious A1 certificates. Never package these test fixtures.')
