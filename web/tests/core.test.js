// Run: node web/tests/core.test.js  — same cases as the iOS ParserTests/RecurrenceTests.
const assert = require('assert');
const { parse, Recurrence } = require('../core.js');
const NOW = new Date(2026, 10, 21, 8, 0); // Sat 21 Nov 2026 08:00
const P = s => parse(s, NOW, [15]);
const ymdhm = d => [d.getFullYear(), d.getMonth() + 1, d.getDate(), d.getHours(), d.getMinutes()];
const ymd = d => ymdhm(d).slice(0, 3);
let pass = 0, fail = 0;
function t(name, fn) { try { fn(); pass++; } catch (e) { fail++; console.log('FAIL', name, '-', e.message); } }

t('bills', () => { const r = P('ذكرني بمراجعة الفواتير بكرة الساعة 10 صباحاً'); assert.equal(r.title, 'مراجعة الفواتير'); assert.deepEqual(ymdhm(r.date), [2026,11,22,10,0]); assert.deepEqual(r.reminderOffsets, [0]); assert.ok(!r.needsClarification, r.issues.join()); });
t('sunday', () => { const r = P('أضف مهمة شراء مستلزمات المكتب يوم الأحد'); assert.equal(r.title, 'شراء مستلزمات المكتب'); assert.deepEqual(ymd(r.date), [2026,11,22]); assert.ok(!r.timeDetected); assert.ok(r.needsClarification); assert.deepEqual(r.reminderOffsets, [15]); });
t('meeting', () => { const r = P('عندي اجتماع غداً الساعة 3 عصراً'); assert.equal(r.title, 'اجتماع'); assert.deepEqual(ymdhm(r.date), [2026,11,22,15,0]); assert.ok(!r.needsClarification, r.issues.join()); });
t('rent', () => { const r = P('ذكرني بدفع الإيجار يوم 1 من الشهر'); assert.equal(r.title, 'دفع الإيجار'); assert.deepEqual(ymd(r.date), [2026,12,1]); assert.ok(r.needsClarification); assert.ok(r.hints.length); });
t('indic', () => { const r = P('اجتماع العملاء بكرة الساعة ١٠:٣٠ صباحا'); assert.equal(r.title, 'اجتماع العملاء'); assert.deepEqual(ymdhm(r.date), [2026,11,22,10,30]); });
t('half', () => { const r = P('مكالمة المورد بكرة الساعة 3 ونص العصر'); assert.deepEqual(ymdhm(r.date), [2026,11,22,15,30]); assert.equal(r.title, 'مكالمة المورد'); });
t('quarterTo', () => { const r = P('العشاء بكرة الساعة 9 الا ربع مساء'); assert.deepEqual(ymdhm(r.date), [2026,11,22,20,45]); });
t('lunch', () => { const r = P('موعد الغداء الساعة 1 الظهر'); assert.equal(r.title, 'موعد الغداء'); assert.deepEqual(ymdhm(r.date), [2026,11,21,13,0]); });
t('relHour', () => { const r = P('اتصل بالعميل بعد ساعة'); assert.equal(r.title, 'اتصل بالعميل'); assert.equal(r.date.getTime(), NOW.getTime() + 3600000); assert.ok(!r.needsClarification); });
t('daily', () => { const r = P('تمرين كل يوم الساعة 6 صباحا'); assert.equal(r.recurrence, 'daily'); assert.equal(r.title, 'تمرين'); assert.deepEqual(ymdhm(r.date), [2026,11,22,6,0]); });
t('weekly', () => { const r = P('اجتماع الفريق كل اثنين الساعة 9 صباحا'); assert.equal(r.recurrence, 'weekly'); assert.deepEqual(ymdhm(r.date), [2026,11,23,9,0]); });
t('ambiguous', () => { const r = P('اجتماع الساعة 4'); assert.deepEqual(ymdhm(r.date), [2026,11,21,16,0]); assert.ok(r.needsClarification); });
t('noDate', () => { const r = P('شراء هدية'); assert.equal(r.title, 'شراء هدية'); assert.ok(!r.dateDetected); assert.ok(r.needsClarification); });
t('offsetPhrase', () => { const r = P('ذكرني قبلها بساعة باجتماع المجلس يوم الخميس الساعة 11 صباحا'); assert.equal(r.title, 'اجتماع المجلس'); assert.deepEqual(r.reminderOffsets, [60]); assert.deepEqual(ymdhm(r.date), [2026,11,26,11,0]); });
t('numericDate', () => { const r = P('ادفع فاتورة الكهرباء 15/12'); assert.equal(r.title, 'ادفع فاتورة الكهرباء'); assert.deepEqual(ymd(r.date), [2026,12,15]); assert.ok(r.needsClarification); });
t('monthly31', () => { const r = P('دفع القسط يوم 31 من كل شهر الساعة 9 صباحا'); assert.equal(r.recurrence, 'monthly'); assert.equal(r.title, 'دفع القسط'); assert.deepEqual(ymdhm(r.date), [2026,12,31,9,0]); assert.ok(r.hints.length); });
t('egyptToday', () => { const r = P('مراجعة التقرير النهارده الساعة 5 مساء'); assert.equal(r.title, 'مراجعة التقرير'); assert.deepEqual(ymdhm(r.date), [2026,11,21,17,0]); });
t('afterTomorrow', () => { const r = P('زيارة الوالدة بعد بكرة الساعة 7 مساء'); assert.equal(r.title, 'زيارة الوالدة'); assert.deepEqual(ymdhm(r.date), [2026,11,23,19,0]); });
t('pastToday', () => { const r = P('اجتماع اليوم الساعة 7 صباحا'); assert.ok(r.needsClarification); });

t('rec daily/weekly', () => { const s = new Date(2026,10,21,9,30); assert.deepEqual(ymdhm(Recurrence.next(s,'daily',0)), [2026,11,22,9,30]); assert.deepEqual(ymdhm(Recurrence.next(s,'weekly',0)), [2026,11,28,9,30]); });
t('rec 31', () => { const f = Recurrence.next(new Date(2027,0,31,10,0),'monthly',31); assert.deepEqual(ymdhm(f),[2027,2,28,10,0]); const m = Recurrence.next(f,'monthly',31); assert.deepEqual(ymdhm(m),[2027,3,31,10,0]); assert.deepEqual(ymdhm(Recurrence.next(m,'monthly',31)),[2027,4,30,10,0]); });
t('rec leap', () => assert.deepEqual(ymdhm(Recurrence.next(new Date(2028,0,31,8,0),'monthly',31)),[2028,2,29,8,0]));
t('rec dec', () => assert.deepEqual(ymdhm(Recurrence.next(new Date(2026,11,15,8,0),'monthly',15)),[2027,1,15,8,0]));
t('rec skip', () => assert.deepEqual(ymdhm(Recurrence.nextOccurrence(new Date(2026,10,18,7,0), NOW,'daily',0)),[2026,11,22,7,0]));
t('rec occurs', () => { const s = new Date(2027,0,31,9,0); assert.ok(Recurrence.occursOn(new Date(2027,1,28),s,'monthly',31)); assert.ok(!Recurrence.occursOn(new Date(2027,1,27),s,'monthly',31)); assert.ok(!Recurrence.occursOn(new Date(2027,0,30),s,'daily',0)); assert.ok(Recurrence.occursOn(new Date(2027,1,7),s,'weekly',0)); });

console.log(`${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
