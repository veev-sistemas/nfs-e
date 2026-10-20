"""Private worker. Arguments contain only a private request directory, never secrets."""
import base64
import json
import os
from pathlib import Path
import re
import sys
import tempfile
from datetime import datetime, timezone
from uuid import UUID

from cryptography import x509
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.x509.oid import ObjectIdentifier

MAX_PFX = 512 * 1024

def private_write(path, data):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, 'wb') as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())

def validate(pfx, password, document):
    if not 0 < len(pfx) <= MAX_PFX:
        raise ValueError('Certificado excede o limite de 512 KB.')
    try:
        key, cert, _ = pkcs12.load_key_and_certificates(pfx, password.encode('utf-8') or None)
    except (ValueError, TypeError):
        raise ValueError('Arquivo PFX/P12 ou senha invalida.') from None
    if key is None or cert is None:
        raise ValueError('O certificado precisa conter a chave privada.')
    if key.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo) != cert.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo):
        raise ValueError('Chave privada incompativel com o certificado.')
    now = datetime.now(timezone.utc)
    if not cert.not_valid_before_utc <= now < cert.not_valid_after_utc:
        raise ValueError('Certificado vencido ou ainda nao valido.')
    documents = set()
    try:
        for other in cert.extensions.get_extension_for_class(x509.SubjectAlternativeName).value.get_values_for_type(x509.OtherName):
            if other.type_id == ObjectIdentifier('2.16.76.1.3.3'):
                # ICP-Brasil CNPJ OtherName contains a DER string of exactly 14 digits.
                value = other.value
                if len(value) == 16 and value[0] in (4, 12, 19, 22) and value[1] == 14:
                    documents.add(value[2:].decode('ascii'))
    except x509.ExtensionNotFound:
        pass
    if documents != {document}:
        raise ValueError('CNPJ do certificado diferente da empresa ou ausente no certificado.')
    try:
        if cert.extensions.get_extension_for_class(x509.BasicConstraints).value.ca:
            raise ValueError('Certificado de autoridade nao pode ser utilizado.')
    except x509.ExtensionNotFound:
        pass
    try:
        if not cert.extensions.get_extension_for_class(x509.KeyUsage).value.digital_signature:
            raise ValueError('Certificado nao permite assinatura digital.')
    except x509.ExtensionNotFound:
        pass
    return {'configured': True, 'document': document, 'subject': cert.subject.rfc4514_string(),
            'valid_from': cert.not_valid_before_utc.isoformat(), 'valid_until': cert.not_valid_after_utc.isoformat(),
            'fingerprint_sha256': cert.fingerprint(hashes.SHA256()).hex()}

def process(request, work):
    company = str(UUID(request['company']))
    document = request['document']
    if not re.fullmatch(r'[0-9]{14}', document):
        raise ValueError('CNPJ invalido.')
    root = Path(os.environ['NFSE_CERTIFICATES_DIR'])
    data = Path(os.environ['NFSE_DATA_DIR'])
    if not root.is_absolute() or not data.is_absolute():
        raise ValueError('Armazenamento privado nao configurado.')
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    bundle = root / (company + '.a1.enc')
    keyfile = data / '.secrets' / 'certificates.key'
    operation = request['operation']
    aad = ('nfse-a1-v1:' + company + ':' + document).encode()

    def encryption_key(create=False):
        if create:
            keyfile.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            try:
                private_write(keyfile, os.urandom(32))
            except FileExistsError:
                pass
        key = keyfile.read_bytes()
        if len(key) != 32:
            raise ValueError('Chave de armazenamento invalida.')
        return key

    if operation == 'install':
        password = request['password']
        if not isinstance(password, str) or len(password.encode()) > 1024:
            raise ValueError('Senha do certificado invalida.')
        try:
            pfx = base64.b64decode(request['pfx_base64'], validate=True)
        except (ValueError, TypeError):
            raise ValueError('Arquivo PFX/P12 invalido.') from None
        metadata = validate(pfx, password, document)
        # Never silently replace a lost key when an encrypted bundle already exists.
        key = encryption_key(create=not any(root.glob('*.a1.enc')))
        nonce = os.urandom(12)
        payload = json.dumps({'pfx_base64': request['pfx_base64'], 'password': password}).encode()
        encrypted = b'A1v1' + nonce + AESGCM(key).encrypt(nonce, payload, aad)
        fd, temporary = tempfile.mkstemp(prefix='.a1-', dir=root)
        try:
            with os.fdopen(fd, 'wb') as stream:
                stream.write(encrypted); stream.flush(); os.fsync(stream.fileno())
            os.replace(temporary, bundle)
        finally:
            Path(temporary).unlink(missing_ok=True)
        return dict(metadata, source='encrypted')

    if bundle.exists():
        encrypted = bundle.read_bytes()
        if encrypted[:4] != b'A1v1':
            raise ValueError('Armazenamento do certificado invalido.')
        payload = json.loads(AESGCM(encryption_key()).decrypt(encrypted[4:16], encrypted[16:], aad))
        pfx = base64.b64decode(payload['pfx_base64'], validate=True)
        password = payload['password']; source = 'encrypted'
    else:
        legacy = root / (company + '.pfx')
        secret = root / (company + '.password')
        if not legacy.exists() or not secret.exists():
            if operation == 'status':
                return {'configured': False}
            raise ValueError('Certificado desta empresa nao provisionado no servidor.')
        pfx = legacy.read_bytes(); password = secret.read_text(encoding='utf-8').rstrip('\r\n'); source = 'legacy'
    metadata = dict(validate(pfx, password, document), source=source)
    if operation == 'materialize':
        private_write(work / 'certificate.pfx', pfx)
        return {'path': str(work / 'certificate.pfx'), 'password': password}
    if operation != 'status':
        raise ValueError('Operacao invalida.')
    return metadata

def main():
    os.umask(0o077)
    work = Path(sys.argv[1])
    try:
        request = json.loads((work / 'request.json').read_text(encoding='utf-8-sig'))
        result = process(request, work)
    except ValueError as error:
        result = {'error': str(error)}
    except Exception:
        result = {'error': 'Nao foi possivel acessar o certificado. Confira o volume privado e a chave de armazenamento.'}
    private_write(work / 'result.json', json.dumps(result, ensure_ascii=False).encode())

if __name__ == '__main__':
    main()
