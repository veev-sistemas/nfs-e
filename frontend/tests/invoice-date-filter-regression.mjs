import assert from 'node:assert/strict';
import {invoiceDateQuery} from '../dist/invoice-date-filter.js';
assert.deepEqual(invoiceDateQuery({dateType:'emission',from:'2026-10-01',to:'2026-10-21'}),{date_from:'2026-10-01',date_to:'2026-10-21'});
assert.deepEqual(invoiceDateQuery({dateType:'competence',from:'2026-09-01',to:'2026-09-30'}),{competence_from:'2026-09-01',competence_to:'2026-09-30'});
assert.deepEqual(invoiceDateQuery({dateType:'competence'}),{competence_from:'',competence_to:''});
assert.deepEqual(invoiceDateQuery({}),{date_from:'',date_to:''});
console.log('OK: somente o período selecionado é enviado, inclusive sem limites.');
