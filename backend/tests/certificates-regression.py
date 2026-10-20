"""Synthetic certificates only; no external fiscal service is contacted."""
import base64
from datetime import datetime, timedelta, timezone
import importlib.util
import json
import os
from pathlib import Path
import tempfile
from uuid import uuid4
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID, ObjectIdentifier

spec=importlib.util.spec_from_file_location('certificates',Path(__file__).parents[1]/'deploy/manage-certificate.py')
worker=importlib.util.module_from_spec(spec);spec.loader.exec_module(worker)
DOCUMENT='99999999999999'

def fixture(document=DOCUMENT, expired=False, private=True):
    key=rsa.generate_private_key(public_exponent=65537,key_size=2048)
    name=x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,'CERTIFICADO FICTICIO')])
    now=datetime.now(timezone.utc)
    cert=(x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(key.public_key())
        .serial_number(x509.random_serial_number()).not_valid_before(now-timedelta(days=2))
        .not_valid_after(now+timedelta(days=-1 if expired else 30))
        .add_extension(x509.SubjectAlternativeName([x509.OtherName(ObjectIdentifier('2.16.76.1.3.3'),b'\x0c\x0e'+document.encode())]),critical=False)
        .add_extension(x509.BasicConstraints(ca=False,path_length=None),critical=True).sign(key,hashes.SHA256()))
    return pkcs12.serialize_key_and_certificates(b'test',key if private else None,cert,None,
        serialization.BestAvailableEncryption('Senha-certificado-2026'.encode()))

def run():
    with tempfile.TemporaryDirectory() as directory:
        root=Path(directory);os.environ['NFSE_DATA_DIR']=str(root);os.environ['NFSE_CERTIFICATES_DIR']=str(root/'certs')
        company=str(uuid4());work=root/'request';work.mkdir(mode=0o700)
        def call(operation, **extra):
            return worker.process(dict(company=company,document=DOCUMENT,operation=operation,**extra),work)
        assert call('status')=={'configured':False}
        pfx=fixture();encoded=base64.b64encode(pfx).decode();password='Senha-certificado-2026'
        result=call('install',pfx_base64=encoded,password=password)
        assert result['configured'] and 'password' not in result and 'pfx_base64' not in result
        bundle=root/'certs'/(company+'.a1.enc');original=bundle.read_bytes()
        assert pfx not in original and password.encode() not in original and encoded.encode() not in original
        for data,secret in [(pfx,'wrong'),(fixture('11111111111111'),password),(fixture(expired=True),password),
                            (fixture(private=False),password),(b'bad',password),(b'x'*(worker.MAX_PFX+1),password)]:
            try:call('install',pfx_base64=base64.b64encode(data).decode(),password=secret)
            except ValueError:pass
            else:raise AssertionError('invalid replacement accepted')
            assert bundle.read_bytes()==original
        materialized=call('materialize');assert materialized['password']==password
        assert Path(materialized['path']).read_bytes()==pfx
        if os.name=='posix':
            assert bundle.stat().st_mode&0o777==0o600
            assert Path(materialized['path']).stat().st_mode&0o777==0o600
        keyfile=root/'.secrets/certificates.key';stored_key=keyfile.read_bytes();keyfile.unlink()
        try:call('install',pfx_base64=encoded,password=password)
        except FileNotFoundError:pass
        else:raise AssertionError('lost key silently replaced')
        assert not keyfile.exists() and bundle.read_bytes()==original
        worker.private_write(keyfile,stored_key)
        bundle.write_bytes(original[:-1]+bytes([original[-1]^1]))
        try:call('status')
        except Exception:pass
        else:raise AssertionError('tampering accepted')
        bundle.unlink()
        worker.private_write(root/'certs'/(company+'.pfx'),pfx)
        worker.private_write(root/'certs'/(company+'.password'),password.encode()+b'\n')
        assert call('status')['source']=='legacy'
    print('PASS: validacao, CNPJ, senha, validade, chave privada, criptografia, integridade, troca atomica e legado.')

if __name__=='__main__':run()
