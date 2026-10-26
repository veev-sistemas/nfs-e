// Send only the selected date range; list and print use the same query.
export function invoiceDateQuery({dateType, from='', to=''}) {
  return dateType === 'competence'
    ? {competence_from:from, competence_to:to}
    : {date_from:from, date_to:to};
}
