"""Local preview. --demo is a fake API and is never packaged for deployment."""
import argparse
import json
import uuid
from datetime import datetime, timezone
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import urllib.request
import urllib.error
from urllib.parse import urlsplit, parse_qs

ROOT = Path(__file__).parent / 'dist'
UPSTREAM = 'https://nfse-nfse-api.0piict.easypanel.host'
COMPANY = {'id':'11111111-1111-4111-8111-111111111111','name':'EMPRESA DEMONSTRAÇÃO LTDA','document':'12345678000199'}
SETTINGS = {'tax_regime':'simples_nacional','service_code':'090103','municipal_service_code':'002','nbs_code':'103031100','approx_simples_percent':13.46,'service_description':'TESTE DE HOMOLOGAÇÃO - Serviço demonstrativo'}
now = lambda: datetime.now(timezone.utc).isoformat()
INVOICES = [{'id':str(uuid.uuid4()),'draft_id':None,'environment':'homologacao','access_key':'3'*50,'customer_name':'TOMADOR DEMONSTRAÇÃO','invoice_number':'2','issuer_document':COMPANY['document'],'amount_cents':10000,'status':'authorized_homologation','source':'sefin_api','imported_at':now()}]
DRAFTS = [{'id':str(uuid.uuid4()),'customer_id':None,'amount_cents':25000,'settings':dict(SETTINGS),'status':'draft','created_at':now(),'attempt_id':None,'attempt_status':None}]
DRAFTS.append(dict(DRAFTS[0],id=str(uuid.uuid4()),environment='producao',settings=dict(SETTINGS,service_description='SIMULACAO VISUAL - SEM TRANSMISSAO')))
CUSTOMERS = [{'id':str(uuid.uuid4()),'name':'Cliente de demonstração','document':'11111111111'}]
ATTEMPTS = {}
TOKENS = set()


class Handler(SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):
        # Never log request bodies, credentials or Authorization.
        pass

    def respond(self, status, body, content_type='application/json; charset=utf-8'):
        payload = json.dumps(body, ensure_ascii=False).encode() if not isinstance(body, bytes) else body
        self.send_response(status)
        self.send_header('Content-Type',content_type)
        self.send_header('Cache-Control','no-store')
        self.send_header('Content-Length',str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        if self.path.startswith('/v1/'):
            self.api()
        else:
            super().do_GET()

    def do_POST(self):
        self.api()

    def do_PATCH(self):
        self.api()

    def api(self):
        if not self.path.startswith('/v1/'):
            self.respond(404, {'error':'Not found'})
            return
        size = int(self.headers.get('Content-Length',0))
        if size > 1048576:
            self.respond(413, {'error':'Corpo muito grande.'})
            return
        raw = self.rfile.read(size)
        if not self.server.demo:
            req = urllib.request.Request(UPSTREAM+self.path,method=self.command,
                data=raw if self.command != 'GET' else None,
                headers={name:self.headers[name] for name in ['Content-Type','Authorization','Accept'] if name in self.headers})
            try:
                with urllib.request.urlopen(req,timeout=130) as response:
                    self.respond(response.status,response.read(),response.headers.get('Content-Type','application/octet-stream'))
            except urllib.error.HTTPError as error:
                self.respond(error.code,error.read(),error.headers.get('Content-Type','application/json'))
            except Exception:
                self.respond(502,{'error':'Backend indisponível na prévia local.'})
            return
        try:
            body = json.loads(raw) if raw else {}
        except ValueError:
            self.respond(400,{'error':'JSON inválido.'})
            return
        path = urlsplit(self.path).path[3:]
        query = parse_qs(urlsplit(self.path).query)
        auth = self.headers.get('Authorization','').removeprefix('Bearer ')
        if path == '/auth/login' and self.command == 'POST':
            if body.get('cnpj') != COMPANY['document'] or body.get('password') != 'Demonstracao-2026':
                self.respond(401,{'error':'CNPJ ou senha invalidos.'})
                return
            token = 'session_'+uuid.uuid4().hex+uuid.uuid4().hex
            TOKENS.add(token)
            self.respond(200,dict(access_token=token,token_type='Bearer',expires_in=28800,
                company_id=COMPANY['id'],name=COMPANY['name'],document=COMPANY['document']))
            return
        if auth not in TOKENS:
            self.respond(401,{'error':'Sessão inválida.'})
            return
        if path == '/auth/me': self.respond(200,COMPANY)
        elif path == '/emission-config': self.respond(200,{'production_available':True,'production_enabled':True,'active_environment':'homologacao'})
        elif path == '/auth/logout':
            TOKENS.discard(auth)
            self.respond(200,{'status':'ok'})
        elif path == '/settings':
            if self.command == 'PATCH': SETTINGS.update(body)
            self.respond(200,SETTINGS)
        elif path == '/customers':
            if self.command == 'POST':
                customer = dict(id=str(uuid.uuid4()),name=body['name'].strip().upper(),document=body['document'])
                CUSTOMERS.append(customer)
                self.respond(201,customer)
            else: self.respond(200,CUSTOMERS)
        elif path == '/drafts':
            if self.command == 'POST':
                draft = dict(id=str(uuid.uuid4()),customer_id=body.get('customer_id'),amount_cents=body['amount_cents'],
                    settings=dict(SETTINGS,**body.get('overrides',{})),status='draft',created_at=now(),environment=body.get('environment','homologacao'))
                DRAFTS.insert(0,draft)
                self.respond(200,draft)
            else: self.respond(200,[d for d in DRAFTS if not query.get('environment') or d.get('environment','homologacao')==query['environment'][0]])
        elif path.startswith('/drafts/') and path.endswith('/emit-production'):
            self.respond(422,{'error':'Emissao real indisponivel nesta demonstracao ficticia. Nenhuma transmissao.'})
        elif path.startswith('/drafts/') and path.endswith('/emit-homologation'):
            draft = next(d for d in DRAFTS if d['id'] == path.split('/')[2])
            if draft.get('attempt_id'):
                self.respond(200,ATTEMPTS[draft['attempt_id']])
                return
            attempt = dict(id=str(uuid.uuid4()),draft_id=draft['id'],environment='homologacao',status='authorized',dps_number=len(ATTEMPTS)+1,dps_series='901',result={'errors':[]})
            invoice = dict(id=str(uuid.uuid4()),draft_id=draft['id'],environment='homologacao',access_key='3'*50,customer_name=next((c['name'] for c in CUSTOMERS if c['id']==draft.get('customer_id')),None),invoice_number=str(max(int(n['invoice_number']) for n in INVOICES)+1),issuer_document=COMPANY['document'],amount_cents=draft['amount_cents'],status='authorized_homologation',source='sefin_api',imported_at=now())
            attempt['invoice_id'] = invoice['id']
            ATTEMPTS[attempt['id']] = attempt
            draft.update(attempt_id=attempt['id'],attempt_status=attempt['status'])
            INVOICES.insert(0,invoice)
            self.respond(200,attempt)
        elif path.startswith('/emission-attempts/'):
            self.respond(200,ATTEMPTS[path.split('/')[-1]])
        elif path == '/invoices':
            from zoneinfo import ZoneInfo
            date_from=query.get('date_from',[''])[0]
            date_to=query.get('date_to',[''])[0]
            filtered=[]
            for note in INVOICES:
                if query.get('environment') and note['environment']!=query['environment'][0]: continue
                status=query.get('status',[''])[0]
                if status and status!=note['status'] and not (status=='authorized' and note['status'].startswith('authorized_')): continue
                day=datetime.fromisoformat(note.get('issued_at') or note['imported_at']).astimezone(ZoneInfo('America/Sao_Paulo')).date().isoformat()
                if (not date_from or day>=date_from) and (not date_to or day<=date_to): filtered.append(note)
            self.respond(200,filtered)
        elif path.endswith('/cancel'):
            self.respond(422,{'error':'Cancelamento real indisponível na demonstração. Nenhuma transmissão.'})
        elif path.endswith('/xml'): self.respond(200,b'<?xml version="1.0"?><demo>Documento ficticio de QA</demo>','application/xml')
        elif path.endswith('/pdf'):
            self.respond(502,{'error':'Download de PDF real disponível somente com o backend; prévia fictícia.'})
        else: self.respond(404,{'error':'Rota não encontrada.'})


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--demo',action='store_true')
    parser.add_argument('--port',type=int,default=4173)
    parser.add_argument('--local-api',type=int,help='Porta da API local de teste; nunca altera o pacote de deploy')
    args = parser.parse_args()
    if args.local_api:
        if not 1<=args.local_api<=65535: parser.error('Porta local invalida')
        UPSTREAM='http://127.0.0.1:'+str(args.local_api)
    server = ThreadingHTTPServer(('127.0.0.1',args.port),partial(Handler,directory=str(ROOT)))
    server.demo = args.demo
    print(f'Local: http://127.0.0.1:{args.port} | mode={"DEMONSTRACAO FICTICIA" if args.demo else "backend real"}',flush=True)
    server.serve_forever()
