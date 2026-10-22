// Internal report only: values are fetched with the same filters as the invoice query.
export function totalsReport({company, environment, filters, summary, generatedAt}, {esc, money, date, envLabel, paymentMethods}) {
  const day = value => value ? value.split('-').reverse().join('/') : 'Sem limite';
  const statuses = {authorized:'Autorizadas', cancelled:'Canceladas', imported:'Importadas'};
  const rows = [...paymentMethods, ['nao_informado','Não informado']].map(([method,label]) => {
    const item = summary.by_payment.find(p => p.payment_method === method) || {count:0,total_cents:0};
    return `<tr><th scope="row">${esc(label)}</th><td>${esc(money(item.total_cents))}</td></tr>`;
  }).join('');
  return `<article class="invoice-report">
    <header><div class="report-brand">VEEV · NFS-e</div><h2>Resumo por forma de pagamento</h2><strong>${esc(company.name)}</strong><p>CNPJ: ${esc(company.document.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, '$1.$2.$3/$4-$5'))}</p></header>
    <dl class="report-filters"><div><dt>Ambiente</dt><dd>${esc(envLabel(environment))}</dd></div><div><dt>Emissão de</dt><dd>${esc(day(filters.from))}</dd></div><div><dt>Até</dt><dd>${esc(day(filters.to))}</dd></div><div><dt>Situação</dt><dd>${esc(statuses[filters.status] || 'Todas')}</dd></div>${filters.search ? `<div><dt>Busca</dt><dd>${esc(filters.search)}</dd></div>` : ''}<div><dt>Gerado em</dt><dd>${esc(date(generatedAt))} (Brasília)</dd></div></dl>
    <section class="report-grand-total"><div><span>Total geral (sem canceladas)</span><strong>${esc(money(summary.total_cents))}</strong></div></section>
    <h3>Formas de pagamento</h3><table><thead><tr><th>Pagamento</th><th>Total</th></tr></thead><tbody>${rows}</tbody></table>
    <footer><p>Canceladas excluídas dos totais. A forma de pagamento informada no lançamento não comprova recebimento.</p><p>Relatório interno de conferência. Não substitui o DANFSe.</p></footer>
  </article>`;
}

let releasePrint = null;
export async function printTotalsReport(reportHTML, format) {
  if (!['a4','80mm'].includes(format)) throw new Error('Formato de impressão inválido.');
  if (releasePrint) releasePrint();
  const report = document.createElement('section');
  report.id = 'invoice-print-report';
  report.className = format === '80mm' ? 'report-receipt' : 'report-a4';
  report.innerHTML = reportHTML;
  document.body.append(report);
  const pageStyle = document.createElement('style');
  const cleanup = () => {
    report.remove(); pageStyle.remove();
    window.removeEventListener('afterprint', cleanup);
    if (releasePrint === cleanup) releasePrint = null;
  };
  releasePrint = cleanup;
  try {
    if (document.fonts?.ready) await document.fonts.ready;
    // A roll has variable length. Measure the 74 mm printable area before opening print.
    const heightMM = Math.ceil(report.getBoundingClientRect().height * 25.4 / 96) + 10;
    pageStyle.textContent = format === '80mm'
      ? `@page { size: 80mm ${Math.max(80,heightMM)}mm; margin: 3mm; }`
      : '@page { size: A4 portrait; margin: 12mm; }';
    document.head.append(pageStyle);
    window.addEventListener('afterprint', cleanup, {once:true});
    window.print();
  } catch (error) { cleanup(); throw error; }
}
