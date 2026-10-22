import {totalsReport, printTotalsReport} from './print-totals.js';
const app = document.querySelector('#app');
const dialog = document.querySelector('#dialog');
let token = null;
let company = null;
let page = 'overview';
let environment='homologacao', emissionConfig={production_available:false};
const envLabel = value => value==='producao'?'Produção':'Homologação';
const envHint = value => value==='producao'?'Produção: as notas emitidas possuem validade fiscal.':'Homologação: notas de teste, sem validade fiscal.';
let data = { invoices: [], drafts: [], customers: [], settings: {} };
let generation = 0;
let toastTimer, invoiceSearchTimer;
let sending = false;
let invoiceFilters = {from:'',to:'',search:'',status:''};
const invoicePath = () => '/invoices?' + new URLSearchParams({date_from:invoiceFilters.from,date_to:invoiceFilters.to,status:invoiceFilters.status,environment,search:invoiceFilters.search,include_totals:1});
const labels = { overview: 'Visão geral', new: 'Nova NFS-e', invoices: 'Notas fiscais', drafts: 'Rascunhos', customers: 'Tomadores', settings: 'Configurações' };
const paths = {
  overview:'M3 3h7v7H3z M14 3h7v7h-7z M3 14h7v7H3z M14 14h7v7h-7z',
  new:'M12 5v14 M5 12h14', invoices:'M6 3h9l4 4v14H5V3z M14 3v5h5 M8 12h8 M8 16h6',
  drafts:'M4 5h16v15H4z M8 2v6 M16 2v6 M8 12h8 M8 16h5',
  customers:'M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2 M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8 M22 21v-2a4 4 0 0 0-3-3.87 M16 3.13a4 4 0 0 1 0 7.75',
  settings:'M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8 M12 2v3 M12 19v3 M2 12h3 M19 12h3 M5 5l2 2 M17 17l2 2 M5 19l2-2 M17 7l2-2',
  arrow:'M5 12h14 M13 6l6 6-6 6', check:'M5 12l4 4L19 6', logout:'M9 3H4v18h5 M12 12h9 M17 8l4 4-4 4', shield:'M12 2l9 4v6c0 5-9 10-9 10S3 17 3 12V6z M8 12l3 3 5-6', download:'M12 3v12 M7 10l5 5 5-5 M4 16v5h16v-5'
};
const icon = name => `<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="${paths[name] || paths.invoices}"/></svg>`;
const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const money = value => new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format((Number(value) || 0) / 100);
const date = value => value ? new Intl.DateTimeFormat('pt-BR', {dateStyle:'short',timeStyle:'short',timeZone:'America/Sao_Paulo'}).format(new Date(value)) : '—';
const doc = value => String(value || '').replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, '$1.$2.$3/$4-$5').replace(/^(\d{3})(\d{3})(\d{3})(\d{2})$/, '$1.$2.$3-$4');
const brand = () => '<div class="brand"><span class="brand-mark">∨∨</span><div>VEEV<small>NOTAS DE SERVIÇO</small></div></div>';
const empty = (title, text) => `<div class="empty">${icon('invoices')}<strong>${esc(title)}</strong>${esc(text)}</div>`;
const badge = status => {
  const map = {cancelled:['Cancelada','bad'],authorized_production:['Autorizada',''],authorized_homologation:['Autorizada',''],imported:['Importada','neutral'],authorized:['Autorizada',''],draft:['Rascunho','neutral'],reserved:['Reservada','warn'],prepared:['Preparada','warn'],sending:['Em processamento','warn'],unknown:['Resultado inconclusivo','warn'],local_error:['Falha na preparação','bad'],rejected:['Rejeitada','bad']};
  const [text, type] = map[status] || [status || 'Pendente','neutral'];
  return `<span class="badge ${type}">${esc(text)}</span>`;
};

function notice(message) {
  const node = document.querySelector('#notice');
  node.textContent = message;
  node.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => node.classList.remove('show'), 7000);
}

async function api(path, options = {}) {
  const {method = 'GET', body, binary = false} = options;
  const headers = {Accept: binary ? '*/*' : 'application/json'};
  if (token) headers.Authorization = 'Bearer ' + token;
  if (body !== undefined) headers['Content-Type'] = 'application/json; charset=utf-8';
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 125000);
  let response;
  try {
    response = await fetch('/v1' + path, {method, headers, body: body === undefined ? undefined : JSON.stringify(body), signal: controller.signal, cache:'no-store', credentials:'omit'});
  } catch (error) {
    throw new Error(method === 'POST' && path.includes('/emit-')
      ? 'O envio ficou sem confirmação. Consulte a tentativa antes de qualquer nova emissão.'
      : 'Não foi possível conectar. Verifique sua conexão e tente novamente.');
  } finally { clearTimeout(timeout); }
  if (!response.ok) {
    let message = `Não foi possível concluir a operação (HTTP ${response.status}).`;
    try { message = (await response.json()).error || message; } catch { /* proxy may return HTML */ }
    if (response.status === 401 && path !== '/auth/login') {
      clearSession();
      renderLogin('Seu acesso expirou ou foi bloqueado. Entre novamente.');
      throw new Error('Sessão encerrada. Entre novamente.');
    }
    throw new Error(message);
  }
  return binary ? response.blob() : response.json();
}

function clearSession() {
  token = null;
  company = null;
  environment='homologacao'; emissionConfig={production_available:false};
  data = {invoices:[],drafts:[],customers:[],settings:{}};
  invoiceFilters = {from:'',to:'',search:'',status:''};
  generation++;
  if (dialog.open) dialog.close();
}

function renderLogin(error = '') {
  app.innerHTML = `<main class="login"><section class="login-story">${brand()}<div><div class="eyebrow">Sua gestão, mais simples</div><h1>Menos etapas.<br>Mais tempo para<br><em>o seu negócio.</em></h1><p>Emita, acompanhe e organize suas notas de serviço em um só lugar.</p><div class="login-art" aria-hidden="true"><span></span><span></span><span></span><span></span></div></div><div class="login-footer">VEEV Sistemas · NFS-e Nacional</div></section><section class="login-form-wrap"><form class="login-form" id="login-form"><div class="eyebrow">Bem-vindo à VEEV</div><h2>Acesse sua empresa</h2><p class="subtle">Entre com o CNPJ e a senha cadastrada.</p><label class="field">CNPJ<input name="cnpj" inputmode="numeric" autocomplete="username" placeholder="00.000.000/0000-00" maxlength="18" required></label><label class="field">Senha<div class="password-row"><input type="password" name="password" autocomplete="current-password" required minlength="12"><button type="button" id="show-password" aria-label="Mostrar senha">Mostrar</button></div></label><p class="error" id="login-error" role="alert">${esc(error)}</p><button class="primary full" type="submit">Entrar na minha conta ${icon('arrow')}</button><div class="hint">${icon('shield')} Confira o ambiente antes de emitir. Produção gera documentos com validade fiscal.</div><p class="subtle">Precisa de acesso ou esqueceu a senha?<br>Entre em contato com o administrador.</p><p><a class="inline-link" href="/admin.html">Acesso administrativo</a></p></form></section></main>`;
  document.querySelector('#show-password').onclick = event => {
    const input = document.querySelector('[name=password]');
    input.type = input.type === 'password' ? 'text' : 'password';
    event.currentTarget.textContent = input.type === 'password' ? 'Mostrar' : 'Ocultar';
  };
  document.querySelector('#login-form').onsubmit = async event => {
    event.preventDefault();
    const form = event.currentTarget;
    const button = form.querySelector('[type=submit]');
    const cnpj = form.elements.cnpj.value.replace(/\D/g, '');
    if (cnpj.length !== 14) { document.querySelector('#login-error').textContent = 'Informe um CNPJ com 14 dígitos.'; return; }
    button.disabled = true;
    button.textContent = 'Entrando…';
    document.querySelector('#login-error').textContent = '';
    try {
      const result = await api('/auth/login', {method:'POST', body:{cnpj,password:form.elements.password.value}});
      form.elements.password.value = '';
      token = result.access_token;
      company = {id:result.company_id,name:result.name,document:result.document};
      page = 'overview';
      renderShell();
      await load();
    } catch (error) {
      if (!company) {
        const field = document.querySelector('#login-error');
        if (field) field.textContent = error.message;
      } else notice(error.message);
    } finally {
      if (button.isConnected) { button.disabled = false; button.innerHTML = `Entrar na minha conta ${icon('arrow')}`; }
    }
  };
}

function renderShell() {
  app.innerHTML = `<div class="shell"><aside class="sidebar">${brand()}<div class="nav-label">ÁREA DA EMPRESA</div><nav class="nav" aria-label="Menu principal">${Object.entries(labels).map(([key,label]) => `<button data-page="${key}" class="${page === key ? 'active' : ''}">${icon(key)}${label}</button>`).join('')}</nav><div class="sidebar-foot"><div class="field">Ambiente<strong id="active-environment">${envLabel(environment)}</strong><small>Definido pelo administrador</small></div><p>${envHint(environment)}</p></div></aside><div class="workspace"><header class="topbar"><div class="breadcrumb">NFS-e Nacional &nbsp; / &nbsp; <strong id="breadcrumb">${labels[page]}</strong></div><div class="company"><span class="avatar">${esc(company.name.slice(0,2).toUpperCase())}</span><div><div class="company-name">${esc(company.name)}</div><div class="company-doc">${esc(doc(company.document))}</div></div><button class="text-button" id="logout" title="Sair da conta">${icon('logout')} Sair</button></div></header><main class="content" id="content"><div class="loading">Carregando seus dados…</div></main></div></div>`;
  document.querySelectorAll('[data-page]').forEach(button => button.onclick = () => navigate(button.dataset.page));
  document.querySelector('#logout').onclick = async () => {
    try { await api('/auth/logout', {method:'POST'}); }
    catch (error) { notice(error.message); }
    finally { clearSession(); renderLogin(); }
  };
}

async function load() {
  const current = ++generation;
  try {
    const config=await api('/emission-config');
    if (!company || current !== generation) return;
    const active=config.active_environment||'homologacao';
    if(environment!==active){environment=active;invoiceFilters={from:'',to:'',search:'',status:''};renderShell();}
    const [settings, customers, drafts, invoices] = await Promise.all(['/settings','/customers','/drafts?environment='+environment,invoicePath()].map(path => api(path)));
    if (!company || current !== generation) return;
    emissionConfig=config;
    data = {settings,customers,drafts:drafts.filter(d=>(d.environment||'homologacao')===environment),invoices:Array.isArray(invoices)?invoices:invoices.invoices,invoiceSummary:invoices.summary||null};
    renderPage();
  } catch (error) {
    if (!company || current !== generation) return;
    document.querySelector('#content').innerHTML = `<div class="panel">${empty('Não foi possível carregar os dados',error.message)}<div class="panel-body"><button class="secondary" id="retry">Tentar novamente</button></div></div>`;
    document.querySelector('#retry').onclick = load;
  }
}

function navigate(next) {
  clearTimeout(invoiceSearchTimer);
  page = next;
  document.querySelectorAll('[data-page]').forEach(button => button.classList.toggle('active',button.dataset.page === page));
  document.querySelector('#breadcrumb').textContent = labels[page];
  renderPage();
}

function title(heading, subtitle, action = '') {
  return `<div class="page-title"><div><h1>${heading}</h1><p class="subtle">${subtitle}</p></div>${action}</div>`;
}
const newButton = () => `<button class="primary" data-go="new">${icon('new')} Nova NFS-e</button>`;
const customerName = id => data.customers.find(c => c.id === id)?.name?.toLocaleUpperCase('pt-BR') || (id ? 'Tomador cadastrado' : 'Tomador não informado');
function draftStatus(draft) {
  return data.invoices.some(i => i.draft_id === draft.id) ? 'authorized' : draft.attempt_status || 'draft';
}

const paymentMethods = [['dinheiro','Dinheiro'],['pix','PIX'],['boleto','Boleto'],['cartao_credito','Cartão de crédito'],['cartao_debito','Cartão de débito']];
const paymentLabel = value => paymentMethods.find(([key])=>key===value)?.[1] || 'Não informado';
function invoiceTotals(summary) {
  if (!summary) return '';
  const byPayment = [...paymentMethods,['nao_informado','Não informado']].map(([method,label])=>{
    const item=summary.by_payment.find(p=>p.payment_method===method)||{count:0,total_cents:0};
    return `<article class="payment-total"><span>${label}</span><strong>${money(item.total_cents)}</strong><small>${item.count} nota(s)</small></article>`;
  }).join('');
  return `<section class="panel invoice-totals" aria-label="Totais das notas filtradas"><div class="panel-header"><div><h2>Totais da consulta</h2><p>Todo o resultado dos filtros, incluindo a busca. Canceladas não entram no total geral nem nos totais por pagamento.</p></div><div class="actions report-actions"><button class="secondary" data-print-totals="a4">Imprimir A4</button><button class="secondary" data-print-totals="80mm">Imprimir bobina 80 mm</button></div></div><div class="totals-main"><div><span>Quantidade de notas</span><strong>${summary.count}</strong></div><div><span>Total geral (sem canceladas)</span><strong>${money(summary.total_cents)}</strong></div><div><span>Canceladas: ${summary.cancelled_count}</span><strong>${money(summary.cancelled_cents)}</strong></div></div><div class="payment-totals">${byPayment}</div><p class="footer-note">Forma de pagamento informada no lançamento; não representa confirmação de recebimento. Notas antigas ou importadas podem constar como não informado.</p></section>`;
}

async function previewInvoiceTotals(format) {
  const companySnapshot = company && {...company};
  const environmentSnapshot = environment;
  const filters = {...invoiceFilters};
  const buttons = document.querySelectorAll('[data-print-totals]');
  buttons.forEach(button=>button.disabled=true);
  try {
    const result = await api('/invoices?' + new URLSearchParams({date_from:filters.from,date_to:filters.to,status:filters.status,environment:environmentSnapshot,search:filters.search,include_totals:1}));
    if (!company || company.id!==companySnapshot?.id) return;
    if (!result.summary) throw new Error('Não foi possível obter os totais para impressão. Atualize a consulta.');
    const html = totalsReport({company:companySnapshot,environment:environmentSnapshot,filters,summary:result.summary,generatedAt:new Date().toISOString()}, {esc,money,date,envLabel,paymentMethods});
    const receipt = format==='80mm';
    dialog.classList.add('totals-print-dialog');
    dialog.innerHTML = `<h2 id="dialog-title">${receipt?'Impressão em bobina 80 mm':'Impressão A4'}</h2><p class="subtle">${receipt?'Selecione a impressora e o papel de 80 mm. Desative cabeçalhos e rodapés do navegador.':'Selecione o papel A4, orientação retrato. Você também pode salvar como PDF.'}</p><div class="totals-print-preview"><div class="${receipt?'report-receipt':'report-a4'}">${html}</div></div><div class="actions"><button class="secondary" data-close>Fechar</button><button class="primary" id="print-totals-confirm">Imprimir</button></div>`;
    const close = ()=>{dialog.close();dialog.classList.remove('totals-print-dialog');};
    dialog.querySelector('[data-close]').onclick=close;
    dialog.addEventListener('close',()=>dialog.classList.remove('totals-print-dialog'),{once:true});
    dialog.querySelector('#print-totals-confirm').onclick=async()=>{
      try {await printTotalsReport(html,format);} catch(error){notice(error.message);}
    };
    dialog.showModal();
  } catch(error) { notice(error.message); }
  finally {buttons.forEach(button=>{if(button.isConnected)button.disabled=false;});}
}

function invoiceTable(invoices) {
  if (!invoices.length) return empty('Nenhuma nota por aqui', 'As notas autorizadas aparecerão nesta lista.');
  return `<div class="table-wrap"><table><thead><tr><th>Nota / emissão</th><th>Tomador</th><th>Ambiente</th><th>Valor</th><th>Pagamento</th><th>Situação</th><th>Documentos</th></tr></thead><tbody>${invoices.map(note => `<tr><td><strong>NFS-e ${esc(note.invoice_number)}</strong><div class="minor">${esc(date(note.issued_at || note.imported_at))}</div></td><td>${esc((note.customer_name||'Tomador não informado').toLocaleUpperCase('pt-BR'))}</td><td>${envLabel(note.environment)}</td><td><strong>${money(note.amount_cents)}</strong></td><td>${esc(paymentLabel(note.payment_method))}</td><td>${badge(note.status)}</td><td><div class="actions">${note.status!=='cancelled'?`<button class="text-button" data-download="${esc(note.id)}" data-format="pdf">${icon('download')} DANFSe</button>`:''}<button class="text-button" data-download="${esc(note.id)}" data-format="xml">XML</button><button class="text-button" data-note="${esc(note.id)}">Detalhes</button>${['authorized_production','authorized_homologation'].includes(note.status)&&note.source==='sefin_api'&&!['sending','unknown'].includes(note.cancellation_status)?`<button class="text-button" data-cancel="${esc(note.id)}">Cancelar NFS-e</button>`:''}${note.status==='cancelled'||['sending','unknown'].includes(note.cancellation_status)?`<button class="text-button" data-cancel-result="${esc(note.id)}">Consultar cancelamento</button>`:''}</div></td></tr>`).join('')}</tbody></table></div>`;
}

function renderPage() {
  if (!company) return;
  const content = document.querySelector('#content');
  if (page === 'overview') {
    const pending = data.drafts.filter(d => draftStatus(d) === 'draft').length;
    content.innerHTML = title('Sua empresa, em dia.', 'Acompanhe suas notas e continue de onde parou.', newButton()) +
      `<div class="banner">${icon('shield')} ${envHint(environment)} ${environment==='producao'&&!emissionConfig.production_available?'A emissão está bloqueada. Consulte o administrador.':''}</div><div class="stats"><article class="stat"><span class="eyebrow">Notas disponíveis</span><span class="stat-icon">${icon('invoices')}</span><strong>${data.invoices.length}</strong><span class="subtle">Notas na consulta atual</span></article><article class="stat"><span class="eyebrow">Valor das notas</span><span class="stat-icon">${icon('check')}</span><strong>${money(data.invoices.reduce((sum,n) => sum + Number(n.amount_cents),0))}</strong><span class="subtle">${envLabel(environment)}</span></article><article class="stat"><span class="eyebrow">Rascunhos pendentes</span><span class="stat-icon">${icon('drafts')}</span><strong>${pending}</strong><span class="subtle">Prontos para revisar</span></article></div><section class="panel"><div class="panel-header"><div><h2>Últimas notas</h2><p>Documentos e informações em um só lugar.</p></div><button class="text-button" data-go="invoices">Ver todas ${icon('arrow')}</button></div>${invoiceTable(data.invoices.slice(0,5))}</section><p class="footer-note">Os indicadores consideram os últimos 100 registros retornados pelo sistema.</p>`;
  } else if (page === 'invoices') {
    content.innerHTML = title('Notas fiscais','Consulte por data de emissão e baixe os documentos.', '<button class="secondary" id="refresh">Atualizar lista</button>') + invoiceTotals(data.invoiceSummary) + `<section class="panel"><div class="panel-header"><div><h2>Suas NFS-e</h2><p>${data.invoiceSummary?.count??data.invoices.length} notas no período consultado · ${envLabel(environment)}</p></div></div><form class="table-tools invoice-filters" id="invoice-filters"><label class="field">Emissão de<input type="date" name="from" value="${esc(invoiceFilters.from)}"></label><label class="field">Até<input type="date" name="to" value="${esc(invoiceFilters.to)}"></label><label class="field">Situação<select name="status">${[['','Todas'],['authorized','Autorizadas'],['cancelled','Canceladas'],['imported','Importadas']].map(([value,label])=>`<option value="${value}" ${invoiceFilters.status===value?'selected':''}>${label}</option>`).join('')}</select></label><button class="primary" type="submit">Filtrar</button><button class="secondary" type="button" id="clear-filters">Limpar</button></form><div class="table-tools"><input class="search" id="invoice-search" type="search" maxlength="200" value="${esc(invoiceFilters.search)}" placeholder="Buscar por número, chave ou tomador" aria-label="Buscar nota"></div><div id="invoice-list"></div></section><p class="footer-note">A lista mostra até 100 notas; os totais consideram todas as notas dos filtros. Datas de emissão no horário de Brasília; data final incluída.</p>`;
    document.querySelectorAll('[data-print-totals]').forEach(button=>button.onclick=()=>previewInvoiceTotals(button.dataset.printTotals));
    document.querySelector('#refresh').onclick = load;
    document.querySelector('#invoice-filters').onsubmit = async event => {
      event.preventDefault();
      const form = event.currentTarget;
      const from = form.elements.from.value, to = form.elements.to.value;
      if (from && to && from > to) { notice('A data inicial deve ser anterior ou igual à final.'); return; }
      invoiceFilters.from = from; invoiceFilters.to = to; invoiceFilters.status=event.currentTarget.elements.status.value;
      await load();
    };
    document.querySelector('#clear-filters').onclick = () => { invoiceFilters = {from:'',to:'',search:'',status:''}; load(); };
    document.querySelector('#invoice-list').innerHTML = invoiceTable(data.invoices);
    bindDocuments();
    document.querySelector('#invoice-search').oninput = event => {
      invoiceFilters.search = event.target.value;
      clearTimeout(invoiceSearchTimer);
      invoiceSearchTimer = setTimeout(async()=>{
        if(page!=='invoices') return;
        await load();
        if(page!=='invoices') return;
        const input=document.querySelector('#invoice-search');
        if(input){input.focus();input.setSelectionRange(input.value.length,input.value.length);}
      },350);
    };
  } else if (page === 'drafts') {
    content.innerHTML = title('Rascunhos','Revise os dados antes de emitir. Ambiente: '+envLabel(environment)+'.', newButton()) + `<section class="panel"><div class="panel-header"><div><h2>Seus rascunhos</h2><p>Até 100 registros mais recentes.</p></div></div>${data.drafts.length ? `<div class="table-wrap"><table><thead><tr><th>Serviço / criação</th><th>Tomador</th><th>Valor</th><th>Situação</th><th>Ação</th></tr></thead><tbody>${data.drafts.map(d => `<tr><td><strong>${esc((d.settings?.service_description || 'Serviço').slice(0,48))}</strong><div class="minor">${esc(date(d.created_at))}</div></td><td>${esc(customerName(d.customer_id))}</td><td>${money(d.amount_cents)}</td><td>${badge(draftStatus(d))}</td><td><button class="text-button" data-draft="${esc(d.id)}">${draftStatus(d) === 'draft' ? 'Revisar' : 'Ver resultado'} ${icon('arrow')}</button></td></tr>`).join('')}</tbody></table></div>` : empty('Seu próximo serviço começa aqui','Crie um rascunho com valor, serviço e tomador opcional.')}</section>`;
    document.querySelectorAll('[data-draft]').forEach(button => button.onclick = () => reviewDraft(data.drafts.find(d => d.id === button.dataset.draft)));
  } else if (page === 'customers') {
    content.innerHTML = title('Tomadores','Mantenha os dados de quem recebe seus serviços.', '<button class="primary" id="new-customer">'+icon('new')+' Cadastrar tomador</button>') + `<section class="panel"><div class="panel-header"><div><h2>Tomadores cadastrados</h2><p>O tomador pode ser omitido na criação do rascunho.</p></div></div>${data.customers.length ? `<div class="table-wrap"><table><thead><tr><th>Nome / razão social</th><th>CPF ou CNPJ</th></tr></thead><tbody>${data.customers.map(c => `<tr><td><strong>${esc(c.name.toLocaleUpperCase('pt-BR'))}</strong></td><td>${esc(doc(c.document))}</td></tr>`).join('')}</tbody></table></div>` : empty('Nenhum tomador cadastrado','Cadastre pessoas e empresas para selecioná-las nas próximas notas.')}</section>`;
    document.querySelector('#new-customer').onclick = customerForm;
  } else if (page === 'settings') {
    content.innerHTML = title('Configurações','Dados da empresa e padrões para os próximos serviços.') + `<div class="split settings-layout"><section class="panel"><div class="panel-header"><div><h2>Padrões do serviço</h2><p>Alterações se aplicam somente aos novos rascunhos.</p></div></div><form id="settings-form" class="panel-body"><div class="form-grid">${settingsFields(data.settings)}</div><p class="error" role="alert" id="settings-error"></p><button type="submit" class="primary">Salvar configurações</button></form></section><section class="panel profile-card"><h3>Empresa conectada</h3><p class="subtle">${esc(company.name)}<br>${esc(doc(company.document))}</p><div class="divider"></div><div class="env-pill">${esc(envLabel(environment).toLocaleUpperCase("pt-BR"))}</div><p class="subtle" style="margin-top:15px">O certificado e o cadastro fiscal são gerenciados pelo administrador.</p></section></div>`;
    document.querySelector('#settings-form').onsubmit = saveSettings;
  } else if (page === 'new') renderNew(content);
  bindCommon();
}

function settingsFields(settings) {
  const field = (name,label,extra='') => `<label class="field">${label}<input name="${name}" value="${esc(settings[name] ?? '')}" ${extra} required></label>`;
  return `<label class="field span2">Regime tributário<select name="tax_regime"><option value="simples_nacional">Simples Nacional</option></select></label>` +
    field('service_code','Código nacional','pattern="[0-9]{6}" maxlength="6" inputmode="numeric"') + field('municipal_service_code','Código municipal','maxlength="3" inputmode="numeric"') + field('nbs_code','Código NBS','pattern="[0-9]{9}" maxlength="9" inputmode="numeric"') + field('approx_simples_percent','Tributos aproximados (%)','type="number" min="0" max="100" step="0.01"') + `<label class="field span2">Descrição do serviço<textarea name="service_description" maxlength="500" required>${esc(settings.service_description || '')}</textarea></label><div class="span2 divider"></div><div class="span2"><h2>IBS / CBS</h2><label class="check"><input type="checkbox" name="send_ibs_cbs" ${settings.send_ibs_cbs === true ? 'checked' : ''}> Enviar grupo IBS/CBS</label><p class="subtle">Desmarcado: não enviar. Perfil disponível: CST 200, classificação 200048 e operação 030101. Destinatário igual ao tomador; sem ajustes, créditos ou diferimento.</p></div><label class="field">CST IBS/CBS<input name="cst_ibs_cbs" value="${esc(settings.cst_ibs_cbs || '')}" placeholder="200" pattern="[0-9]{3}" maxlength="3" inputmode="numeric"></label><label class="field">Indicador da operação (cIndOp)<input name="cind_op" value="${esc(settings.cind_op || '')}" placeholder="030101" pattern="[0-9]{6}" maxlength="6" inputmode="numeric"></label><label class="field">Classificação tributária (cClassTrib)<input name="cclass_trib" value="${esc(settings.cclass_trib || '')}" placeholder="200048" pattern="[0-9]{6}" maxlength="6" inputmode="numeric"><span class="subtle">Pode ficar configurada mesmo sem enviar o grupo.</span></label>`;
}

function renderNew(content) {
  content.innerHTML = title('Nova nota de serviço','Prepare os dados e revise. Ambiente: '+envLabel(environment)+'.') + `<div class="steps"><span class="current"><b>1</b> Dados do serviço</span><span>—</span><span><b>2</b> Revisão</span><span>—</span><span><b>3</b> Emissão</span></div><div class="split"><section class="panel"><div class="panel-header"><div><h2>O que foi prestado?</h2><p>Os padrões cadastrados já estão preenchidos.</p></div><button class="primary" type="submit" form="draft-form">Salvar e revisar ${icon('arrow')}</button></div><form id="draft-form" class="panel-body"><div class="payment-row"><label class="field">Valor do serviço (R$)<input name="amount" inputmode="decimal" placeholder="0,00" required autocomplete="off"></label><label class="field">Forma de pagamento<select name="payment_method" required><option value="">Selecione…</option>${paymentMethods.map(([value,label])=>`<option value="${value}">${label}</option>`).join('')}</select></label></div><div class="form-grid">${settingsFields(data.settings)}</div><div class="divider"></div><h2>Quem é o tomador?</h2><label class="check"><input type="checkbox" name="anonymous" checked> Tomador não informado</label><label class="field" id="customer-field" hidden>Selecione o tomador<select name="customer_id"><option value="">Selecione…</option>${data.customers.map(c => `<option value="${esc(c.id)}">${esc(c.name.toLocaleUpperCase('pt-BR'))} · ${esc(doc(c.document))}</option>`).join('')}</select></label><p class="error" role="alert" id="draft-error"></p><button class="primary" type="submit">Salvar e revisar ${icon('arrow')}</button></form></section><aside><div class="panel profile-card"><h3>Resumo do serviço</h3><div class="summary-line"><span>Ambiente</span> ${envLabel(environment)}</div><div class="summary-line"><span>Prestador</span> ${esc(company.name)}</div><div class="summary-line total"><span>Valor do serviço</span><strong id="amount-preview">R$ 0,00</strong></div></div><div class="hint">Salvar um rascunho ainda não emite uma nota. Você poderá conferir os dados antes de confirmar.</div></aside></div>`;
  const form = document.querySelector('#draft-form');
  form.elements.anonymous.onchange = () => {
    document.querySelector('#customer-field').hidden = form.elements.anonymous.checked;
    form.elements.customer_id.required = !form.elements.anonymous.checked;
  };
  form.elements.amount.oninput = () => {
    try { document.querySelector('#amount-preview').textContent = money(parseAmount(form.elements.amount.value)); }
    catch { document.querySelector('#amount-preview').textContent = '—'; }
  };
  form.onsubmit = async event => {
    event.preventDefault();
    const buttons = document.querySelectorAll('[form="draft-form"], #draft-form [type=submit]');
    buttons.forEach(button=>button.disabled=true);
    try {
      const settings = readSettings(form);
      const draft = await api('/drafts', {method:'POST',body:{environment,payment_method:form.elements.payment_method.value,amount_cents:parseAmount(form.elements.amount.value),customer_id:form.elements.anonymous.checked ? null : form.elements.customer_id.value,overrides:settings}});
      data.drafts.unshift(draft);
      navigate('drafts');
      reviewDraft(draft);
    } catch (error) { const node = document.querySelector('#draft-error'); if(node) node.textContent = error.message; }
    finally { buttons.forEach(button=>button.disabled=false); }
  };
}

function parseAmount(value) {
  const normalized = value.trim().replace(/\s/g,'');
  if (!/^\d{1,10}(,\d{1,2})?$/.test(normalized)) throw new Error('Informe o valor sem pontos, usando vírgula para os centavos. Exemplo: 1500,50.');
  const [whole,fraction=''] = normalized.split(',');
  const amount = Number(whole)*100 + Number(fraction.padEnd(2,'0'));
  if (!Number.isSafeInteger(amount) || amount <= 0 || amount > 999999999999) throw new Error('Informe um valor positivo dentro do limite permitido.');
  return amount;
}

function readSettings(form) {
  const settings = {};
  for(const key of ['tax_regime','service_code','municipal_service_code','nbs_code','service_description']) settings[key] = form.elements[key].value.trim();
  settings.approx_simples_percent = Number(form.elements.approx_simples_percent.value);
  settings.send_ibs_cbs = form.elements.send_ibs_cbs.checked;
  for (const key of ['cclass_trib','cst_ibs_cbs','cind_op']) {
    if (form.elements[key].value.trim()) settings[key] = form.elements[key].value.trim();
  }
  if (settings.send_ibs_cbs && (settings.cst_ibs_cbs !== '200' || settings.cclass_trib !== '200048' || settings.cind_op !== '030101')) throw new Error('Para enviar IBS/CBS neste perfil, informe CST 200, cClassTrib 200048 e cIndOp 030101.');
  return settings;
}

async function saveSettings(event) {
  event.preventDefault();
  const form = event.currentTarget;
  const button = form.querySelector('[type=submit]');
  button.disabled = true;
  try { data.settings = await api('/settings',{method:'PATCH',body:readSettings(form)}); notice('Padrões salvos para os próximos rascunhos.'); }
  catch(error) { const node = document.querySelector('#settings-error'); if(node) node.textContent = error.message; }
  finally { button.disabled = false; }
}

function customerForm() {
  dialog.innerHTML = `<h2 id="dialog-title">Cadastrar tomador</h2><p class="subtle">Informe os dados da pessoa ou empresa.</p><form id="customer-form"><label class="field">Nome ou razão social<input name="name" class="uppercase" required maxlength="500" autocomplete="name"></label><label class="field">CPF ou CNPJ<input name="document" required inputmode="numeric" maxlength="18"></label><p class="error" id="customer-error" role="alert"></p><div class="actions"><button class="secondary" type="button" data-close>Cancelar</button><button class="primary" type="submit">Cadastrar tomador</button></div></form>`;
  dialog.showModal();
  const nameInput = dialog.querySelector('input[name=name]');
  if (nameInput) nameInput.oninput = () => {
    const start = nameInput.selectionStart, end = nameInput.selectionEnd;
    nameInput.value = nameInput.value.toLocaleUpperCase('pt-BR');
    nameInput.setSelectionRange(start,end);
  };
  dialog.querySelector('[data-close]').onclick = () => dialog.close();
  dialog.querySelector('form').onsubmit = async event => {
    event.preventDefault();
    const form = event.currentTarget;
    const button = form.querySelector('[type=submit]');
    const document = form.elements.document.value.replace(/\D/g,'');
    if (![11,14].includes(document.length)) { dialog.querySelector('#customer-error').textContent = 'Informe CPF com 11 ou CNPJ com 14 dígitos.'; return; }
    button.disabled = true;
    try { await api('/customers',{method:'POST',body:{name:form.elements.name.value.trim().toLocaleUpperCase('pt-BR'),document}}); dialog.close(); await load(); notice('Tomador cadastrado.'); }
    catch(error) { const node=dialog.querySelector('#customer-error'); if(node) node.textContent=error.message; }
    finally { button.disabled = false; }
  };
}

function reviewDraft(draft) {
  const note = data.invoices.find(i => i.draft_id === draft.id);
  if (note) { showNote(note); return; }
  if (draft.attempt_id) { showAttempt(draft.attempt_id); return; }
  const draftEnvironment=draft.environment||'homologacao';
  const production=draftEnvironment==='producao';
  if(production&&!emissionConfig.production_available){notice('Emissão em produção bloqueada. Consulte o administrador.');return;}
  const today = new Date();
  const localDay = new Date(today.getTime() - today.getTimezoneOffset()*60000).toISOString().slice(0,10);
  // Freeze issue time before review; never subtract time from the clock.
  const issuedAt = today.toISOString().replace(/\.\d{3}Z$/,'Z');
  dialog.innerHTML = `<h2 id="dialog-title">${production?'Confirme a emissão em PRODUÇÃO':'Revise sua nota de teste'}</h2><p class="subtle">Confira as informações antes de confirmar a emissão.</p><div class="review-card"><dl class="details"><div><dt>PRESTADOR</dt><dd>${esc(company.name)}</dd></div><div><dt>VALOR</dt><dd><strong>${money(draft.amount_cents)}</strong></dd></div><div><dt>TOMADOR</dt><dd>${esc(customerName(draft.customer_id))}</dd></div><div><dt>CÓDIGO DO SERVIÇO</dt><dd>${esc(draft.settings?.service_code)}</dd></div><div><dt>FORMA DE PAGAMENTO</dt><dd>${esc(paymentLabel(draft.payment_method))}</dd></div></dl><p class="detail-text">${esc(draft.settings?.service_description)}</p></div><form id="emit-form"><label class="field">Competência<input name="competence" type="date" value="${localDay}" max="${localDay}" required></label><div class="hint">${envHint(draftEnvironment)} Em caso de resultado inconclusivo, consulte a tentativa antes de emitir outra nota.</div>${production?'<label class="check"><input name="confirm_production" type="checkbox" required> Conferi o serviço, o tomador e o valor. Confirmo a emissão de uma NFS-e real com validade fiscal.</label>':''}<p class="error" id="emit-error" role="alert"></p><div class="actions"><button class="secondary" type="button" data-close>Voltar</button><button class="primary" type="submit">${production?'Emitir nota real em produção':'Emitir em homologação'}</button></div></form>`;
  dialog.showModal();
  dialog.querySelector('[data-close]').onclick = () => dialog.close();
  dialog.querySelector('form').onsubmit = async event => {
    event.preventDefault();
    if (sending) return;
    sending = true;
    const form = event.currentTarget;
    form.querySelectorAll('button').forEach(b => b.disabled = true);
    form.querySelector('[type=submit]').textContent = 'Aguardando resultado…';
    dialog.oncancel = event => event.preventDefault();
    try {
      const attempt = await api(`/drafts/${draft.id}/${production?'emit-production':'emit-homologation'}`,{method:'POST',body:{issued_at:issuedAt,competence:form.elements.competence.value,...(production?{confirm_production:form.elements.confirm_production.checked}:{})}});
      draft.attempt_id = attempt.id;
      draft.attempt_status = attempt.status;
      attemptResult(attempt);
      await load();
    } catch(error) {
      if (!company) return;
      // No automatic resubmission. Refresh state before offering any further action.
      await load();
      dialog.innerHTML = `<h2 id="dialog-title">Não foi possível confirmar a emissão</h2><p class="detail-text">${esc(error.message)}</p><div class="hint">O rascunho foi preservado. Se houver uma tentativa, consulte o resultado. Não crie outra nota para repetir esta operação sem verificar.</div><div class="actions"><button class="secondary" data-close>Fechar e consultar rascunhos</button></div>`;
      dialog.querySelector('[data-close]').onclick = () => { dialog.close(); navigate('drafts'); };
    } finally { sending = false; dialog.oncancel = null; }
  };
}

async function showAttempt(id) {
  dialog.innerHTML = '<h2 id="dialog-title">Consultando resultado…</h2>';
  if (!dialog.open) dialog.showModal();
  try { attemptResult(await api('/emission-attempts/' + id)); }
  catch(error) {
    if(!company) return;
    dialog.innerHTML = `<h2 id="dialog-title">Não foi possível consultar</h2><p>${esc(error.message)}</p><button class="secondary" data-close>Fechar</button>`;
    dialog.querySelector('[data-close]').onclick = () => dialog.close();
  }
}

function attemptResult(attempt) {
  const successful = attempt.status === 'authorized';
  const errors = attempt.result?.errors || attempt.result?.erros || [];
  const errorDetails = errors.map(e => e.complement || e.complemento || e.Complemento || '').filter(Boolean);
  const message = successful ? (attempt.environment==='producao'?'Sua nota foi autorizada em produção e possui validade fiscal.':'Sua nota de teste foi autorizada.')+' O XML e o DANFSe estão disponíveis na lista de notas.' : 'Não há autorização confirmada nesta tentativa. Consulte as informações abaixo antes de tomar outra ação.';
  dialog.innerHTML = `<h2 id="dialog-title">${successful ? 'Nota autorizada em '+envLabel(attempt.environment).toLowerCase() : 'Resultado da tentativa'}</h2>${badge(attempt.status)}<p class="detail-text" style="margin-top:18px">${message}</p><div class="status-box ${successful ? '' : 'bad'}">${envLabel(attempt.environment)} · DPS ${esc(attempt.dps_number)} · Série ${esc(attempt.dps_series)}<br>${esc(attempt.result?.validation || attempt.result?.error || '')}${errors.map(e => `<div>${esc(e.codigo || e.code || '')} ${esc(e.descricao || e.description || '')}</div>`).join('')}</div><p class="footer-note">Identificação da tentativa: ${esc(attempt.id)}</p><div class="actions"><button class="secondary" data-close>Fechar</button>${successful ? '<button class="primary" id="see-notes">Ver notas fiscais</button>' : '<button class="secondary" id="check-attempt">Consultar novamente</button>'}</div>`;
  if (!dialog.open) dialog.showModal();
  dialog.querySelector('[data-close]').onclick = () => dialog.close();
  for (const message of errorDetails) {
    const detail = document.createElement('p');
    detail.className = 'detail-text';
    detail.textContent = message;
    dialog.querySelector('.status-box').append(detail);
  }
  if (successful) dialog.querySelector('#see-notes').onclick = async () => { dialog.close(); await load(); if (company) navigate('invoices'); };
  else dialog.querySelector('#check-attempt').onclick = () => showAttempt(attempt.id);
}

function showNote(note) {
  dialog.innerHTML = `<h2 id="dialog-title">NFS-e ${esc(note.invoice_number)}</h2>${badge(note.status)}<dl class="details"><div><dt>VALOR DO SERVIÇO</dt><dd>${money(note.amount_cents)}</dd></div><div><dt>DISPONÍVEL DESDE</dt><dd>${esc(date(note.issued_at || note.imported_at))}</dd></div><div><dt>AMBIENTE</dt><dd>${envLabel(note.environment)}</dd></div><div><dt>PRESTADOR</dt><dd>${esc(doc(note.issuer_document))}</dd></div><div class="span2"><dt>CHAVE DE ACESSO</dt><dd>${esc(note.access_key)}</dd></div></dl><div class="hint">${envHint(note.environment)}</div><div class="actions"><button class="secondary" data-close>Fechar</button><button class="secondary" data-download="${esc(note.id)}" data-format="xml">Baixar XML</button>${note.status!=='cancelled'?`<button class="primary" data-download="${esc(note.id)}" data-format="pdf">Baixar DANFSe</button>`:`<button class="secondary" data-cancel-result="${esc(note.id)}">Ver cancelamento</button>`}</div>`;
  dialog.showModal();
  dialog.querySelector('[data-close]').onclick = () => dialog.close();
  bindDocuments();
}

function bindDocuments() {
  document.querySelectorAll('[data-cancel]').forEach(button=>button.onclick=()=>cancelInvoice(data.invoices.find(n=>n.id===button.dataset.cancel)));
  document.querySelectorAll('[data-cancel-result]').forEach(button=>button.onclick=()=>showCancellation(button.dataset.cancelResult));
  document.querySelectorAll('[data-note]').forEach(button => button.onclick = () => showNote(data.invoices.find(n => n.id === button.dataset.note)));
  document.querySelectorAll('[data-download]').forEach(button => button.onclick = async () => {
    button.disabled = true;
    const original = button.innerHTML;
    button.textContent = 'Preparando…';
    try {
      const format = button.dataset.format;
      const blob = await api(`/invoices/${button.dataset.download}/${format}`, {binary:true});
      if (format === 'pdf' && (await blob.slice(0,5).text()) !== '%PDF-') throw new Error('O servidor não retornou um PDF válido.');
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = `nfse-${data.invoices.find(n=>n.id===button.dataset.download)?.environment||environment}-${button.dataset.download}.${format}`;
      document.body.append(link);
      link.click();
      link.remove();
      setTimeout(() => URL.revokeObjectURL(url), 30000);
      notice('Download solicitado. Confira a pasta de downloads do navegador.');
    } catch(error) { notice(error.message); }
    finally { button.disabled = false; button.innerHTML = original; }
  });
}

function bindCommon() {
  document.querySelectorAll('[data-go]').forEach(button => button.onclick = () => navigate(button.dataset.go));
  bindDocuments();
}

// Tokens remain in memory. Closing or refreshing this page requires a new login.
window.addEventListener('pagehide', () => { token = null; });
renderLogin();

async function showCancellation(invoiceId, attempt) {
  try {
    attempt=attempt||await api(`/invoices/${invoiceId}/cancellation`);
    const confirmed=attempt.status==='cancelled', rejected=attempt.status==='rejected';
    dialog.innerHTML=`<h2 id="dialog-title">${confirmed?'NFS-e cancelada':rejected?'Cancelamento rejeitado':'Cancelamento sem confirmação'}</h2><p>${confirmed?'A SEFIN confirmou o cancelamento.':rejected?'A nota permanece autorizada. Confira o retorno antes de solicitar novamente.':'Não reenvie o pedido. Consulte esta tentativa antes de outra operação.'}</p><div class="status-box">${(attempt.result?.errors||[]).map(e=>`<p>${esc(e.code)} ${esc(e.description)}</p>`).join('')}${esc(attempt.result?.error||'')}</div><p class="subtle">Justificativa: ${esc(attempt.reason)}</p><p class="footer-note">Tentativa: ${esc(attempt.id)}</p><div class="actions"><button class="secondary" data-close>Fechar</button>${confirmed?'<button class="primary" id="cancel-event">Baixar evento XML</button>':'<button class="secondary" id="cancel-check">Consultar novamente</button>'}</div>`;
    if(!dialog.open)dialog.showModal();dialog.querySelector('[data-close]').onclick=()=>dialog.close();
    const check=dialog.querySelector('#cancel-check');if(check)check.onclick=()=>showCancellation(invoiceId);
    const download=dialog.querySelector('#cancel-event');if(download)download.onclick=async()=>{
      try{const blob=await api(`/invoices/${invoiceId}/cancellation/xml`,{binary:true});const url=URL.createObjectURL(blob);const a=document.createElement('a');a.href=url;a.download=`cancelamento-${invoiceId}.xml`;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}catch(error){notice(error.message);}
    };
  }catch(error){notice(error.message);}
}
function cancelInvoice(note) {
  dialog.innerHTML=`<h2 id="dialog-title">Cancelar NFS-e ${esc(note.invoice_number)}</h2><div class="hint">${envHint(note.environment)} O pedido será enviado à SEFIN. A aceitação depende das regras de cancelamento aplicáveis à nota.</div><p>${esc(note.customer_name||'Tomador não informado')} · ${money(note.amount_cents)}</p><form><label class="field">Motivo<select name="reason_code" required><option value="">Selecione…</option><option value="1">Erro na emissão</option><option value="2">Serviço não prestado</option><option value="9">Outros</option></select></label><label class="field">Justificativa<textarea name="reason" minlength="15" maxlength="255" required></textarea></label><label class="check"><input name="confirmed" type="checkbox" required> Confirmo o pedido de cancelamento desta NFS-e.</label><p class="error" role="alert"></p><div class="actions"><button class="secondary" type="button" data-close>Voltar</button><button class="primary" type="submit">Confirmar cancelamento</button></div></form>`;
  dialog.showModal();const form=dialog.querySelector('form');form.querySelector('[data-close]').onclick=()=>dialog.close();
  form.onsubmit=async event=>{
    event.preventDefault();const button=form.querySelector('[type=submit]');button.disabled=true;dialog.oncancel=e=>e.preventDefault();form.querySelector('[data-close]').disabled=true;
    try {
      const result=await api(`/invoices/${note.id}/cancel`,{method:'POST',body:{reason_code:form.elements.reason_code.value,reason:form.elements.reason.value.trim(),confirm_cancellation:form.elements.confirmed.checked}});
      await load();await showCancellation(note.id,result);
    }catch(error){if(dialog.open){form.querySelector('.error').textContent=error.message+' Se o envio ficou sem resposta, consulte o cancelamento antes de reenviar.';const check=document.createElement('button');check.type='button';check.className='secondary';check.textContent='Consultar cancelamento';check.onclick=()=>showCancellation(note.id);form.querySelector('.actions').append(check);}}
    finally{dialog.oncancel=null;if(button.isConnected){button.disabled=false;form.querySelector('[data-close]').disabled=false;}}
  };
}
