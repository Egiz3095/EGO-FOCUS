/* EGO FOCUS — web app (PWA). All data stays in this browser's local storage on the device. */
(function () {
  'use strict';
  const { D, Recurrence, parse, reminderLabel, ALLOWED_OFFSETS } = window.EGOCore;

  // ---------- Constants ----------
  const PRIORITIES = [['low', 'منخفضة'], ['normal', 'عادية'], ['high', 'مرتفعة'], ['urgent', 'عاجلة']];
  const PRANK = { low: 0, normal: 1, high: 2, urgent: 3 };
  const CATEGORIES = [['work', 'العمل', 'briefcase'], ['finance', 'المالية', 'cash'], ['personal', 'شخصي', 'user'],
    ['learning', 'التعلم', 'book'], ['health', 'الصحة', 'heart'], ['other', 'أخرى', 'grid']];
  const RECURRENCES = [['none', 'بدون تكرار'], ['daily', 'يومياً'], ['weekly', 'أسبوعياً'], ['monthly', 'شهرياً']];
  const label = (list, key) => (list.find(x => x[0] === key) || list[0])[1];
  const KEY = 'egofocus.data.v1';
  const EXAMPLES = ['ذكرني بمراجعة الفواتير بكرة الساعة 10 صباحاً', 'أضف مهمة شراء مستلزمات المكتب يوم الأحد',
    'عندي اجتماع غداً الساعة 3 عصراً', 'ذكرني بدفع الإيجار يوم 1 من الشهر'];

  // ---------- Icons ----------
  const P = {
    home: '<path d="M3 11l9-8 9 8v9a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"/>',
    calendar: '<rect x="3" y="4" width="18" height="17" rx="3"/><path d="M3 9h18M8 2v4M16 2v4"/>',
    chart: '<path d="M5 20V10M12 20V4M19 20v-7"/>',
    gear: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>',
    plus: '<path d="M12 5v14M5 12h14"/>', plusc: '<circle cx="12" cy="12" r="10"/><path d="M12 8v8M8 12h8"/>',
    mic: '<rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v4"/>',
    stop: '<rect x="6" y="6" width="12" height="12" rx="2"/>',
    check: '<path d="M5 12l5 5L20 7"/>', clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    alert: '<circle cx="12" cy="12" r="9"/><path d="M12 7v6M12 16.5v.5"/>', bell: '<path d="M6 8a6 6 0 1 1 12 0c0 7 3 9 3 9H3s3-2 3-9M10.3 21a1.9 1.9 0 0 0 3.4 0"/>',
    repeat: '<path d="M17 2l4 4-4 4"/><path d="M3 11V9a3 3 0 0 1 3-3h15M7 22l-4-4 4-4"/><path d="M21 13v2a3 3 0 0 1-3 3H3"/>',
    list: '<path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/>', trash: '<path d="M3 6h18M8 6V4h8v2M6 6l1 15h10l1-15"/>',
    prev: '<path d="M9 6l6 6-6 6"/>', next: '<path d="M15 6l-6 6 6 6"/>', sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
    briefcase: '<rect x="3" y="7" width="18" height="13" rx="2"/><path d="M9 7V5h6v2"/>', cash: '<rect x="2" y="6" width="20" height="12" rx="2"/><circle cx="12" cy="12" r="2.5"/>',
    user: '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>', book: '<path d="M4 4h6a3 3 0 0 1 3 3v13a2 2 0 0 0-2-2H4zM20 4h-6a3 3 0 0 0-1 .2"/><path d="M20 4v14h-7"/>',
    heart: '<path d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1-1.1a5.5 5.5 0 0 0-7.8 7.8L12 21l8.8-8.6a5.5 5.5 0 0 0 0-7.8z"/>', grid: '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>',
    hour: '<path d="M6 2h12M6 22h12M7 2c0 6 10 6 10 10S7 16 7 22M17 2c0 6-10 6-10 10s10 4 10 10"/>', lock: '<rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>',
    share: '<path d="M12 3v13M7 8l5-5 5 5"/><path d="M5 13v6a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-6"/>', msg: '<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>',
    bulb: '<path d="M9 18h6M10 22h4M12 2a7 7 0 0 0-4 12.7V17h8v-2.3A7 7 0 0 0 12 2z"/>', drive: '<rect x="3" y="4" width="18" height="16" rx="3"/><path d="M7 15h.01M11 15h6"/>'
  };
  const icon = (n) => '<svg class="i" viewBox="0 0 24 24" aria-hidden="true">' + (P[n] || '') + '</svg>';
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  // ---------- Formatting ----------
  const LOC = 'ar-u-nu-latn-ca-gregory';
  const fmt = (opts) => new Intl.DateTimeFormat(LOC, opts);
  const F = {
    time: d => fmt({ hour: 'numeric', minute: '2-digit' }).format(d),
    dayMonth: d => fmt({ weekday: 'long', day: 'numeric', month: 'long' }).format(d),
    fullDate: d => fmt({ weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }).format(d),
    short: d => fmt({ day: 'numeric', month: 'short' }).format(d),
    monthYear: d => fmt({ month: 'long', year: 'numeric' }).format(d),
    wdShort: d => fmt({ weekday: 'short' }).format(d),
    dateTime: d => fmt({ weekday: 'short', day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' }).format(d),
    full: d => fmt({ weekday: 'long', day: 'numeric', month: 'long', year: 'numeric', hour: 'numeric', minute: '2-digit' }).format(d),
    pct: v => Math.round(v * 100) + '٪'
  };
  const toLocalInput = d => { const p = n => String(n).padStart(2, '0'); return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`; };
  const fromLocalInput = s => { const d = new Date(s); return isNaN(d) ? null : d; };

  // ---------- Store ----------
  const defaults = { tasks: [], events: [], fired: [], settings: { appearance: 'system', remindersEnabled: true, defaultReminder: 0, briefEnabled: false, briefTime: '08:00', lastBrief: '',
    deviceId: '', pushEnabled: false, pushShowTitles: true } };
  let db;
  function load() {
    try { db = JSON.parse(localStorage.getItem(KEY)) || null; } catch (e) { db = null; }
    if (!db) db = JSON.parse(JSON.stringify(defaults));
    db.settings = Object.assign({}, defaults.settings, db.settings || {});
    db.fired = db.fired || [];
  }
  function save() {
    try { localStorage.setItem(KEY, JSON.stringify(db)); }
    catch (e) { toast('تعذر الحفظ على الجهاز — المساحة ممتلئة؟'); }
  }
  const uid = () => (crypto.randomUUID ? crypto.randomUUID() : Date.now().toString(36) + Math.random().toString(36).slice(2));
  const due = t => new Date(t.due);
  const now = () => new Date();
  const cleanMinute = d => { const x = new Date(d); x.setSeconds(0, 0); return x; };

  const S = {
    pending() { return db.tasks.filter(t => !t.completed).sort((a, b) => (due(a) - due(b)) || (PRANK[b.priority] - PRANK[a.priority])); },
    overdue() { const n = now(); return S.pending().filter(t => due(t) < n); },
    todayOpen() { const n = now(); return S.pending().filter(t => due(t) >= n && D.sameDay(due(t), n)); },
    upcoming() { const end = D.addDays(D.startOfDay(now()), 1); return S.pending().filter(t => due(t) >= end); },
    completed() { return db.tasks.filter(t => t.completed).sort((a, b) => new Date(b.completedAt || b.updatedAt) - new Date(a.completedAt || a.updatedAt)); },
    get(id) { return db.tasks.find(t => t.id === id); },
    add(draft) {
      const title = (draft.title || '').trim(); if (!title) return null;
      const d = cleanMinute(draft.due), ts = now().toISOString();
      const t = { id: uid(), title, details: (draft.details || '').trim(), notes: (draft.notes || '').trim(), due: d.toISOString(),
        priority: draft.priority || 'normal', category: draft.category || 'personal', recurrence: draft.recurrence || 'none',
        anchorDay: draft.recurrence === 'monthly' ? d.getDate() : 0, offsets: [...new Set(draft.offsets || [])].sort((a, b) => a - b),
        completed: false, completedAt: null, createdAt: ts, updatedAt: ts };
      db.tasks.push(t); persist(); return t;
    },
    update(t, draft) {
      const title = (draft.title || '').trim(); if (!title) return;
      const d = cleanMinute(draft.due); const changed = d.getTime() !== due(t).getTime() || draft.recurrence !== t.recurrence;
      Object.assign(t, { title, details: (draft.details || '').trim(), notes: (draft.notes || '').trim(), due: d.toISOString(),
        priority: draft.priority, category: draft.category, recurrence: draft.recurrence, offsets: [...new Set(draft.offsets)].sort((a, b) => a - b), updatedAt: now().toISOString() });
      if (draft.recurrence !== 'monthly') t.anchorDay = 0; else if (changed || !t.anchorDay) t.anchorDay = d.getDate();
      persist();
    },
    toggle(t) {
      const n = now();
      if (t.completed) {
        t.completed = false; t.completedAt = null;
        const mine = db.events.filter(e => e.taskId === t.id).sort((a, b) => new Date(b.completedAt) - new Date(a.completedAt));
        if (mine[0]) db.events = db.events.filter(e => e !== mine[0]);
      } else {
        db.events.push({ id: uid(), taskId: t.id, category: t.category, completedAt: n.toISOString(), scheduledFor: t.due });
        if (t.recurrence === 'none') { t.completed = true; t.completedAt = n.toISOString(); }
        else t.due = Recurrence.nextOccurrence(due(t), n, t.recurrence, t.anchorDay).toISOString();
      }
      t.updatedAt = n.toISOString(); persist();
    },
    remove(t) { db.tasks = db.tasks.filter(x => x !== t); db.events = db.events.filter(e => e.taskId !== t.id); persist(); },
    itemsOn(day) {
      const out = [];
      for (const t of db.tasks) {
        if (D.sameDay(due(t), day)) out.push({ t, date: due(t), proj: false });
        else if (!t.completed && t.recurrence !== 'none' && Recurrence.occursOn(day, due(t), t.recurrence, t.anchorDay))
          out.push({ t, date: D.atTime(day, due(t).getHours(), due(t).getMinutes()), proj: true });
      }
      return out.sort((a, b) => a.date - b.date);
    },
    interval(period) {
      const n = now();
      if (period === 'day') { const s = D.startOfDay(n); return [s, D.addDays(s, 1)]; }
      if (period === 'week') { const s = D.startOfWeek(n); return [s, D.addDays(s, 7)]; }
      const s = D.startOfMonth(n); return [s, D.addMonths(s, 1)];
    },
    stats(period) {
      const [s, e] = S.interval(period), n = now();
      const completed = db.events.filter(x => { const d = new Date(x.completedAt); return d >= s && d < e; }).length;
      const open = S.pending().filter(t => due(t) >= s && due(t) < e);
      const overdue = open.filter(t => due(t) < n).length;
      const pending = open.length - overdue, total = completed + pending + overdue;
      return { s, e, completed, pending, overdue, total, rate: total ? completed / total : 0 };
    }
  };
  function persist() { save(); render(); Push.sync(); }

  // ---------- Reminders (while the app is open) ----------
  function plannedReminders() {
    if (!db.settings.remindersEnabled) return [];
    const n = now(), out = [];
    for (const t of db.tasks) {
      if (t.completed || !t.offsets.length) continue;
      let occ = due(t);
      if (t.recurrence !== 'none' && occ <= n) occ = Recurrence.nextOccurrence(occ, n, t.recurrence, t.anchorDay);
      for (const o of t.offsets) out.push({ id: `${t.id}|${o}|${occ.getTime()}`, t, offset: o, occ, fire: D.addMinutes(occ, -o) });
    }
    return out;
  }
  async function notify(title, body, toastOnly) {
    toast(body);
    if (toastOnly) return; // the server push delivers the system notification
    try {
      if ('Notification' in window && Notification.permission === 'granted') {
        const reg = await navigator.serviceWorker?.getRegistration();
        if (reg) reg.showNotification(title, { body, icon: 'icons/icon-192.png', badge: 'icons/icon-192.png', lang: 'ar', dir: 'rtl' });
        else new Notification(title, { body, icon: 'icons/icon-192.png' });
      }
    } catch (e) { /* toast already shown */ }
  }
  function checkReminders() {
    const n = now(), windowStart = D.addMinutes(n, -10); // catch up on anything missed in the last 10 min
    let changed = false;
    for (const r of plannedReminders()) {
      if (r.fire <= n && r.fire >= windowStart && !db.fired.includes(r.id)) {
        db.fired.push(r.id); changed = true;
        notify('EGO FOCUS', reminderText(r.t, r.offset, r.occ), db.settings.pushEnabled);
      }
    }
    const s = db.settings;
    if (s.briefEnabled) {
      const [h, m] = s.briefTime.split(':').map(Number), at = D.atTime(n, h, m), key = D.startOfDay(n).toDateString();
      if (n >= at && n - at < 30 * 60000 && s.lastBrief !== key) {
        s.lastBrief = key; changed = true;
        const c = S.todayOpen().length + S.overdue().length;
        if (!db.settings.pushEnabled) notify('صباحك منظّم مع EGO FOCUS', c ? `لديك ${c} مهمة تنتظرك اليوم. ركّز على ما يهمك.` : 'لا مهام متبقية اليوم. ركّز على ما يهمك.');
      }
    }
    if (db.fired.length > 400) { db.fired = db.fired.slice(-200); changed = true; }
    if (changed) save();
  }

  // ---------- Server push (reminders while the app is closed) ----------
  const Push = {
    url: () => (window.EGO_PUSH_URL || '').replace(/\/$/, ''),
    available: () => !!(Push.url() && 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window),
    deviceId() { if (!db.settings.deviceId) { db.settings.deviceId = uid(); save(); } return db.settings.deviceId; },
    async post(path, body) {
      const r = await fetch(Push.url() + path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(Object.assign({ deviceId: Push.deviceId() }, body)) });
      if (!r.ok) throw new Error('HTTP ' + r.status); return r.json();
    },
    async enable() {
      const perm = await Notification.requestPermission(); // must run directly from the tap
      if (perm !== 'granted') { toast('لم يتم السماح بالإشعارات. فعّلها من إعدادات الآيفون ← الإشعارات ← EGO FOCUS.'); render(); return; }
      try {
        const reg = await navigator.serviceWorker.ready;
        const { publicKey } = await (await fetch(Push.url() + '/vapid')).json();
        const key = Uint8Array.from(atob(publicKey.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((publicKey.length + 3) % 4)), c => c.charCodeAt(0));
        let sub = await reg.pushManager.getSubscription();
        if (!sub) sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: key });
        await Push.post('/subscribe', { subscription: sub.toJSON() });
        db.settings.pushEnabled = true; save(); await Push.sync(true); render();
        toast('تم التفعيل: ستصلك التذكيرات حتى والتطبيق مغلق.');
      } catch (e) { toast('تعذر تفعيل الإشعارات: ' + e.message); render(); }
    },
    async disable() {
      db.settings.pushEnabled = false; save(); render();
      try { await Push.post('/unsubscribe', {}); const sub = await (await navigator.serviceWorker.ready).pushManager.getSubscription(); await sub?.unsubscribe(); } catch (e) { /* offline: server drops it later */ }
    },
    reminders() {
      const n = now(), horizon = D.addDays(n, 30), out = [], s = db.settings;
      if (s.remindersEnabled) for (const t of db.tasks) {
        if (t.completed || !t.offsets.length) continue;
        let occ = due(t); if (t.recurrence !== 'none' && occ <= n) occ = Recurrence.nextOccurrence(occ, n, t.recurrence, t.anchorDay);
        for (let k = 0; k < 40 && occ <= horizon; k++) {
          for (const o of t.offsets) {
            const at = D.addMinutes(occ, -o);
            if (at > n) out.push({ id: `${t.id}|${o}|${occ.getTime()}`, at: at.getTime(), title: 'EGO FOCUS', body: s.pushShowTitles ? reminderText(t, o, occ) : 'لديك تذكير بمهمة — افتح EGO FOCUS' });
          }
          if (t.recurrence === 'none') break;
          occ = Recurrence.next(occ, t.recurrence, t.anchorDay);
        }
      }
      if (s.briefEnabled) {
        const [h, m] = s.briefTime.split(':').map(Number);
        for (let i = 0; i < 14; i++) {
          const at = D.atTime(D.addDays(n, i), h, m); if (at <= n) continue;
          const c = S.itemsOn(at).filter(x => !x.t.completed).length;
          out.push({ id: 'brief|' + at.getTime(), at: at.getTime(), title: 'صباحك منظّم مع EGO FOCUS', body: c ? `لديك ${c} مهمة اليوم. ركّز على ما يهمك.` : 'ركّز على ما يهمك. افتح التطبيق لتخطيط يومك.' });
        }
      }
      return out.sort((a, b) => a.at - b.at).slice(0, 300);
    },
    _timer: null,
    sync(immediate) {
      if (!db.settings.pushEnabled || !Push.available()) return Promise.resolve();
      clearTimeout(Push._timer);
      return new Promise(res => { Push._timer = setTimeout(() => Push.post('/sync', { reminders: Push.reminders() }).catch(() => {}).finally(res), immediate ? 0 : 1200); });
    },
    async test() { try { const r = await Push.post('/test', {}); toast(r.ok ? 'أُرسل تنبيه من الخادم — اقفل التطبيق وانتظر ثوانٍ.' : 'لم يُقبل التنبيه (رمز ' + r.status + ').'); } catch (e) { toast('تعذر الاتصال بالخادم.'); } }
  };
  function reminderText(t, o, occ) {
    const span = { 15: '15 دقيقة', 30: '30 دقيقة', 60: 'ساعة' }[o] || (o + ' دقيقة');
    return o === 0 ? 'حان الآن موعد: ' + t.title : o === 1440 ? 'غداً الساعة ' + F.time(occ) + ': ' + t.title : 'بعد ' + span + ' (' + F.time(occ) + '): ' + t.title;
  }

  // ---------- UI state ----------
  const ui = { tab: 'home', sheet: null, editId: null, editDraft: null, calMonth: D.startOfMonth(new Date()), calSel: D.startOfDay(new Date()),
    period: 'week', showAllDone: false, filter: 'open', search: '', assistant: null };
  const $app = () => document.getElementById('app');

  function applyTheme() {
    const a = db.settings.appearance;
    const dark = a === 'dark' || (a === 'system' && matchMedia('(prefers-color-scheme: dark)').matches);
    document.documentElement.dataset.theme = dark ? 'dark' : 'light';
    document.querySelector('meta[name=theme-color]')?.setAttribute('content', dark ? '#000000' : '#f2f2f7');
  }

  // ---------- Components ----------
  function taskRow(t, opt = {}) {
    const d = opt.date || due(t), n = now();
    const late = !opt.proj && !t.completed && d < n;
    const when = (opt.timeOnly || D.sameDay(d, n)) ? F.time(d) : F.dateTime(d);
    const cat = CATEGORIES.find(c => c[0] === t.category) || CATEGORIES[2];
    const badge = !t.completed && (t.priority === 'high' || t.priority === 'urgent') ? `<span class="badge">${label(PRIORITIES, t.priority)}</span>` : '';
    return `<div class="task p-${t.priority} ${t.completed ? 'done' : ''}" data-act="edit" data-id="${t.id}">
      <button class="check" data-act="toggle" data-id="${t.id}" ${opt.proj ? 'disabled' : ''} aria-label="${t.completed ? 'إعادة فتح' : 'إكمال'} ${esc(t.title)}">${icon('check')}</button>
      <div class="body"><div class="title">${esc(t.title)}</div>
        ${t.details ? `<div class="details">${esc(t.details)}</div>` : ''}
        <div class="meta"><span class="${late ? 'late' : ''}">${icon(late ? 'alert' : 'clock')} ${when}</span><span>${icon(cat[2])} ${cat[1]}</span>
        ${t.recurrence !== 'none' ? `<span>${icon('repeat')} ${label(RECURRENCES, t.recurrence)}</span>` : ''}
        ${t.offsets.length && !t.completed ? `<span>${icon('bell')}</span>` : ''}</div></div>${badge}</div>`;
  }
  const empty = (ic, title, msg) => `<div class="empty"><div class="ic">${icon(ic)}</div><b>${title}</b><p>${msg}</p></div>`;
  const secHead = (title, count, cls = '') => `<div class="sec-head ${cls}"><h2>${title}</h2>${count != null ? `<span class="count">${count}</span>` : ''}</div>`;
  function ring(v, size = 76, stroke = 8, color = '#6ed9b8', track = 'rgba(255,255,255,.2)') {
    const r = (100 - stroke) / 2, c = 2 * Math.PI * r;
    return `<div class="ring" style="width:${size}px;height:${size}px"><svg viewBox="0 0 100 100"><circle cx="50" cy="50" r="${r}" fill="none" stroke="${track}" stroke-width="${stroke}"/><circle cx="50" cy="50" r="${r}" fill="none" stroke="${color}" stroke-width="${stroke}" stroke-linecap="round" stroke-dasharray="${c * Math.min(Math.max(v, 0), 1)} ${c}"/></svg><div class="val">${F.pct(v)}</div></div>`;
  }
  const isStandalone = () => window.navigator.standalone === true || matchMedia('(display-mode: standalone)').matches;

  // ---------- Views ----------
  function viewHome() {
    const n = now(), h = n.getHours();
    const greet = h >= 4 && h < 12 ? 'صباح الخير' : h < 17 && h >= 12 ? 'نهارك سعيد' : 'مساء الخير';
    const st = S.stats('day'), over = S.overdue(), today = S.todayOpen(), up = S.upcoming(), done = S.completed();
    let html = `<div class="view">
      <div class="home-head"><div><div class="date">${F.dayMonth(n)}</div><h1>${greet}</h1><div class="slogan">ركّز على ما يهمك.</div></div>
      <button class="circle-btn" data-act="all" aria-label="كل المهام">${icon('list')}</button></div>
      ${!isStandalone() ? `<div class="install">${icon('share')}<div>لتثبيت التطبيق على الآيفون: اضغط زر <b>المشاركة</b> في Safari ثم <b>«إضافة إلى الشاشة الرئيسية»</b>.</div></div>` : ''}
      <form class="quick" data-form="quick"><span class="lead">${icon('plusc')}</span><input id="quickInput" placeholder="أضف مهمة سريعة…" autocomplete="off" enterkeyhint="done">
        <button type="button" class="mic-btn" data-act="assistant" aria-label="المساعد الذكي">${icon('mic')}</button></form>
      <div class="hero"><div style="flex:1"><div class="lbl">ملخص إنتاجيتك اليوم</div><div class="big">أنجزت ${st.completed} من ${st.total}</div>
        <div class="pills"><div><b>${today.length}</b><span>متبقية اليوم</span></div><div><b>${over.length}</b><span>متأخرة</span></div><div><b>${up.length}</b><span>قادمة</span></div></div></div>${ring(st.rate)}</div>`;
    if (over.length) html += secHead('مهام متأخرة', over.length, 'red') + over.map(t => taskRow(t)).join('');
    html += secHead('مهام اليوم', today.length) + (today.length ? today.map(t => taskRow(t, { timeOnly: true })).join('')
      : empty('sun', over.length ? 'لا مهام أخرى لليوم' : 'لا مهام متبقية لليوم', 'أضف مهمة جديدة أو استخدم المساعد لتنظيم يومك.'));
    html += secHead('المهام القادمة', up.length) + (up.length ? up.slice(0, 6).map(t => taskRow(t)).join('') + (up.length > 6 ? `<button class="link-btn" data-act="all">عرض كل المهام القادمة (${up.length})</button>` : '')
      : empty('calendar', 'لا مهام قادمة', 'جدولك القادم فارغ. خطّط لأسبوعك من التقويم.'));
    if (done.length) {
      html += secHead('المهام المكتملة', done.length) + done.slice(0, ui.showAllDone ? 30 : 3).map(t => taskRow(t)).join('');
      if (done.length > 3) html += `<button class="link-btn" data-act="moreDone">${ui.showAllDone ? 'عرض أقل' : 'عرض المزيد'}</button>`;
    }
    return html + '</div>' + `<button class="fab" data-act="new" aria-label="إضافة مهمة">${icon('plus')}</button>`;
  }

  function viewCalendar() {
    const m = ui.calMonth, first = D.startOfMonth(m), count = D.daysInMonth(m.getFullYear(), m.getMonth()), n = now();
    const wds = Array.from({ length: 7 }, (_, i) => F.wdShort(new Date(2026, 10, 1 + i))); // 1 Nov 2026 is a Sunday
    let cells = '';
    for (let i = 0; i < first.getDay(); i++) cells += '<div></div>';
    for (let d = 1; d <= count; d++) {
      const day = new Date(m.getFullYear(), m.getMonth(), d), items = S.itemsOn(day);
      const open = items.filter(x => !x.t.completed);
      const top = open.length ? open.reduce((a, b) => (PRANK[b.t.priority] > PRANK[a.t.priority] ? b : a)).t.priority : (items.length ? 'low' : null);
      const cls = ['day', D.sameDay(day, n) ? 'today' : '', D.sameDay(day, ui.calSel) ? 'sel' : ''].join(' ');
      cells += `<button class="${cls}" data-act="pick" data-day="${day.getTime()}" aria-label="${F.fullDate(day)}">${d}<span class="dot ${top ? 'p-' + top : ''}" style="${top ? '' : 'visibility:hidden'}"></span></button>`;
    }
    const items = S.itemsOn(ui.calSel), isToday = D.sameDay(ui.calSel, n);
    return `<div class="view"><div class="top-actions"><button class="text-btn" data-act="calToday">اليوم</button></div>
      <div class="large-title">التقويم</div>
      <div class="cal-head"><button class="circle-btn" data-act="calPrev" aria-label="الشهر السابق">${icon('prev')}</button><h2>${F.monthYear(m)}</h2><button class="circle-btn" data-act="calNext" aria-label="الشهر التالي">${icon('next')}</button></div>
      <div class="card" style="padding:12px" id="calGrid"><div class="grid7">${wds.map(x => `<div class="wd">${x}</div>`).join('')}${cells}</div></div>
      ${secHead(isToday ? 'مهام اليوم' : F.dayMonth(ui.calSel), items.length)}
      ${items.length ? items.map(x => taskRow(x.t, { date: x.date, proj: x.proj, timeOnly: true })).join('') + (items.some(x => x.proj) ? `<div class="subtle small">${icon('repeat')} المهام المتكررة تظهر في مواعيدها القادمة؛ يمكن إنجاز الموعد الحالي فقط.</div>` : '')
        : empty('calendar', 'لا توجد مهام في هذا اليوم', 'اضغط + لإضافة مهمة في ' + F.dayMonth(ui.calSel) + '.')}
      </div><button class="fab" data-act="newOnDay" aria-label="إضافة مهمة">${icon('plus')}</button>`;
  }

  function viewReports() {
    const st = S.stats(ui.period), [s, e] = [st.s, st.e];
    const range = ui.period === 'day' ? F.fullDate(s) : `من ${F.short(s)} إلى ${F.short(D.addDays(e, -1))}`;
    const pname = { day: 'اليوم', week: 'الأسبوع', month: 'الشهر' }[ui.period];
    const days = []; for (let d = new Date(s); d < e; d = D.addDays(d, 1)) days.push(d);
    const counts = days.map(d => db.events.filter(x => D.sameDay(new Date(x.completedAt), d)).length), max = Math.max(1, ...counts);
    const cats = {}; db.events.forEach(x => { const d = new Date(x.completedAt); if (d >= s && d < e) cats[x.category] = (cats[x.category] || 0) + 1; });
    const catRows = CATEGORIES.filter(c => cats[c[0]]).sort((a, b) => cats[b[0]] - cats[a[0]]); const cmax = Math.max(1, ...Object.values(cats));
    const total = db.events.length + S.pending().length;
    const accent = getComputedStyle(document.documentElement).getPropertyValue('--accent').trim() || '#0d8571';
    return `<div class="view"><div class="large-title">التقارير</div>
      <div class="seg">${[['day', 'اليوم'], ['week', 'الأسبوع'], ['month', 'الشهر']].map(p => `<button class="${ui.period === p[0] ? 'on' : ''}" data-act="period" data-p="${p[0]}">${p[1]}</button>`).join('')}</div>
      <p class="subtle small" style="margin:10px 2px">${range}</p>
      <div class="card row" style="gap:18px">${ring(st.rate, 92, 10, accent, 'color-mix(in srgb, ' + accent + ' 18%, transparent)')}
        <div><b style="font-size:17px">نسبة الإنجاز</b><div class="subtle small">${st.total ? `أنجزت ${st.completed} من أصل ${st.total} مهمة مستحقة أو منجزة خلال ${pname}.` : 'لا توجد مهام مستحقة أو منجزة في هذه الفترة.'}</div></div></div>
      <div class="tiles">
        <div class="card tile" style="--tc:var(--accent)"><div class="ic">${icon('check')}</div><b>${st.completed}</b><span>مهام مكتملة</span></div>
        <div class="card tile" style="--tc:var(--blue)"><div class="ic">${icon('hour')}</div><b>${st.pending}</b><span>قيد الانتظار</span></div>
        <div class="card tile" style="--tc:var(--red)"><div class="ic">${icon('alert')}</div><b>${st.overdue}</b><span>متأخرة</span></div>
        <div class="card tile" style="--tc:var(--orange)"><div class="ic">${icon('list')}</div><b>${st.total}</b><span>إجمالي مهام الفترة</span></div></div>
      ${ui.period !== 'day' ? `<div class="card" style="margin-top:12px"><b>الإنجاز اليومي</b><div class="bars">${days.map((d, i) => `<div class="b"><i style="height:${Math.round(counts[i] / max * 100)}%"></i><small>${ui.period === 'week' ? F.wdShort(d) : (i % 5 === 0 ? d.getDate() : '')}</small></div>`).join('')}</div></div>` : ''}
      <div class="card" style="margin-top:12px"><b>الإنجاز حسب التصنيف</b>${catRows.length ? catRows.map(c => `<div class="hbar"><span class="name">${c[1]}</span><span class="track"><i style="width:${Math.max(6, cats[c[0]] / cmax * 100)}%"></i></span><b>${cats[c[0]]}</b></div>`).join('') : '<p class="subtle small">لم تُنجز مهام في هذه الفترة بعد.</p>'}</div>
      <div class="card" style="margin-top:12px"><b>نظرة عامة</b>
        <div class="kv"><span>كل المهام المسجلة</span><b>${db.tasks.length}</b></div><div class="kv"><span>المهام المفتوحة</span><b>${S.pending().length}</b></div>
        <div class="kv"><span>المتأخرة حالياً</span><b>${S.overdue().length}</b></div><div class="kv"><span>مرات الإنجاز المسجلة</span><b>${db.events.length}</b></div>
        <div class="kv"><span>نسبة الإنجاز الإجمالية</span><b>${F.pct(total ? db.events.length / total : 0)}</b></div></div></div>`;
  }

  function viewSettings() {
    const s = db.settings, perm = 'Notification' in window ? Notification.permission : 'unsupported';
    const permText = { granted: 'مفعّلة', denied: 'مرفوضة', default: 'لم يُطلب الإذن', unsupported: isStandalone() ? 'غير مدعومة' : 'متاحة بعد التثبيت على الشاشة الرئيسية' }[perm];
    return `<div class="view"><div class="large-title">الإعدادات</div>
      <div class="group-title">المظهر</div><div class="seg">${[['system', 'حسب النظام'], ['light', 'فاتح'], ['dark', 'داكن']].map(a => `<button class="${s.appearance === a[0] ? 'on' : ''}" data-act="theme" data-v="${a[0]}">${a[1]}</button>`).join('')}</div>
      <div class="group-title">التنبيهات</div><div class="group">
        <div class="item"><span>حالة الإشعارات</span><span class="val">${permText}</span></div>
        ${perm === 'default' ? `<button class="item btn" data-act="askNotif">${icon('bell')} السماح بالإشعارات</button>` : ''}
        <label class="item"><span>تذكيرات المهام</span><span class="switch"><input type="checkbox" data-set="remindersEnabled" ${s.remindersEnabled ? 'checked' : ''}><span></span></span></label>
        <div class="item"><span>التذكير الافتراضي</span><select data-set="defaultReminder">${[[-1, 'بدون تذكير'], ...ALLOWED_OFFSETS.map(o => [o, reminderLabel(o)])].map(o => `<option value="${o[0]}" ${+s.defaultReminder === o[0] ? 'selected' : ''}>${o[1]}</option>`).join('')}</select></div>
        <button class="item btn" data-act="testNotif">${icon('bell')} تجربة تنبيه داخل التطبيق</button></div>
      <div class="group-title">التذكير والتطبيق مغلق</div><div class="group">${pushSection()}</div>
      <div class="group-foot">${s.pushEnabled ? 'يرسل خادم EGO FOCUS على Cloudflare التذكير في موعده عبر خدمة إشعارات Apple. يُحفظ على الخادم موعد كل تذكير' + (s.pushShowTitles ? ' ونصّه' : ' فقط، بدون أسماء المهام') + '. التوقيت يعتمد على Apple وقد يتأخر قليلاً.' : 'بدون التفعيل تظهر التنبيهات والتطبيق مفتوح فقط.'}</div>
      <div class="group-title">التذكير الصباحي</div><div class="group">
        <label class="item"><span>الملخص الصباحي اليومي</span><span class="switch"><input type="checkbox" data-set="briefEnabled" ${s.briefEnabled ? 'checked' : ''}><span></span></span></label>
        ${s.briefEnabled ? `<div class="item"><span>الوقت</span><input type="time" data-set="briefTime" value="${s.briefTime}"></div>` : ''}</div>
      <div class="group-foot">يظهر عند فتح التطبيق خلال نصف ساعة من الوقت المختار.</div>
      <div class="group-title">البيانات والخصوصية</div><div class="group">
        <button class="item btn" data-act="privacy">${icon('lock')} بيان الخصوصية</button>
        <div class="item"><span>مكان التخزين</span><span class="val">على هذا الجهاز فقط</span></div>
        <div class="item"><span>المهام المحفوظة</span><span class="val">${db.tasks.length}</span></div>
        <button class="item btn" data-act="export">${icon('share')} نسخة احتياطية (تصدير)</button>
        <button class="item btn" data-act="import">${icon('drive')} استعادة من نسخة احتياطية</button></div>
      <div class="group-foot">احتفظ بنسخة احتياطية دورياً: حذف بيانات Safari أو حذف التطبيق من الشاشة الرئيسية يمسح المهام.</div>
      <div class="group-title">حول التطبيق</div><div class="group"><div class="item about"><img src="icons/icon-180.png" alt=""><div><b>EGO FOCUS</b><div class="subtle">إيجو فوكس</div><div class="slogan">ركّز على ما يهمك.</div></div></div>
        <div class="item"><span>الإصدار</span><span class="val">1.1 (ويب)</span></div></div>
      <input type="file" id="importFile" accept="application/json,.json" hidden></div>`;
  }

  function pushSection() {
    const s = db.settings;
    if (!Push.url()) return '<div class="item"><span class="subtle">خادم الإشعارات لم يُفعَّل بعد.</span></div>';
    if (!isStandalone()) return `<div class="item"><span class="subtle">${icon('share')} ثبّت التطبيق على الشاشة الرئيسية أولاً من Safari، ثم افتحه من الأيقونة.</span></div>`;
    if (!Push.available()) return '<div class="item"><span class="subtle">يحتاج iOS 16.4 أو أحدث.</span></div>';
    if (!s.pushEnabled) return `<button class="item btn" data-act="pushOn">${icon('bell')} تفعيل الإشعارات والتطبيق مغلق</button>`;
    return `<div class="item"><span>الحالة</span><span class="val" style="color:var(--accent)">مفعّلة ✓</span></div>
      <label class="item"><span>إظهار اسم المهمة في الإشعار</span><span class="switch"><input type="checkbox" data-set="pushShowTitles" ${s.pushShowTitles ? 'checked' : ''}><span></span></span></label>
      <button class="item btn" data-act="pushTest">${icon('bell')} إرسال تنبيه تجريبي من الخادم</button>
      <button class="item btn red" data-act="pushOff">إيقاف الإشعارات والتطبيق مغلق</button>`;
  }

  // ---------- Sheets ----------
  function sheetEditor() {
    const t = ui.editId ? S.get(ui.editId) : null, d = ui.editDraft;
    const recNote = { none: '', daily: 'عند إنجازها تنتقل إلى اليوم التالي في نفس الوقت.', weekly: 'تتكرر كل ' + F.wdShort(d.due) + ' في نفس الوقت.',
      monthly: d.due.getDate() > 28 ? `تتكرر يوم ${d.due.getDate()} من كل شهر؛ وفي الأشهر الأقصر تكون في آخر يوم من الشهر.` : `تتكرر يوم ${d.due.getDate()} من كل شهر.` }[d.recurrence];
    return `<div class="sheet-bar"><button data-act="close">إلغاء</button><h3>${t ? 'تعديل المهمة' : 'مهمة جديدة'}</h3><button class="bold" data-act="saveTask" id="saveBtn" ${d.title.trim() ? '' : 'disabled'}>حفظ</button></div>
    <div class="sheet-body">
      <div class="group-title">المهمة</div><div class="group">
        <div class="item"><input type="text" data-f="title" placeholder="عنوان المهمة" value="${esc(d.title)}" style="font-weight:650"></div>
        <div class="item"><input type="text" data-f="details" placeholder="الوصف" value="${esc(d.details)}"></div></div>
      <div class="group-title">الموعد</div><div class="group">
        <div class="item"><span>التاريخ والوقت</span><input type="datetime-local" data-f="due" value="${toLocalInput(d.due)}"></div>
        <div class="item chips"><button class="chip" data-act="quickDate" data-d="0">اليوم</button><button class="chip" data-act="quickDate" data-d="1">غداً</button><button class="chip" data-act="quickDate" data-d="7">بعد أسبوع</button></div></div>
      <div class="group-title">التصنيف والأولوية</div><div class="group">
        <div class="item"><span>التصنيف</span><select data-f="category">${CATEGORIES.map(c => `<option value="${c[0]}" ${d.category === c[0] ? 'selected' : ''}>${c[1]}</option>`).join('')}</select></div>
        <div class="item"><div class="seg" style="flex:1">${PRIORITIES.map(p => `<button class="${d.priority === p[0] ? 'on' : ''}" data-act="prio" data-v="${p[0]}">${p[1]}</button>`).join('')}</div></div></div>
      <div class="group-title">التكرار</div><div class="group"><div class="item"><span>التكرار</span><select data-f="recurrence">${RECURRENCES.map(r => `<option value="${r[0]}" ${d.recurrence === r[0] ? 'selected' : ''}>${r[1]}</option>`).join('')}</select></div></div>
      ${recNote ? `<div class="group-foot">${recNote}</div>` : ''}
      <div class="group-title">التذكير</div><div class="group">
        <label class="item"><span>تفعيل التذكير</span><span class="switch"><input type="checkbox" data-f="remOn" ${d.remOn ? 'checked' : ''}><span></span></span></label>
        ${d.remOn ? ALLOWED_OFFSETS.map(o => `<label class="item"><span>${reminderLabel(o)}</span><span class="switch"><input type="checkbox" data-off="${o}" ${d.offsets.includes(o) ? 'checked' : ''}><span></span></span></label>`).join('') : ''}</div>
      <div class="group-title">ملاحظات</div><div class="group"><div class="item"><textarea data-f="notes" placeholder="أضف ملاحظات">${esc(d.notes)}</textarea></div></div>
      ${t ? `<div class="group" style="margin-top:22px"><button class="item btn" data-act="sheetToggle">${icon('check')} ${t.completed ? 'إعادة فتح المهمة' : (t.recurrence === 'none' ? 'تم التنفيذ' : 'تم التنفيذ (الانتقال للموعد التالي)')}</button>
        <button class="item btn red" data-act="delete">${icon('trash')} حذف المهمة</button></div>` : ''}
    </div>`;
  }

  function sheetAll() {
    const base = ui.filter === 'open' ? S.pending() : ui.filter === 'done' ? S.completed() : [...S.pending(), ...S.completed()];
    const q = ui.search.trim(), items = q ? base.filter(t => [t.title, t.details, t.notes].some(x => (x || '').includes(q))) : base;
    return `<div class="sheet-bar"><button data-act="close">إغلاق</button><h3>كل المهام</h3><span style="min-width:56px"></span></div><div class="sheet-body">
      <input class="search" type="search" placeholder="ابحث في المهام" value="${esc(ui.search)}" data-act-input="search">
      <div class="seg" style="margin-bottom:12px">${[['open', 'قيد التنفيذ'], ['done', 'المكتملة'], ['all', 'الكل']].map(f => `<button class="${ui.filter === f[0] ? 'on' : ''}" data-act="filter" data-v="${f[0]}">${f[1]}</button>`).join('')}</div>
      <div id="allList">${items.length ? items.map(t => taskRow(t)).join('') : empty('list', 'لا توجد مهام', 'لا توجد مهام مطابقة.')}</div></div>`;
  }

  function sheetPrivacy() {
    const pts = [['drive', 'تخزين محلي فقط', 'المهام والإعدادات وسجل الإنجاز محفوظة في ذاكرة هذا المتصفح على جهازك. لا خادم، لا حساب، لا مزامنة سحابية.'],
      ['user', 'بدون حساب', 'لا تسجيل ولا تسجيل دخول، ولا نجمع اسمك أو بريدك أو أي بيانات شخصية.'],
      ['chart', 'بدون تتبع', 'لا أدوات تحليلات أو إعلانات. الصفحة لا ترسل بياناتك إلى أي مكان.'],
      ['msg', 'المساعد الذكي محلي', 'تحليل الأوامر العربية يتم داخل جهازك بقواعد محلية دون أي خدمة ذكاء اصطناعي خارجية.'],
      ['mic', 'الإملاء الصوتي', 'يستخدم خدمة التعرف على الكلام في المتصفح (Apple على الآيفون)، وقد تُعالَج عبر خوادم Apple. لا نحتفظ بأي تسجيل.'],
      ['trash', 'الحذف', 'حذف مهمة يزيلها مع سجلها. مسح بيانات Safari أو حذف التطبيق يمسح كل شيء من الجهاز؛ احتفظ بنسخة احتياطية.']];
    return `<div class="sheet-bar"><button data-act="close">إغلاق</button><h3>الخصوصية</h3><span style="min-width:56px"></span></div><div class="sheet-body">
      <h2 style="text-align:center;margin:10px 0">بياناتك على جهازك</h2>${pts.map(p => `<div class="privacy-pt"><div class="ic">${icon(p[0])}</div><div><b>${p[1]}</b><p>${p[2]}</p></div></div>`).join('')}</div>`;
  }

  function sheetAssistant() {
    const a = ui.assistant, r = a.result;
    let preview = '';
    if (r) {
      const canSave = a.draft.title.trim() && (!r.needsClarification || a.confirmed);
      preview = `<div class="card stack" style="margin-top:12px">
        <div class="row"><b style="font-size:17px">معاينة المهمة</b><span class="spacer"></span><span class="small" style="color:${r.needsClarification ? 'var(--orange)' : 'var(--accent)'};font-weight:700">${r.needsClarification ? 'تحتاج تأكيد' : 'مفهومة ✓'}</span></div>
        ${r.issues.length ? `<div class="warn">${r.issues.map(x => `<div>⚠︎ ${esc(x)}</div>`).join('')}</div>` : ''}
        <div><div class="field-lbl">العنوان</div><input class="field" data-af="title" value="${esc(a.draft.title)}"></div>
        <div class="prev-row"><span>الموعد</span><input type="datetime-local" data-af="due" value="${toLocalInput(a.draft.due)}"></div>
        <div class="prev-row"><span>التكرار</span><select data-af="recurrence">${RECURRENCES.map(x => `<option value="${x[0]}" ${a.draft.recurrence === x[0] ? 'selected' : ''}>${x[1]}</option>`).join('')}</select></div>
        <div class="prev-row"><span>التذكير</span><select data-af="reminder">${[[-1, 'بدون تذكير'], ...ALLOWED_OFFSETS.map(o => [o, reminderLabel(o)])].map(o => `<option value="${o[0]}" ${(a.draft.offsets[0] ?? -1) === o[0] ? 'selected' : ''}>${o[1]}</option>`).join('')}</select></div>
        ${r.hints.map(h => `<div class="subtle small">${icon('bulb')} ${esc(h)}</div>`).join('')}
        ${r.needsClarification ? `<label class="confirm"><input type="checkbox" data-af="confirmed" ${a.confirmed ? 'checked' : ''}> راجعتُ الموعد والعنوان وهما صحيحان</label>` : ''}
        <button class="btn-main wide" data-act="assistSave" ${canSave ? '' : 'disabled'}>${icon('plusc')} إضافة المهمة</button></div>`;
    }
    const sr = speechSupported();
    return `<div class="sheet-bar"><button data-act="close">إغلاق</button><h3>المساعد الذكي</h3><span style="min-width:56px"></span></div><div class="sheet-body">
      <p class="subtle small">اكتب المهمة أو قلها كما تفكر بها، وسأجهزها لك للمراجعة قبل الحفظ.</p>
      <div class="card stack"><textarea class="cmd" id="cmd" placeholder="مثال: ذكرني بالاجتماع بكرة الساعة 9 صباحاً">${esc(a.command)}</textarea>
        <div class="row">${sr ? `<button class="btn-tint ${a.listening ? 'rec' : ''}" data-act="mic">${icon(a.listening ? 'stop' : 'mic')} ${a.listening ? 'إيقاف' : 'تحدّث'}</button>` : ''}
          ${a.listening ? '<span class="listening">جارٍ الاستماع…</span>' : ''}<span class="spacer"></span>
          <button class="btn-main" data-act="analyze" id="analyzeBtn" ${a.command.trim() ? '' : 'disabled'}>تحليل الأمر</button></div>
        ${a.error ? `<div class="warn">${esc(a.error)}</div>` : ''}
        ${!sr ? '<div class="subtle small">الإملاء الصوتي غير مدعوم في هذا المتصفح؛ يمكنك استخدام زر الميكروفون في لوحة مفاتيح الآيفون.</div>' : ''}</div>
      ${!r ? `<div class="card" style="margin-top:12px"><b>جرّب مثلاً</b>${EXAMPLES.map(e => `<button class="example" data-act="example" data-v="${esc(e)}">${icon('msg')} ${esc(e)}</button>`).join('')}</div>` : preview}
      <p class="subtle small" style="margin-top:14px">${icon('lock')} تحليل النص يتم على جهازك دون أي خدمة خارجية.</p></div>`;
  }

  // ---------- Render ----------
  function render() {
    applyTheme();
    const scrollY = window.scrollY;
    const views = { home: viewHome, calendar: viewCalendar, reports: viewReports, settings: viewSettings };
    const tabs = [['home', 'الرئيسية', 'home'], ['calendar', 'التقويم', 'calendar'], ['reports', 'التقارير', 'chart'], ['settings', 'الإعدادات', 'gear']];
    let html = views[ui.tab]() + `<nav class="tabbar">${tabs.map(t => `<button class="${ui.tab === t[0] ? 'on' : ''}" data-act="tab" data-v="${t[0]}">${icon(t[2])}<span>${t[1]}</span></button>`).join('')}</nav>`;
    if (ui.sheet) {
      const sheets = { editor: sheetEditor, all: sheetAll, privacy: sheetPrivacy, assistant: sheetAssistant };
      const prevScroll = document.querySelector('.sheet-body')?.scrollTop || 0;
      html += `<div class="sheet-back" data-act="close"></div><div class="sheet" role="dialog">${sheets[ui.sheet]()}</div>`;
      $app().innerHTML = html;
      const sb = document.querySelector('.sheet-body'); if (sb) sb.scrollTop = prevScroll;
      document.body.style.overflow = 'hidden';
    } else {
      $app().innerHTML = html; document.body.style.overflow = '';
      window.scrollTo(0, scrollY);
    }
  }
  function openSheet(name) { ui.sheet = name; render(); }
  function closeSheet() { stopListening(); ui.sheet = null; ui.editId = null; render(); }

  function openEditor(t, dayDefault) {
    ui.editId = t ? t.id : null;
    if (t) ui.editDraft = { title: t.title, details: t.details, notes: t.notes, due: due(t), priority: t.priority, category: t.category, recurrence: t.recurrence, offsets: [...t.offsets], remOn: t.offsets.length > 0 };
    else {
      let d = D.suggestedDue(now());
      if (dayDefault) d = D.atTime(dayDefault, d.getHours(), d.getMinutes());
      const def = +db.settings.defaultReminder;
      ui.editDraft = { title: '', details: '', notes: '', due: d, priority: 'normal', category: 'personal', recurrence: 'none', offsets: def >= 0 ? [def] : [], remOn: def >= 0 };
    }
    openSheet('editor');
  }

  function toast(text) {
    document.querySelector('.toast')?.remove();
    const el = document.createElement('div'); el.className = 'toast';
    el.innerHTML = `<img src="icons/icon-180.png" alt=""><div><b>EGO FOCUS</b><div class="small">${esc(text)}</div></div>`;
    document.body.appendChild(el); setTimeout(() => el.remove(), 5000);
  }

  // ---------- Speech ----------
  let recog = null;
  const speechSupported = () => !!(window.SpeechRecognition || window.webkitSpeechRecognition);
  function startListening() {
    const SR = window.SpeechRecognition || window.webkitSpeechRecognition; if (!SR) return;
    const a = ui.assistant; a.error = null;
    try {
      recog = new SR(); recog.lang = 'ar-SA'; recog.interimResults = true; recog.continuous = false;
      recog.onresult = e => { let txt = ''; for (const r of e.results) txt += r[0].transcript; a.command = txt; a.result = null; const c = document.getElementById('cmd'); if (c) c.value = txt; const b = document.getElementById('analyzeBtn'); if (b) b.disabled = !txt.trim(); };
      recog.onerror = e => { a.error = e.error === 'not-allowed' || e.error === 'service-not-allowed' ? 'تم رفض إذن الميكروفون أو التعرف على الكلام. فعّله من إعدادات Safari ثم حاول مجدداً.' : (e.error === 'no-speech' ? 'لم يتم التقاط كلام واضح. حاول مرة أخرى أو اكتب المهمة.' : 'تعذر التعرف على الكلام: ' + e.error); };
      recog.onend = () => { a.listening = false; recog = null; if (ui.sheet === 'assistant') render(); };
      recog.start(); a.listening = true;
    } catch (err) { a.error = 'تعذر بدء الإملاء الصوتي.'; a.listening = false; }
    render();
  }
  function stopListening() { if (recog) { try { recog.stop(); } catch (e) {} } if (ui.assistant) ui.assistant.listening = false; }
  function analyze() {
    const a = ui.assistant; stopListening();
    const def = +db.settings.defaultReminder;
    const r = parse(a.command, now(), def >= 0 ? [def] : []);
    a.result = r; a.confirmed = false;
    a.draft = { title: r.title, due: r.date, recurrence: r.recurrence, offsets: r.reminderOffsets.slice(0, 1) };
    render();
  }

  // ---------- Events ----------
  document.addEventListener('click', e => {
    const el = e.target.closest('[data-act]'); if (!el) return;
    const act = el.dataset.act, id = el.dataset.id;
    switch (act) {
      case 'tab': ui.tab = el.dataset.v; window.scrollTo(0, 0); render(); break;
      case 'toggle': e.stopPropagation(); { const t = S.get(id); if (t) S.toggle(t); } break;
      case 'edit': { const t = S.get(id); if (t) openEditor(t); } break;
      case 'new': openEditor(null); break;
      case 'newOnDay': openEditor(null, ui.calSel); break;
      case 'assistant': ui.assistant = { command: '', result: null, draft: null, confirmed: false, listening: false, error: null }; openSheet('assistant'); break;
      case 'all': openSheet('all'); break;
      case 'privacy': openSheet('privacy'); break;
      case 'close': closeSheet(); break;
      case 'moreDone': ui.showAllDone = !ui.showAllDone; render(); break;
      case 'calPrev': ui.calMonth = D.addMonths(ui.calMonth, -1); render(); break;
      case 'calNext': ui.calMonth = D.addMonths(ui.calMonth, 1); render(); break;
      case 'calToday': ui.calMonth = D.startOfMonth(now()); ui.calSel = D.startOfDay(now()); render(); break;
      case 'pick': ui.calSel = new Date(+el.dataset.day); render(); break;
      case 'period': ui.period = el.dataset.p; render(); break;
      case 'filter': ui.filter = el.dataset.v; render(); break;
      case 'theme': db.settings.appearance = el.dataset.v; save(); render(); break;
      case 'askNotif': if ('Notification' in window) Notification.requestPermission().then(() => render()); break;
      case 'testNotif': notify('EGO FOCUS', 'هذا تنبيه تجريبي — التنبيهات تعمل.'); break;
      case 'pushOn': Push.enable(); break;
      case 'pushOff': Push.disable(); break;
      case 'pushTest': Push.test(); break;
      case 'export': exportData(); break;
      case 'import': document.getElementById('importFile')?.click(); break;
      case 'prio': ui.editDraft.priority = el.dataset.v; render(); break;
      case 'quickDate': { const d = ui.editDraft.due, day = D.addDays(D.startOfDay(now()), +el.dataset.d); ui.editDraft.due = D.atTime(day, d.getHours(), d.getMinutes()); render(); } break;
      case 'saveTask': {
        const d = ui.editDraft; const draft = Object.assign({}, d, { offsets: d.remOn ? d.offsets : [] });
        if (!draft.title.trim()) return;
        const t = ui.editId && S.get(ui.editId);
        if (t) S.update(t, draft); else S.add(draft);
        closeSheet();
        if (!t) maybeAskNotifications(draft);
      } break;
      case 'sheetToggle': { const t = S.get(ui.editId); if (t) { ui.sheet = null; S.toggle(t); ui.editId = null; } } break;
      case 'delete': { const t = S.get(ui.editId); if (t && confirm('حذف هذه المهمة نهائياً؟ سيتم حذفها مع سجل إنجازها من هذا الجهاز.')) { ui.sheet = null; ui.editId = null; S.remove(t); } } break;
      case 'mic': ui.assistant.listening ? (stopListening(), render()) : startListening(); break;
      case 'analyze': analyze(); break;
      case 'example': ui.assistant.command = el.dataset.v; analyze(); break;
      case 'assistSave': {
        const a = ui.assistant; if (!a.draft.title.trim()) return;
        S.add({ title: a.draft.title, due: a.draft.due, recurrence: a.draft.recurrence, offsets: a.draft.offsets, priority: 'normal', category: 'personal' });
        closeSheet(); toast('تمت إضافة المهمة.'); maybeAskNotifications(a.draft);
      } break;
    }
  });

  document.addEventListener('submit', e => {
    if (e.target.dataset.form === 'quick') {
      e.preventDefault();
      const inp = document.getElementById('quickInput'), title = inp.value.trim(); if (!title) return;
      const def = +db.settings.defaultReminder;
      S.add({ title, due: D.suggestedDue(now()), offsets: def >= 0 ? [def] : [] });
    }
  });

  document.addEventListener('input', e => {
    const el = e.target;
    if (el.id === 'cmd') { ui.assistant.command = el.value; const b = document.getElementById('analyzeBtn'); if (b) b.disabled = !el.value.trim(); if (ui.assistant.result) { ui.assistant.result = null; render(); document.getElementById('cmd')?.focus(); } return; }
    if (el.dataset.actInput === 'search') { ui.search = el.value; const list = document.getElementById('allList'); if (list) { const html = sheetAll(); const tmp = document.createElement('div'); tmp.innerHTML = html; list.innerHTML = tmp.querySelector('#allList').innerHTML; } return; }
    if (el.dataset.f && ui.editDraft) {
      const f = el.dataset.f;
      if (f === 'title' || f === 'details' || f === 'notes') { ui.editDraft[f] = el.value; if (f === 'title') document.getElementById('saveBtn').disabled = !el.value.trim(); }
      return;
    }
    if (el.dataset.af === 'title' && ui.assistant) { ui.assistant.draft.title = el.value; const btn = document.querySelector('[data-act=assistSave]'); if (btn) btn.disabled = !(el.value.trim() && (!ui.assistant.result.needsClarification || ui.assistant.confirmed)); }
  });

  document.addEventListener('change', e => {
    const el = e.target;
    if (el.dataset.set) {
      const k = el.dataset.set, s = db.settings;
      s[k] = el.type === 'checkbox' ? el.checked : (k === 'defaultReminder' ? +el.value : el.value);
      save(); render(); Push.sync();
      if (k === 'remindersEnabled' && el.checked && !s.pushEnabled) maybeAskNotifications({ offsets: [0] });
      return;
    }
    if (el.id === 'importFile') { importData(el.files[0]); el.value = ''; return; }
    if (el.dataset.f && ui.editDraft) {
      const f = el.dataset.f, d = ui.editDraft;
      if (f === 'due') { const v = fromLocalInput(el.value); if (v) d.due = v; render(); }
      else if (f === 'category' || f === 'recurrence') { d[f] = el.value; render(); }
      else if (f === 'remOn') { d.remOn = el.checked; if (d.remOn && !d.offsets.length) d.offsets = [0]; render(); }
      return;
    }
    if (el.dataset.off != null && ui.editDraft) {
      const o = +el.dataset.off, set = new Set(ui.editDraft.offsets);
      el.checked ? set.add(o) : set.delete(o); ui.editDraft.offsets = [...set].sort((a, b) => a - b); return;
    }
    if (el.dataset.af && ui.assistant) {
      const a = ui.assistant, f = el.dataset.af;
      if (f === 'due') { const v = fromLocalInput(el.value); if (v) a.draft.due = v; }
      else if (f === 'recurrence') a.draft.recurrence = el.value;
      else if (f === 'reminder') a.draft.offsets = +el.value < 0 ? [] : [+el.value];
      else if (f === 'confirmed') a.confirmed = el.checked;
      render();
    }
  });

  function maybeAskNotifications(draft) {
    if ((draft.offsets || []).length && 'Notification' in window && Notification.permission === 'default') Notification.requestPermission().then(() => render());
  }

  function exportData() {
    const blob = new Blob([JSON.stringify({ app: 'EGO FOCUS', version: 1, exportedAt: new Date().toISOString(), data: db }, null, 2)], { type: 'application/json' });
    const name = 'EGO-FOCUS-backup-' + toLocalInput(now()).slice(0, 10) + '.json';
    const file = new File([blob], name, { type: 'application/json' });
    if (navigator.canShare && navigator.canShare({ files: [file] })) navigator.share({ files: [file], title: 'EGO FOCUS' }).catch(() => {});
    else { const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = name; a.click(); setTimeout(() => URL.revokeObjectURL(a.href), 2000); }
  }
  function importData(file) {
    if (!file) return;
    const r = new FileReader();
    r.onload = () => {
      try {
        const j = JSON.parse(r.result), d = j.data || j;
        if (!Array.isArray(d.tasks)) throw new Error('bad');
        if (!confirm(`استبدال البيانات الحالية بـ ${d.tasks.length} مهمة من النسخة الاحتياطية؟`)) return;
        db = Object.assign(JSON.parse(JSON.stringify(defaults)), d); db.settings = Object.assign({}, defaults.settings, d.settings || {});
        save(); render(); toast('تمت استعادة البيانات.');
      } catch (e) { toast('الملف غير صالح.'); }
    };
    r.readAsText(file);
  }

  // ---------- Boot ----------
  load();
  matchMedia('(prefers-color-scheme: dark)').addEventListener?.('change', render);
  render();
  checkReminders();
  setInterval(checkReminders, 20000);
  document.addEventListener('visibilitychange', () => { if (!document.hidden) { render(); checkReminders(); Push.sync(); } });
  Push.sync();
  if ('serviceWorker' in navigator && location.protocol !== 'file:') navigator.serviceWorker.register('sw.js').catch(() => {});
  if (navigator.storage && navigator.storage.persist) navigator.storage.persist().catch(() => {});
})();
