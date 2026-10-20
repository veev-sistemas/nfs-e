"""WSL only: validate the deployment nginx template using local nginx."""
import subprocess
import time
import urllib.request
import urllib.error
from pathlib import Path

root = Path(__file__).resolve().parents[1]
template = (root/'nginx.conf.template').read_text()
config = template.replace('${NFSE_API_HOST}','nfse-nfse-api.0piict.easypanel.host')
config = config.replace('listen 80;', 'listen 18080;').replace('/usr/share/nginx/html',str(root/'dist'))
path = Path('/tmp/nfse-frontend-nginx.conf')
path.write_text('pid /tmp/nfse-frontend-nginx.pid;\nevents {}\nhttp {\ninclude /etc/nginx/mime.types;\naccess_log off;\n'+config+'\n}\n')
subprocess.run(['nginx','-t','-c',str(path)],check=True)
process = subprocess.Popen(['nginx','-c',str(path),'-g','daemon off;'],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
try:
    for _ in range(40):
        try:
            with urllib.request.urlopen('http://127.0.0.1:18080/') as response:
                assert response.status == 200
                assert b'VEEV' in response.read()
                assert "script-src 'self'" in response.headers['Content-Security-Policy']
            break
        except urllib.error.URLError:
            time.sleep(.1)
    else: raise AssertionError('Nginx failed to serve frontend')
    with urllib.request.urlopen('http://127.0.0.1:18080/app.js') as response:
        assert 'javascript' in response.headers['Content-Type']
    try:
        urllib.request.urlopen('http://127.0.0.1:18080/v1/auth/me',timeout=20)
        raise AssertionError('Unauthenticated proxy accepted')
    except urllib.error.HTTPError as error:
        assert error.code == 401, (error.code,error.read())
        assert 'error' in error.read().decode()
    print('OK: nginx template, static assets, CSP and same-origin HTTPS API proxy (401).')
finally:
    process.terminate()
    process.wait(timeout=5)
    diagnostics = process.stderr.read().decode()
    if diagnostics:
        print(diagnostics)
