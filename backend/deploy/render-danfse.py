#!/usr/bin/env python3
"""DANFSe v2.0 a partir do XML autorizado. Sem acesso a rede ou certificado.

Escopo: NFS-e regular, com/sem IBS/CBS de hospedagem. Producao exige fontes do leiaute.
Referencia: NT 008 v1.02, 14/07/2026, Anexo I.
"""
import argparse
from datetime import datetime
from decimal import Decimal
import hashlib
import os
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen.canvas import Canvas
from reportlab.platypus import Paragraph
from reportlab.graphics.barcode.qr import QrCodeWidget
from reportlab.graphics.shapes import Drawing
from reportlab.graphics import renderPDF

NS = {'n': 'http://www.sped.fazenda.gov.br/nfse'}
N = '{http://www.sped.fazenda.gov.br/nfse}'


def text(node, path, default=''):
    if node is None:
        return default
    value = node.find('/'.join('n:' + p for p in path.split('/')), NS)
    return (value.text or '').strip() if value is not None else default


def elem(node, path):
    return node.find('/'.join('n:' + p for p in path.split('/')), NS) if node is not None else None


def money(value):
    if not value:
        return '-'
    v = Decimal(value)
    if not v.is_finite():
        raise ValueError('Valor monetario invalido')
    return 'R$ ' + f'{v:,.2f}'.replace(',', '_').replace('.', ',').replace('_', '.')


def percent(value):
    return value.replace('.', ',') + '%' if value else '-'


def sum_money(values):
    present = [v for v in values if v != '']
    return money(str(sum((Decimal(v) for v in present), Decimal('0')))) if present else '-'


def ibs_data(info, dps):
    """Read returned fiscal amounts; never recalculate rates or add taxes to vTotNF."""
    declared, returned = elem(dps, 'IBSCBS'), elem(info, 'IBSCBS')
    if declared is None and returned is None:
        return None
    if declared is None or returned is None:
        raise ValueError('XML IBS/CBS incompleto: declaracao ou retorno ausente')
    classification = elem(declared, 'valores/trib')
    if elem(classification, 'gIBSCBS') is not None:
        classification = elem(classification, 'gIBSCBS')
    if (text(classification, 'CST'), text(classification, 'cClassTrib'),
            text(declared, 'cIndOp'), text(declared, 'indDest')) != ('200', '200048', '030101', '0'):
        raise ValueError('Perfil IBS/CBS fora do escopo de hospedagem em homologacao')
    allowed = {'finNFSe', 'cIndOp', 'indDest', 'valores', 'indFinal'}
    if text(declared,'finNFSe') not in ('','0'):
        raise ValueError('Finalidade IBS/CBS fora do escopo regular')
    if any(node.tag not in {N + tag for tag in allowed} for node in declared):
        raise ValueError('Operacao especial IBS/CBS ainda nao suportada no DANFSe')
    if any(node.tag not in {N+'CST', N+'cClassTrib'} for node in classification):
        raise ValueError('Ajustes, creditos ou diferimento IBS/CBS ainda nao suportados no DANFSe')
    required = ['valores/vBC', 'valores/uf/pIBSUF', 'valores/uf/pRedAliqUF',
                'valores/uf/pAliqEfetUF', 'valores/mun/pIBSMun', 'valores/mun/pRedAliqMun',
                'valores/mun/pAliqEfetMun', 'valores/fed/pCBS', 'valores/fed/pRedAliqCBS',
                'valores/fed/pAliqEfetCBS', 'totCIBS/vTotNF', 'totCIBS/gIBS/vIBSTot',
                'totCIBS/gIBS/gIBSUFTot/vIBSUF', 'totCIBS/gIBS/gIBSMunTot/vIBSMun',
                'totCIBS/gCBS/vCBS']
    for path in required:
        value = text(returned, path)
        if not value:
            raise ValueError('Retorno IBS/CBS incompleto: ' + path)
        amount = Decimal(value)
        if not amount.is_finite() or amount < 0:
            raise ValueError('Valor IBS/CBS invalido: ' + path)
    return declared, returned, classification


def date(value, with_time=False):
    if not value:
        return '-'
    d = datetime.fromisoformat(value.replace('Z', '+00:00'))
    return d.strftime('%d/%m/%Y %H:%M:%S' if with_time else '%d/%m/%Y')


def document(value):
    if re.fullmatch(r'\d{14}', value):
        return f'{value[:2]}.{value[2:5]}.{value[5:8]}/{value[8:12]}-{value[12:]}'
    if re.fullmatch(r'\d{11}', value):
        return f'{value[:3]}.{value[3:6]}.{value[6:9]}-{value[9:]}'
    return value or '-'


def mapped(value, choices):
    if not value:
        return '-'
    if value not in choices:
        raise ValueError('Codigo fora do escopo do DANFSe de homologacao')
    return choices[value]


def register_fonts(production=False):
    roots = [Path(os.environ.get('NFSE_DANFSE_FONT_DIR', '/var/lib/nfse/fonts')),
             Path('C:/Windows/Fonts')]
    for root in roots:
        if all((root / x).is_file() for x in ('arial.ttf', 'arialbd.ttf', 'micross.ttf')):
            for name, file in [('DLabel', 'arialbd.ttf'), ('DRegular', 'arial.ttf'), ('DValue', 'micross.ttf')]:
                pdfmetrics.registerFont(TTFont(name, str(root / file)))
            return 'Arial / Microsoft Sans Serif'
    if production:
        raise ValueError('Instale arial.ttf, arialbd.ttf e micross.ttf no diretorio privado NFSE_DANFSE_FONT_DIR para o DANFSe de producao')
    # Apenas homologacao: fonte livre compativel, nao declarada conforme para producao.
    for root in [Path('/usr/share/fonts/truetype/liberation2'), Path('/usr/share/fonts/truetype/liberation')]:
        if (root / 'LiberationSans-Regular.ttf').is_file():
            for name, file in [('DLabel', 'LiberationSans-Bold.ttf'), ('DRegular', 'LiberationSans-Regular.ttf'), ('DValue', 'LiberationSans-Regular.ttf')]:
                pdfmetrics.registerFont(TTFont(name, str(root / file)))
            return 'Liberation Sans (previa de homologacao)'
    raise ValueError('Fontes para o DANFSe nao encontradas')


class Sheet:
    def __init__(self, output, production=False):
        self.c = Canvas(str(output), pagesize=A4, pageCompression=1)
        self.c.setTitle('DANFSe - producao' if production else 'DANFSe - homologacao')
        self.c.setAuthor('VEEV')
        self.x, self.y, self.w = 2 * mm, 2 * mm, 206 * mm
        self.col = self.w / 4
        self.c.setStrokeColor(colors.black)
        self.c.setFillColor(colors.black)

    def fill(self, x, top, width, height):
        self.c.setFillColor(colors.Color(.95, .95, .95))
        self.c.rect(x, A4[1] - top - height, width, height, stroke=0, fill=1)
        self.c.setFillColor(colors.black)

    def paragraph(self, value, x, top, width, height, font='DValue', size=7):
        p = Paragraph(escape(value or '-').replace('\n', '<br/>'),
                      ParagraphStyle('p', fontName=font, fontSize=size, leading=size * 1.18,
                                     textColor=colors.black, splitLongWords=1))
        _, h = p.wrap(width, height)
        if h > height + .2:
            raise ValueError('Conteudo excede o campo do DANFSe; revise o leiaute antes de imprimir')
        p.drawOn(self.c, x, A4[1] - top - h)

    def line(self, top):
        self.c.setLineWidth(.5)
        self.c.line(self.x, A4[1] - top, self.x + self.w, A4[1] - top)

    def cell(self, label, value, col, row, span=1, top=None, ident=False, shade=False):
        y = (self.y if top is None else top) + row * 6.5 * mm
        x, w = self.x + col * self.col, self.col * span
        if shade:
            self.fill(x, y, w, 6.5 * mm)
        self.paragraph(label.upper() if ident else label, x + 1 * mm, y + .5 * mm,
                       w - 2 * mm, 3 * mm, 'DLabel', 7 if ident else 6)
        value = value or '-'
        # NT 008 permite reticencias quando nomes/descricoes de codigos nao cabem.
        while pdfmetrics.stringWidth(value, 'DValue', 7) > w - 2 * mm:
            value = value[:-4] + '...' if len(value) > 4 else '-'
        self.paragraph(value, x + 1 * mm, y + 3.2 * mm, w - 2 * mm, 3.2 * mm)

    def title(self, value, top=None):
        y = self.y if top is None else top
        self.fill(self.x, y, self.col, 6.5 * mm)
        self.paragraph(value, self.x + mm, y + .6 * mm, self.col - 2 * mm,
                       5.7 * mm, 'DLabel', 7)

    def advance(self, height):
        self.y += height * mm
        self.line(self.y)

    def absent(self, value):
        self.fill(self.x, self.y, self.w, 6 * mm)
        self.paragraph(value, self.x + mm, self.y + 1.4 * mm, self.w - 2 * mm,
                       4 * mm, 'DLabel', 7)
        self.advance(6)

    def finish(self):
        self.c.setLineWidth(1)
        self.c.rect(self.x, 2 * mm, self.w, A4[1] - 4 * mm, stroke=1, fill=0)
        self.c.showPage()
        self.c.save()


def generate(xml_path, output, expected_doc='', expected_key='', expected_hash=''):
    raw = Path(xml_path).read_bytes()
    if len(raw) > 524288:
        raise ValueError('XML muito grande')
    source = raw.decode('utf-8-sig')
    if re.search(r'<!\s*(DOCTYPE|ENTITY)', source, re.I):
        raise ValueError('DTD/entidades nao permitidas')
    if expected_hash and hashlib.sha256(raw).hexdigest() != expected_hash:
        raise ValueError('Hash do XML difere do registro da nota')
    root = ET.fromstring(source)
    if root.tag != N + 'NFSe' or len(root.findall('n:infNFSe', NS)) != 1:
        raise ValueError('Esperado XML de NFS-e Nacional autorizada')
    info = elem(root, 'infNFSe')
    dps = elem(info, 'DPS/infDPS')
    if text(dps, 'tpAmb') not in ('1','2') or text(info, 'cStat') != '100':
        raise ValueError('Ambiente ou autorizacao da NFS-e invalido')
    production = text(dps, 'tpAmb') == '1'
    ibs = ibs_data(info, dps)
    key = info.attrib.get('Id', '')
    if not re.fullmatch(r'NFS\d{50}', key):
        raise ValueError('Chave da NFS-e invalida')
    key = key[3:]
    prest, emit = elem(dps, 'prest'), elem(info, 'emit')
    issuer = text(prest, 'CNPJ')
    if issuer != text(emit, 'CNPJ') or issuer != key[9:23]:
        raise ValueError('Prestador inconsistente no XML')
    if expected_doc and expected_doc != issuer or expected_key and expected_key != key:
        raise ValueError('XML nao pertence a nota solicitada')
    font_mode = register_fonts(production)
    sheet = Sheet(output, production)
    c = sheet.c
    sheet.fill(sheet.x, sheet.y, sheet.w, 14 * mm)
    logo = Path(__file__).parent / 'danfse-assets/logo-nfse.png'
    if not logo.is_file():
        raise ValueError('Logotipo oficial ausente')
    c.drawImage(str(logo), 5 * mm, A4[1] - 12 * mm, width=40 * mm, height=8.1 * mm, mask='auto')
    c.setFont('DLabel', 9)
    c.drawCentredString(105 * mm, A4[1] - 5.2 * mm, 'DANFSe v2.0')
    c.drawCentredString(105 * mm, A4[1] - 8.7 * mm, 'Documento Auxiliar da NFS-e')
    if not production:
        c.setFillColor(colors.CMYKColor(0, 1, 1, 0))
        c.drawCentredString(105 * mm, A4[1] - 12.5 * mm, 'NFS-e SEM VALIDADE JURÍDICA')
    c.setFillColor(colors.black)
    uf = text(emit, 'enderNac/UF')
    city = text(info, 'xLocEmi')
    sheet.paragraph('Município: ' + city + ' / ' + uf, 157 * mm, 3 * mm, 49 * mm, 5 * mm, size=8)
    sheet.paragraph('Ambiente Gerador: ' + mapped(text(info, 'ambGer'), {'1': 'Município', '2': 'Sefin Nacional'}),
                    157 * mm, 9 * mm, 49 * mm, 3 * mm, size=6)
    sheet.paragraph('Tipo de Ambiente: '+('Produção' if production else 'Homologação'), 157 * mm, 12 * mm, 49 * mm, 3 * mm, size=6)
    sheet.advance(14)
    sheet.cell('Chave de Acesso da NFS-e', key, 0, 0, 3, ident=True)
    for label, value, col, row in [
        ('Número da NFS-e', text(info, 'nNFSe'), 0, 1),
        ('Competência da NFS-e', date(text(dps, 'dCompet')), 1, 1),
        ('Data e Hora da Emissão da NFS-e', date(text(info, 'dhProc'), True), 2, 1),
        ('Número da DPS', text(dps, 'nDPS'), 0, 2), ('Série da DPS', text(dps, 'serie'), 1, 2),
        ('Data e Hora da Emissão da DPS', date(text(dps, 'dhEmi'), True), 2, 2),
        ('Emitente da NFS-e', mapped(text(dps, 'tpEmit'), {'1': 'Prestador', '2': 'Tomador', '3': 'Intermediário'}), 0, 3),
        ('Situação da NFS-e', 'NFS-e Gerada', 1, 3), ('Finalidade', '-', 2, 3)]:
        sheet.cell(label, value, col, row, ident=True, shade=col == 0 and row == 3)
    qr_url = 'https://www.nfse.gov.br/ConsultaPublica/?tpc=1&chave=' + key
    widget = QrCodeWidget(qr_url, barLevel='M', barBorder=4)
    x1, y1, x2, y2 = widget.getBounds()
    qr_size = 17 * mm
    drawing = Drawing(qr_size, qr_size, transform=[qr_size / (x2-x1), 0, 0, qr_size / (y2-y1), 0, 0])
    drawing.add(widget)
    renderPDF.draw(drawing, c, 174.8 * mm, A4[1] - (16.7 * mm + qr_size))
    sheet.paragraph('A autenticidade desta NFS-e pode ser verificada pela leitura deste código QR ou pela consulta da chave de acesso no portal nacional da NFS-e',
                    157 * mm, 35 * mm, 49 * mm, 9 * mm, size=6)
    sheet.advance(28)

    def party(node, heading, is_prest=False):
        if node is None:
            sheet.absent(heading + ' DA OPERAÇÃO NÃO IDENTIFICADO NA NFS-e')
            return
        sheet.title(heading)
        addr = elem(node, 'end')
        national = elem(addr, 'endNac')
        if is_prest and addr is None:
            addr, national = elem(emit, 'enderNac'), elem(emit, 'enderNac')
        get = lambda field: text(node, field) or (text(emit, field) if is_prest else '')
        doc = get('CNPJ') or get('CPF') or get('NIF')
        code = text(national, 'cMun')
        loc = (city + ' / ' + uf) if code and code == text(emit, 'enderNac/cMun') else (code or text(elem(addr, 'endExt'), 'xCidade'))
        cep = text(national, 'CEP')
        if len(cep) == 8:
            cep = cep[:5] + '-' + cep[5:]
        address = ', '.join(text(addr, p) for p in ('xLgr', 'nro', 'xCpl', 'xBairro') if text(addr, p))
        sheet.cell('CNPJ / CPF / NIF', document(doc), 1, 0)
        sheet.cell('Indicador Municipal (Inscrição)', get('IM'), 2, 0)
        sheet.cell('Telefone', get('fone'), 3, 0)
        sheet.cell('Nome / Nome Empresarial', get('xNome'), 0, 1, 2)
        sheet.cell('Município / Sigla UF', loc, 2, 1)
        sheet.cell('Código IBGE / CEP', ' / '.join(v for v in (code, cep) if v), 3, 1)
        sheet.cell('Endereço', address, 0, 2, 2)
        sheet.cell('E-mail', get('email'), 2, 2, 2)
        if is_prest:
            sheet.cell('Simples Nacional na Data de Competência', mapped(text(node, 'regTrib/opSimpNac'),
                {'1': 'Não Optante', '2': 'Optante - MEI', '3': 'Optante - ME/EPP'}), 0, 3, 2)
            sheet.cell('Regime de Apuração Tributária pelo SN', mapped(text(node, 'regTrib/regApTribSN'),
                {'1': 'Regime de apuração dos tributos federais e municipal pelo Simples Nacional',
                 '2': 'Tributos federais pelo SN e ISSQN pela NFS-e', '3': 'Tributos federais e municipal pela NFS-e'}), 2, 3, 2)
        sheet.advance(26 if is_prest else 19.5)

    party(prest, 'PRESTADOR / FORNECEDOR', True)
    party(elem(dps, 'toma'), 'TOMADOR/ADQUIRENTE')
    if ibs:
        sheet.absent('O DESTINATÁRIO É O PRÓPRIO TOMADOR/ADQUIRENTE DA OPERAÇÃO')
    else:
        party(None, 'DESTINATÁRIO')
    party(elem(dps, 'interm'), 'INTERMEDIÁRIO')
    service_height = 18 + sum(13.5 for path in ('toma', 'interm') if elem(dps, path) is None) + 13.5
    sheet.title('SERVIÇO PRESTADO')
    service = elem(dps, 'serv/cServ')
    sheet.cell('Código de Tributação Nacional / Municipal', ' / '.join(x for x in (text(service, 'cTribNac'), text(service, 'cTribMun')) if x), 1, 0)
    sheet.cell('Código da NBS', text(service, 'cNBS'), 2, 0)
    local = text(info, 'xLocPrestacao')
    sheet.cell('Local da Prestação / Sigla UF / País', local + (' / ' + uf if text(dps, 'serv/locPrest/cLocPrestacao') == text(emit, 'enderNac/cMun') else ''), 3, 0)
    description_code = text(info, 'xTribMun') or text(info, 'xTribNac')
    sheet.paragraph(description_code, sheet.x + mm, sheet.y + 7 * mm, sheet.w - 2 * mm, 7 * mm)
    sheet.paragraph('Descrição do Serviço', sheet.x + mm, sheet.y + 15 * mm, sheet.w - 2 * mm, 3 * mm, 'DLabel', 6)
    sheet.paragraph(text(service, 'xDescServ'), sheet.x + mm, sheet.y + 18 * mm,
                    sheet.w - 2 * mm, (service_height - 19) * mm)
    sheet.advance(service_height)
    tax = elem(dps, 'valores/trib/tribMun')
    values = elem(info, 'valores')
    sheet.title('TRIBUTAÇÃO MUNICIPAL (ISSQN)')
    sheet.cell('Tipo de Tributação do ISSQN', mapped(text(tax, 'tribISSQN'),
        {'1': 'Operação Tributável', '2': 'Imunidade', '3': 'Exportação de Serviço', '4': 'Não Incidência'}), 1, 0)
    sheet.cell('Município / Sigla UF / País de Incidência do ISSQN', text(info, 'xLocIncid') +
        (' / ' + uf if text(info, 'cLocIncid') == text(emit, 'enderNac/cMun') else ''), 2, 0, 2)
    for label, value, col, row in [
        ('Regime Especial de Tributação do ISSQN', mapped(text(prest, 'regTrib/regEspTrib'), {'0': 'Nenhum'}), 0, 1),
        ('Tipo de Imunidade do ISSQN', text(tax, 'tpImunidade'), 1, 1),
        ('Suspensão da Exigibilidade do ISSQN', text(tax, 'exigSusp/tpSusp'), 2, 1),
        ('Número Processo Suspensão', text(tax, 'exigSusp/nProcesso'), 3, 1),
        ('Benefício Municipal', text(tax, 'BM/nBM'), 0, 2), ('Cálculo do BM', text(tax, 'BM/tpBM'), 1, 2),
        ('Total Deduções/Reduções', money(text(values, 'vCalcDR')), 2, 2),
        ('Desconto Incondicionado', money(text(dps, 'valores/vDescCondIncond/vDescIncond')), 3, 2),
        ('BC ISSQN', money(text(values, 'vBC')), 0, 3), ('Alíquota Aplicada', percent(text(values, 'pAliqAplic')), 1, 3),
        ('Retenção do ISSQN', mapped(text(tax, 'tpRetISSQN'), {'1': 'Não Retido', '2': 'Retido pelo Tomador', '3': 'Retido pelo Intermediário'}), 2, 3),
        ('ISSQN Apurado', money(text(values, 'vISSQN')), 3, 3)]:
        sheet.cell(label, value, col, row)
    sheet.advance(26)
    federal = elem(dps, 'valores/trib/tribFed')
    sheet.title('TRIBUTAÇÃO FEDERAL (EXCETO CBS)')
    sheet.cell('IRRF', money(text(federal, 'vRetIRRF')), 1, 0)
    sheet.cell('Contribuição Previdenciária - Retida', money(text(federal, 'vRetCP')), 2, 0)
    sheet.cell('Contribuições Sociais - Retidas', money(text(federal, 'vRetCSLL')), 3, 0)
    sheet.cell('PIS - Débito Apuração Própria', money(text(federal, 'piscofins/vPis')), 0, 1)
    sheet.cell('COFINS - Débito Apuração Própria', money(text(federal, 'piscofins/vCofins')), 1, 1)
    sheet.cell('Descrição Contribuições Sociais - Retidas', '', 2, 1, 2)
    sheet.advance(13)
    sheet.title('TRIBUTAÇÃO IBS / CBS')
    declared, returned, classification = ibs if ibs else (None, None, None)
    ibv = lambda path: text(returned, 'valores/' + path)
    ibt = lambda path: text(returned, 'totCIBS/' + path)
    location_code = text(returned, 'cLocalidadeIncid')
    location_uf = uf if location_code == text(emit, 'enderNac/cMun') else ''
    sheet.cell('CST / cClassTrib', ' / '.join(v for v in (text(classification, 'CST'), text(classification, 'cClassTrib')) if v), 1, 0)
    sheet.cell('Indicador Operação / Código IBGE / Município Incidência / UF',
               ' / '.join(v for v in (text(declared, 'cIndOp'), location_code, text(returned, 'xLocalidadeIncid'), location_uf) if v), 2, 0, 2)
    exclusions = sum_money([text(dps, 'valores/vDescCondIncond/vDescIncond'),
        ibv('vCalcReeRepRes'), text(values, 'vISSQN'), text(federal, 'piscofins/vPis'),
        text(federal, 'piscofins/vCofins')]) if ibs else '-'
    tax_values = [
        [exclusions, money(ibv('vBC')),
         ' / '.join(percent(ibv(p)) for p in ('uf/pRedAliqUF','mun/pRedAliqMun','fed/pRedAliqCBS')) if ibs else '-',
         ' / '.join(percent(ibv(p)) for p in ('uf/pIBSUF','mun/pIBSMun')) if ibs else '-'],
        [percent(ibv('mun/pAliqEfetMun')), money(ibt('gIBS/gIBSMunTot/vIBSMun')),
         percent(ibv('uf/pAliqEfetUF')), money(ibt('gIBS/gIBSUFTot/vIBSUF'))],
        [money(ibt('gIBS/vIBSTot')), percent(ibv('fed/pCBS')),
         percent(ibv('fed/pAliqEfetCBS')), money(ibt('gCBS/vCBS'))]]
    for row, labels in enumerate([
        ('Exclusões e Reduções da Base de Cálculo', 'Base de Cálculo Após Exclusões e Reduções', 'Red. Alíquotas IBS / Red. Alíquotas CBS', 'Alíquota - IBS UF / IBS Mun'),
        ('Alíquota Efetiva Municipal - IBS', 'Valor Apurado Municipal - IBS', 'Alíquota Efetiva Estadual - IBS', 'Valor Apurado Estadual - IBS'),
        ('Valor Total Apurado - IBS', 'Alíquota - CBS', 'Alíquota Efetiva - CBS', 'Valor Total Apurado - CBS')], 1):
        for col, label in enumerate(labels):
            sheet.cell(label, tax_values[row-1][col], col, row)
    sheet.advance(26)
    sheet.title('VALOR TOTAL DA NFS-e')
    sheet.cell('Valor da Operação / Serviço', money(text(dps, 'valores/vServPrest/vServ')), 1, 0)
    sheet.cell('Desconto Incondicionado', money(text(dps, 'valores/vDescCondIncond/vDescIncond')), 2, 0)
    sheet.cell('Desconto Condicionado', money(text(dps, 'valores/vDescCondIncond/vDescCond')), 3, 0)
    sheet.cell('Total das Retenções (ISSQN / Federais)', money(text(values, 'vTotalRet')), 0, 1)
    sheet.cell('Valor Líquido da NFS-e', money(text(values, 'vLiq')), 1, 1)
    sheet.cell('Total do IBS/CBS', sum_money([ibt('gIBS/vIBSTot'), ibt('gCBS/vCBS')]), 2, 1)
    sheet.cell('Valor Líquido da NFS-e + IBS/CBS', money(ibt('vTotNF')), 3, 1, shade=True)
    sheet.advance(13)
    sheet.fill(sheet.x, sheet.y, sheet.w, 4 * mm)
    sheet.paragraph('INFORMAÇÕES COMPLEMENTARES', sheet.x + mm, sheet.y + .6 * mm,
                    sheet.w - 2 * mm, 3 * mm, 'DLabel', 7)
    extra = [text(info, 'xOutInf'), text(dps, 'serv/infoCompl/xInfComp')]
    totals = elem(dps, 'valores/trib/totTrib')
    if text(totals, 'pTotTribSN'):
        extra.append('Totais Aproximados dos Tributos cfe. Lei nº 12.741/2012: Simples Nacional: ' + percent(text(totals, 'pTotTribSN')))
    for node, label in [('vTotTrib', 'R$'), ('pTotTrib', '%')]:
        group = elem(totals, node)
        if group is not None:
            extra.append('Totais Aproximados dos Tributos cfe. Lei nº 12.741/2012: ' +
                         '; '.join(name + ': ' + (money(text(group, field)) if label == 'R$' else percent(text(group, field)))
                                   for name, field in [('Federais', node + 'Fed'), ('Estaduais', node + 'Est'), ('Municipais', node + 'Mun')]))
    sheet.paragraph('\n'.join(x for x in extra if x) or '-', sheet.x + mm, sheet.y + 5 * mm,
                    sheet.w - 2 * mm, A4[1] - sheet.y - 8 * mm)
    sheet.finish()
    return {'invoice_number': text(info, 'nNFSe'), 'access_key': key, 'fonts': font_mode,
            'xml_sha256': hashlib.sha256(raw).hexdigest(),'environment':'producao' if production else 'homologacao'}


def main():
    p = argparse.ArgumentParser()
    p.add_argument('xml')
    p.add_argument('pdf')
    p.add_argument('--document', default='')
    p.add_argument('--key', default='')
    p.add_argument('--sha256', default='')
    args = p.parse_args()
    try:
        result = generate(args.xml, args.pdf, args.document, args.key, args.sha256)
        print('OK: DANFSe de '+result['environment']+' gerado; fontes: ' + result['fonts'])
    except Exception as exc:
        Path(args.pdf).unlink(missing_ok=True)
        print('DANFSe: ' + str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
