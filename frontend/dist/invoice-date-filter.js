// Send only the selected date range; list and print use the same query.
export function invoiceDateQuery({dateType, from='', to=''}) {
  return dateType === 'competence'
    ? {competence_from:from, competence_to:to}
    : {date_from:from, date_to:to};
}

export function competenceDate(value) {
  if (!value || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return '—';
  return value.split('-').reverse().join('/');
}
// Never show an unfiltered result as if the server had applied competence dates.
export function validateCompetenceResult(result, filters) {
  if (filters.dateType !== 'competence' || (!filters.from && !filters.to)) return;
  const invoices = Array.isArray(result) ? result : result.invoices;
  if (invoices.some(note => !note.competence ||
      (filters.from && note.competence < filters.from) ||
      (filters.to && note.competence > filters.to))) {
    throw new Error('A API não aplicou o filtro de competência. Atualize o serviço nfse-api com o pacote de filtros de datas e tente novamente.');
  }
}
