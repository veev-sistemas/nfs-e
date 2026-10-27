import assert from 'node:assert/strict';
import {invoiceDateQuery, competenceDate, validateCompetenceResult} from '../dist/invoice-date-filter.js';
assert.deepEqual(invoiceDateQuery({dateType:'emission',from:'2026-10-01',to:'2026-10-21'}),{date_from:'2026-10-01',date_to:'2026-10-21'});
assert.deepEqual(invoiceDateQuery({dateType:'competence',from:'2026-09-01',to:'2026-09-30'}),{competence_from:'2026-09-01',competence_to:'2026-09-30'});
assert.deepEqual(invoiceDateQuery({dateType:'competence'}),{competence_from:'',competence_to:''});
assert.deepEqual(invoiceDateQuery({}),{date_from:'',date_to:''});
console.log('OK: somente o período selecionado é enviado, inclusive sem limites.');

const filters={dateType:'competence',from:'2026-10-21',to:'2026-10-21'};
assert.equal(competenceDate('2026-10-21'),'21/10/2026');
assert.equal(competenceDate(null),'—');
validateCompetenceResult({invoices:[{competence:'2026-10-21'}]},filters);
validateCompetenceResult({invoices:[]},filters);
for (const note of [{},{competence:null},{competence:'2026-10-20'},{competence:'2026-10-22'}]) {
  assert.throws(()=>validateCompetenceResult({invoices:[note]},filters),/nfse-api/);
}
validateCompetenceResult([{competence:null}],{dateType:'emission',from:filters.from});
console.log('OK: competência sem deslocamento de fuso; API antiga ou resultado fora do período é recusado.');
