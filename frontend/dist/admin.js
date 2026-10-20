const root = document.querySelector('#admin-app');
const dialog = document.querySelector('#admin-dialog');
let session = null, username = '', companies = [], search = '', noticeTimer;
const esc = value => String(value ?? '').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const cnpj = value => value.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/,'$1.$2.$3/$4-$5');

function notice(message) {
  const node = document.querySelector('#notice'); node.textContent = message; node.classList.add('show');
  clearTimeout(noticeTimer); noticeTimer = setTimeout(()=>node.classList.remove('show'),7000);
}

async function api(path,{method='GET',body}={}) {
  const controller = new AbortController();
  const timeout = setTimeout(()=>controller.abort(),30000);
  try {
    const response = await fetch('/v1/admin'+path,{method,signal:controller.signal,cache:'no-store',credentials:'omit',
      headers:{'Content-Type':'application/json; charset=utf-8',...(session?{Authorization:'Bearer '+session}:{})},
      body:body===undefined?undefined:JSON.stringify(body)});
    let result; try { result = await response.json(); } catch { throw new Error('O serviço administrativo não respondeu. Tente novamente.'); }
    if (!response.ok) {
      if (response.status===401 && path!=='/auth/login') { session=null; companies=[]; if(dialog.open) dialog.close(); login(); }
      throw new Error(result.error || 'Não foi possível concluir a operação.');
    }
    return result;
  } catch(error) {
    if(error.name==='AbortError') throw new Error('A operação ficou sem confirmação. Atualize a lista antes de repetir um cadastro.');
    throw error;
  } finally { clearTimeout(timeout); }
}

function login() {
  root.innerHTML = `<section class="panel admin-login"><div class="eyebrow">VEEV · ADMINISTRAÇÃO</div><h1>Acesso administrativo</h1><p class="subtle">Cadastre empresas e gerencie os acessos.</p><form id="admin-login"><label class="field">Usuário<input name="username" required autocomplete="username" maxlength="100"></label><label class="field">Senha<input name="password" type="password" required autocomplete="current-password" minlength="12" maxlength="72"></label><p class="error" id="login-error" role="alert"></p><button class="primary full" type="submit">Entrar como administrador</button></form><p class="admin-info"><a class="inline-link" href="/">Voltar ao acesso da empresa</a></p></section>`;
  document.querySelector('#admin-login').onsubmit = async event => {
    event.preventDefault(); const form = event.currentTarget, button = form.querySelector('button');
    button.disabled = true; document.querySelector('#login-error').textContent = '';
    try {
      const result = await api('/auth/login',{method:'POST',body:{username:form.elements.username.value.trim(),password:form.elements.password.value}});
      form.elements.password.value=''; session=result.access_token; username=result.username;
      await dashboard();
    } catch(error) {
      const node=document.querySelector('#login-error'); if(node) node.textContent=error.message; else notice(error.message);
    } finally { if(button.isConnected) button.disabled=false; }
  };
}

async function dashboard() {
  root.innerHTML = `<div class="admin-content"><header class="admin-top"><div><div class="eyebrow">VEEV · ADMINISTRAÇÃO</div><h1>Empresas cadastradas</h1><p class="subtle">Conectado como ${esc(username)}</p></div><div class="actions"><button class="secondary" id="admin-refresh">Atualizar</button><button class="primary" id="company-new">Cadastrar empresa</button><button class="text-button" id="admin-logout">Sair</button></div></header><section class="panel"><div class="panel-header"><div><h2>Contas e acessos</h2><p>Até 1.000 empresas. O bloqueio encerra as sessões da empresa.</p></div></div><div class="table-tools"><input id="company-search" class="search admin-search" type="search" placeholder="Buscar por razão social ou CNPJ" aria-label="Buscar empresa" value="${esc(search)}"></div><div id="company-list" class="loading">Carregando empresas…</div></section><p class="subtle">O cadastro cria o acesso por CNPJ e senha. Para emitir, configure o perfil fiscal, os padrões do serviço e o certificado da empresa. As emissões continuam em homologação.</p></div>`;
  document.querySelector('#company-new').onclick=companyForm;
  document.querySelector('#admin-refresh').onclick=refresh;
  document.querySelector('#company-search').oninput=event=>{search=event.target.value; renderCompanies();};
  document.querySelector('#admin-logout').onclick=async()=>{
    try { await api('/auth/logout',{method:'POST'}); } catch(error) { notice(error.message); }
    finally { session=null; companies=[]; search=''; login(); }
  };
  await refresh();
}

async function refresh() {
  const previousSession=session;
  try { const list=await api('/companies'); if(!session||session!==previousSession)return; companies=list; renderCompanies(); }
  catch(error) {
    const list=document.querySelector('#company-list');
    if(list) { list.className='panel-body'; list.textContent=error.message; }
    else notice(error.message);
  }
}

function renderCompanies() {
  const node=document.querySelector('#company-list'); if(!node)return;
  const term=search.toLocaleUpperCase('pt-BR'), digits=search.replace(/\D/g,'');
  const list=companies.filter(c=>c.name.toLocaleUpperCase('pt-BR').includes(term)||c.document.includes(search)||(digits && c.document.includes(digits)));
  node.className='';
  node.innerHTML=list.length ? `<div class="table-wrap"><table><thead><tr><th>Empresa / CNPJ</th><th>Acesso</th><th>Cadastro fiscal</th><th>Ações</th></tr></thead><tbody>${list.map(c=>`<tr><td><strong>${esc(c.name)}</strong><div class="minor">${esc(cnpj(c.document))}</div></td><td><span class="badge ${c.access_enabled?'':'bad'}">${c.access_enabled?'Liberado':'Bloqueado'}</span></td><td>${c.has_fiscal_profile?'Perfil cadastrado':'Perfil pendente'}${c.has_password?'':' · Senha pendente'}</td><td><div class="actions"><button class="${c.access_enabled?'danger':'secondary'}" data-access="${esc(c.id)}">${c.access_enabled?'Bloquear':'Liberar'}</button><button class="text-button" data-password="${esc(c.id)}">Redefinir senha</button></div></td></tr>`).join('')}</tbody></table></div>` : '<div class="empty">Nenhuma empresa encontrada.</div>';
  node.querySelectorAll('[data-access]').forEach(b=>b.onclick=()=>accessForm(companies.find(c=>c.id===b.dataset.access)));
  node.querySelectorAll('[data-password]').forEach(b=>b.onclick=()=>passwordForm(companies.find(c=>c.id===b.dataset.password)));
}

function passwordField() {
  return `<label class="field">Senha de acesso da empresa<input name="password" type="password" required minlength="12" maxlength="72" autocomplete="new-password"></label><div class="actions"><button type="button" class="secondary" id="password-generate">Gerar senha</button><button type="button" class="text-button" id="password-show">Mostrar senha</button></div><p class="subtle">Guarde a senha antes de confirmar. Ela não poderá ser consultada depois.</p>`;
}

function bindPassword(form) {
  const input=form.elements.password;
  form.querySelector('#password-show').onclick=event=>{ input.type=input.type==='password'?'text':'password'; event.currentTarget.textContent=input.type==='password'?'Mostrar senha':'Ocultar senha'; };
  form.querySelector('#password-generate').onclick=()=>{
    const alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
    input.value=Array.from(crypto.getRandomValues(new Uint8Array(24)),n=>alphabet[n%64]).join('');
    input.type='text'; form.querySelector('#password-show').textContent='Ocultar senha';
  };
  form.querySelector('[data-close]').onclick=()=>{input.value='';dialog.close();};
}

function companyForm() {
  const field=(name,label,extra='')=>`<label class="field">${label}<input name="${name}" ${extra} maxlength="255"></label>`;
  dialog.innerHTML=`<h2 id="admin-dialog-title">Cadastrar empresa</h2><form id="company-form"><label class="field">Razão social<input name="name" required maxlength="500"></label><label class="field">CNPJ<input name="cnpj" required inputmode="numeric" maxlength="18" autocomplete="off"></label>${passwordField()}<label class="check"><input name="with_profile" type="checkbox"> Cadastrar também o endereço e o perfil fiscal</label><div class="form-grid" id="fiscal-profile" hidden>${field('municipality_code','Código IBGE do município','pattern="[0-9]{7}" inputmode="numeric"')}${field('municipality_name','Município')}${field('state_code','UF','pattern="[A-Z]{2}" class="uppercase"')}${field('postal_code','CEP','pattern="[0-9]{8}" inputmode="numeric"')}${field('street','Logradouro')}${field('house_number','Número')}${field('district','Bairro')}${field('municipal_registration','Inscrição municipal (opcional)')}${field('homologation_series','Série em homologação','value="901" pattern="[0-9]{1,5}" inputmode="numeric"')}</div><p class="error" role="alert" id="company-error"></p><div class="actions"><button type="button" class="secondary" data-close>Cancelar</button><button type="submit" class="primary">Cadastrar empresa</button></div></form>`;
  dialog.showModal(); const form=dialog.querySelector('form'); bindPassword(form);
  const profile=form.querySelector('#fiscal-profile');
  form.elements.with_profile.onchange=()=>{
    profile.hidden=!form.elements.with_profile.checked;
    profile.querySelectorAll('input').forEach(input=>{input.required=form.elements.with_profile.checked && input.name!=='municipal_registration';});
  };
  form.elements.state_code.oninput=()=>{form.elements.state_code.value=form.elements.state_code.value.toUpperCase();};
  form.onsubmit=async event=>{
    event.preventDefault();const button=form.querySelector('[type=submit]');button.disabled=true;
    try {
      const body={name:form.elements.name.value.trim(),cnpj:form.elements.cnpj.value.replace(/\D/g,''),password:form.elements.password.value};
      if(body.cnpj.length!==14)throw new Error('Informe um CNPJ com 14 dígitos.');
      if(new TextEncoder().encode(body.password).length>72)throw new Error('A senha deve ter no máximo 72 bytes.');
      if(form.elements.with_profile.checked){
        body.fiscal_profile={};
        profile.querySelectorAll('input').forEach(input=>{if(input.value.trim())body.fiscal_profile[input.name]=input.value.trim();});
      }
      await api('/companies',{method:'POST',body}); form.elements.password.value='';dialog.close();notice('Empresa cadastrada. O acesso por CNPJ e senha está liberado.');await refresh();
    }catch(error){const node=form.querySelector('#company-error');if(node)node.textContent=error.message;}
    finally{if(button.isConnected)button.disabled=false;}
  };
}

function accessForm(company) {
  const enable=!company.access_enabled;
  dialog.innerHTML=`<h2 id="admin-dialog-title">${enable?'Liberar':'Bloquear'} acesso</h2><p>${esc(company.name)}<br>${esc(cnpj(company.document))}</p><p class="subtle">${enable?'A empresa poderá entrar novamente usando a senha cadastrada.':'As sessões serão encerradas e o uso pelo CNPJ e pelas chaves de API será bloqueado.'}</p><p class="error" role="alert" id="action-error"></p><div class="actions"><button class="secondary" data-close>Cancelar</button><button class="${enable?'primary':'danger'}" id="access-confirm">${enable?'Liberar acesso':'Bloquear acesso'}</button></div>`;
  dialog.showModal();dialog.querySelector('[data-close]').onclick=()=>dialog.close();
  dialog.querySelector('#access-confirm').onclick=async event=>{
    const button=event.currentTarget;button.disabled=true;
    try{await api('/companies/'+company.id+'/access',{method:'PATCH',body:{enabled:enable}});dialog.close();await refresh();notice(enable?'Acesso liberado.':'Acesso bloqueado.');}
    catch(error){const node=dialog.querySelector('#action-error');if(node)node.textContent=error.message;}
    finally{if(button.isConnected)button.disabled=false;}
  };
}

function passwordForm(company) {
  dialog.innerHTML=`<h2 id="admin-dialog-title">Redefinir senha</h2><p>${esc(company.name)}<br>${esc(cnpj(company.document))}</p><form>${passwordField()}<p class="subtle">As sessões atuais serão encerradas após a alteração.</p><p class="error" role="alert" id="password-error"></p><div class="actions"><button type="button" class="secondary" data-close>Cancelar</button><button type="submit" class="primary">Salvar nova senha</button></div></form>`;
  dialog.showModal();const form=dialog.querySelector('form');bindPassword(form);
  form.onsubmit=async event=>{
    event.preventDefault();const button=form.querySelector('[type=submit]');button.disabled=true;
    try{await api('/companies/'+company.id+'/password',{method:'POST',body:{password:form.elements.password.value}});form.elements.password.value='';dialog.close();await refresh();notice('Senha redefinida e sessões anteriores encerradas.');}
    catch(error){const node=form.querySelector('#password-error');if(node)node.textContent=error.message;}
    finally{if(button.isConnected)button.disabled=false;}
  };
}

dialog.addEventListener('close',()=>{dialog.querySelectorAll('input[name=password]').forEach(input=>input.value='');});
login();
