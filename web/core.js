/* EGO FOCUS — core logic (no DOM). Port of the iOS app's Swift logic.
   Works in the browser (window.EGOCore) and in Node (module.exports) for tests. */
(function (root) {
  'use strict';

  // ---------- Dates ----------
  const D = {
    startOfDay(d) { const x = new Date(d); x.setHours(0, 0, 0, 0); return x; },
    addDays(d, n) { const x = new Date(d); x.setDate(x.getDate() + n); return x; },
    addMinutes(d, n) { return new Date(d.getTime() + n * 60000); },
    daysInMonth(y, m) { return new Date(y, m + 1, 0).getDate(); },
    sameDay(a, b) { return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate(); },
    atTime(day, h, m) { const x = new Date(day); x.setHours(h, m, 0, 0); return x; },
    startOfMonth(d) { return new Date(d.getFullYear(), d.getMonth(), 1); },
    addMonths(d, n) { return new Date(d.getFullYear(), d.getMonth() + n, 1); },
    startOfWeek(d) { const s = D.startOfDay(d); return D.addDays(s, -s.getDay()); }, // Sunday
    suggestedDue(now) {
      const h = now.getHours();
      if (h >= 22) return D.atTime(D.addDays(now, 1), 9, 0);
      const x = new Date(now); x.setHours(h + 1, 0, 0, 0); return x;
    }
  };

  // ---------- Recurrence ----------
  const Recurrence = {
    dateIn(year, month, day, h, m) {
      const count = D.daysInMonth(year, month);
      return new Date(year, month, Math.min(Math.max(day, 1), count), h, m, 0, 0);
    },
    next(date, rule, anchorDay) {
      switch (rule) {
        case 'daily': return D.addDays(date, 1);
        case 'weekly': return D.addDays(date, 7);
        case 'monthly': {
          const day = anchorDay > 0 ? anchorDay : date.getDate();
          const nm = D.addMonths(date, 1);
          return Recurrence.dateIn(nm.getFullYear(), nm.getMonth(), day, date.getHours(), date.getMinutes());
        }
        default: return date;
      }
    },
    nextOccurrence(date, after, rule, anchorDay) {
      if (rule === 'none') return date;
      let r = Recurrence.next(date, rule, anchorDay), guard = 0;
      while (r <= after && guard++ < 5000) r = Recurrence.next(r, rule, anchorDay);
      return r;
    },
    occursOn(day, start, rule, anchorDay) {
      const d = D.startOfDay(day), s = D.startOfDay(start);
      if (rule === 'none') return d.getTime() === s.getTime();
      if (d < s) return false;
      if (rule === 'daily') return true;
      if (rule === 'weekly') return day.getDay() === start.getDay();
      if (rule === 'monthly') {
        const anchor = anchorDay > 0 ? anchorDay : start.getDate();
        return day.getDate() === Math.min(anchor, D.daysInMonth(day.getFullYear(), day.getMonth()));
      }
      return false;
    }
  };

  // ---------- Arabic parser ----------
  const NUMBER_WORDS = {
    'واحد': 1, 'واحده': 1, 'الواحده': 1,
    'اتنين': 2, 'اثنين': 2, 'ثنتين': 2, 'اثنتين': 2, 'تنتين': 2,
    'تلاته': 3, 'ثلاثه': 3, 'ثلاث': 3, 'تلات': 3,
    'اربعه': 4, 'اربع': 4, 'خمسه': 5, 'خمس': 5, 'سته': 6, 'ست': 6, 'سبعه': 7, 'سبع': 7,
    'تمانيه': 8, 'ثمانيه': 8, 'ثماني': 8, 'ثمان': 8, 'تمن': 8, 'تسعه': 9, 'تسع': 9,
    'عشره': 10, 'عشر': 10,
    'حداشر': 11, 'احدعشر': 11, 'احد عشر': 11, 'احدي عشر': 11, 'احدي عشره': 11,
    'اتناشر': 12, 'اطناشر': 12, 'اثنا عشر': 12, 'اثني عشر': 12, 'اثنتا عشره': 12, 'اثنتي عشره': 12,
    'الاولي': 1, 'الثانيه': 2, 'الثالثه': 3, 'الرابعه': 4, 'الخامسه': 5, 'السادسه': 6,
    'السابعه': 7, 'الثامنه': 8, 'التاسعه': 9, 'العاشره': 10,
    'الحاديه عشر': 11, 'الحاديه عشره': 11, 'الثانيه عشر': 12, 'الثانيه عشره': 12
  };
  const NUM = '(\\d{1,2}|(?:' + Object.keys(NUMBER_WORDS).sort((a, b) => b.length - a.length).join('|') + ')(?![\\p{L}]))';
  const PERIOD_WORDS = 'صباحا|صباح|الصباح|الصبح|صبحا|فجرا|الفجر|فجر|ظهرا|الظهر|ظهر|بعد الظهر|عصرا|العصر|عصر|مساء|مساءا|المساء|المسا|مسا|مغربا|المغرب|ليلا|الليل|بالليل|بليل|am|pm|ص|م';
  const WEEKDAYS = [['احد', 0], ['اثنين', 1], ['اتنين', 1], ['ثلاثاء', 2], ['ثلاثا', 2], ['تلات', 2],
    ['اربعاء', 3], ['اربعا', 3], ['اربع', 3], ['خميس', 4], ['جمعه', 5], ['سبت', 6]];
  const WD = WEEKDAYS.map(x => x[0]).join('|');
  const MONTHS = [['يناير', 1], ['كانون الثاني', 1], ['فبراير', 2], ['شباط', 2], ['مارس', 3], ['اذار', 3],
    ['ابريل', 4], ['نيسان', 4], ['مايو', 5], ['ايار', 5], ['يونيو', 6], ['حزيران', 6], ['يوليو', 7], ['تموز', 7],
    ['اغسطس', 8], ['اب', 8], ['سبتمبر', 9], ['ايلول', 9], ['اكتوبر', 10], ['تشرين الاول', 10],
    ['نوفمبر', 11], ['تشرين الثاني', 11], ['ديسمبر', 12], ['كانون الاول', 12]];
  const MONTH_P = MONTHS.map(x => x[0]).sort((a, b) => b.length - a.length).join('|');
  const NEXT_WORDS = 'الجاي|الجايه|القادم|القادمه|المقبل|المقبله|اللي\\s*جاي';
  const ALLOWED_OFFSETS = [0, 15, 30, 60, 1440];

  const w = p => '(?<![\\p{L}\\p{N}])(?:' + p + ')(?![\\p{L}\\p{N}])';
  const number = t => { if (t == null) return null; t = t.trim(); if (!t) return null; return /^\d+$/.test(t) ? parseInt(t, 10) : (NUMBER_WORDS[t] ?? null); };
  const weekday = t => { const f = WEEKDAYS.find(x => x[0] === t); return f ? f[1] : null; };

  function periodFrom(word) {
    if (!word) return null;
    const x = word.trim().toLowerCase();
    if (!x) return null;
    if (x === 'بعد الظهر') return 'afternoon';
    if (x.includes('صب') || x.includes('فجر') || x === 'am' || x === 'ص') return 'morning';
    if (x.includes('ظهر')) return 'noon';
    if (x.includes('عصر')) return 'afternoon';
    if (x.includes('ليل')) return 'night';
    if (x.includes('مس') || x.includes('مغرب') || x === 'pm' || x === 'م') return 'evening';
    return null;
  }

  function clean(text) {
    let out = '';
    for (const ch of text) {
      const c = ch.codePointAt(0);
      if ((c >= 0x064B && c <= 0x0652) || c === 0x0670 || c === 0x0640) continue;
      if (c >= 0x0660 && c <= 0x0669) { out += String.fromCharCode(c - 0x0660 + 48); continue; }
      if (c >= 0x06F0 && c <= 0x06F9) { out += String.fromCharCode(c - 0x06F0 + 48); continue; }
      if (c === 0x060C) { out += ','; continue; }
      out += ch;
    }
    return out.replace(/\n/g, ' ').trim();
  }

  function normalizeLetters(text) { // one-to-one, keeps UTF-16 length
    const map = { 'أ': 'ا', 'إ': 'ا', 'آ': 'ا', 'ٱ': 'ا', 'ى': 'ي', 'ة': 'ه', 'ؤ': 'و', 'ئ': 'ي' };
    let out = '';
    for (const ch of text) {
      if (map[ch]) out += map[ch];
      else if (ch >= 'A' && ch <= 'Z') out += ch.toLowerCase();
      else out += ch;
    }
    return out;
  }

  class Engine {
    constructor(input, now) {
      this.now = now;
      const cleaned = clean(input.trim());
      this.base = cleaned;
      this.norm = normalizeLetters(cleaned);
      this.dayOffset = null; this.explicitDay = null; this.weekdayTarget = null; this.relativeDate = null;
      this.hour = null; this.minute = 0; this.period = null; this.timeIsApproximate = false;
      this.recurrence = 'none'; this.monthlyDay = null; this.reminderOffsets = []; this.hasReminderVerb = false;
      this.issues = []; this.hints = []; this.nextWeekRequested = false;
    }

    take(pattern) {
      const re = new RegExp(pattern, 'iu');
      const m = re.exec(this.norm);
      if (!m) return null;
      const blank = ' '.repeat(m[0].length);
      this.norm = this.norm.slice(0, m.index) + blank + this.norm.slice(m.index + m[0].length);
      this.base = this.base.slice(0, m.index) + blank + this.base.slice(m.index + m[0].length);
      return Array.from(m, g => (g === undefined ? null : g));
    }

    run(defaultOffsets) {
      this.parseRelativeTime();
      this.parseReminderOffsets();
      this.parseClockTime();
      this.parseRecurrence();
      this.parseDates();
      this.parseStandalonePeriod();
      this.removeCommandWords();
      let title = this.buildTitle();
      if (!title) this.issues.push('لم أتمكن من تحديد عنوان المهمة، اكتبه بنفسك.');
      const [date, dateDetected, timeDetected] = this.resolveDate();
      let offsets = this.reminderOffsets.length ? this.reminderOffsets : (this.hasReminderVerb ? [0] : defaultOffsets);
      if (dateDetected && timeDetected && date < this.now && !this.relativeDate) {
        this.issues.push('الموعد المفهوم في الماضي، راجع التاريخ والوقت.');
      }
      const anchor = this.monthlyDay ?? date.getDate();
      if (this.recurrence === 'monthly' && anchor > 28) {
        this.hints.push('في الأشهر الأقصر من اليوم ' + anchor + ' ستظهر المهمة في آخر يوم من الشهر.');
      }
      return {
        title, date, recurrence: this.recurrence,
        reminderOffsets: [...new Set(offsets)].sort((a, b) => a - b),
        dateDetected, timeDetected, issues: this.issues, hints: this.hints,
        needsClarification: this.issues.length > 0
      };
    }

    parseRelativeTime() {
      let minutes = null, g;
      if ((g = this.take(w('(?:بعد|خلال)\\s*' + NUM + '\\s*(?:دقيقه|دقايق|دقائق|دقيقة)')))) minutes = number(g[1]);
      else if ((g = this.take(w('(?:بعد|خلال)\\s*(نص|نصف|ربع)\\s*ساعه')))) minutes = g[1] === 'ربع' ? 15 : 30;
      else if ((g = this.take(w('(?:بعد|خلال)\\s*(ساعتين|ساعه)')))) minutes = g[1] === 'ساعتين' ? 120 : 60;
      else if ((g = this.take(w('(?:بعد|خلال)\\s*' + NUM + '\\s*(?:ساعات|ساعه)')))) { const n = number(g[1]); minutes = n == null ? null : n * 60; }
      if (minutes && minutes > 0) this.relativeDate = D.addMinutes(this.now, minutes);
    }

    parseClockTime() {
      if (this.relativeDate) return;
      const minutePart = '(?:\\s*[:.]\\s*(\\d{2}))?';
      const fraction = '(?:\\s*(و\\s*(?:نص|النص|نصف|النصف|ربع|الربع|ثلث|الثلث|\\d{1,2}\\s*(?:دقيقه|دقايق|دقائق|د)?)|الا\\s*(?:ربع|الربع|ثلث|الثلث|\\d{1,2}\\s*(?:دقيقه|دقايق|دقائق|د)?)))?';
      const periodPart = '(?:\\s*(?:في\\s*|ب)?(' + PERIOD_WORDS + ')(?![\\p{L}]))';
      let g;
      if ((g = this.take('(?<![\\p{L}])(?:ال)?ساعه\\s*' + NUM + minutePart + fraction + periodPart + '?'))) return this.applyTime(g[1], g[2], g[3], g[4]);
      if ((g = this.take('(?<![\\p{L}\\p{N}/])' + NUM + minutePart + fraction + periodPart))) return this.applyTime(g[1], g[2], g[3], g[4]);
      if ((g = this.take('(?<![\\p{N}/])(\\d{1,2}):(\\d{2})(?![\\p{N}])' + periodPart + '?'))) this.applyTime(g[1], g[2], null, g[3]);
    }

    applyTime(hourTok, minTok, fraction, periodWord) {
      let h = number(hourTok); if (h == null) return;
      let m = minTok ? parseInt(minTok, 10) : 0;
      if (fraction && fraction.trim()) {
        const f = fraction.trim(); const digits = parseInt(f.replace(/\D/g, '') || '0', 10);
        if (f.startsWith('الا')) {
          const minus = f.includes('ربع') ? 15 : (f.includes('ثلث') ? 20 : digits);
          h = h === 0 ? 23 : h - 1; m = 60 - minus;
        } else if (f.includes('نص')) m = 30;
        else if (f.includes('ربع')) m = 15;
        else if (f.includes('ثلث')) m = 20;
        else m = digits;
      }
      if (h < 0 || h > 24 || m < 0 || m > 59) { this.issues.push('الوقت المذكور غير صالح، حدّده يدوياً.'); return; }
      this.hour = h === 24 ? 0 : h; this.minute = m; this.period = periodFrom(periodWord);
    }

    parseStandalonePeriod() {
      if (this.take(w('الليله'))) {
        if (this.dayOffset == null && !this.explicitDay && this.weekdayTarget == null) this.dayOffset = 0;
        if (!this.period) this.period = 'evening';
      }
      if (this.period) return;
      const g = this.take(w('الصبح|الصباح|صباحا|الفجر|فجرا|الظهر|ظهرا|بعد الظهر|العصر|عصرا|المغرب|المساء|مساء|بالليل|ليلا'));
      if (!g) return;
      this.period = periodFrom(g[0]);
      if (this.hour == null) {
        const word = g[0];
        switch (this.period) {
          case 'morning': this.hour = word.includes('فجر') ? 5 : 9; break;
          case 'noon': this.hour = 12; break;
          case 'afternoon': this.hour = 15; this.minute = 30; break;
          case 'evening': this.hour = word.includes('مغرب') ? 18 : 19; break;
          case 'night': this.hour = 21; break;
        }
        this.timeIsApproximate = true;
      }
    }

    parseReminderOffsets() {
      const before = 'قبل(?:ها|ه|الموعد|\\s*الموعد)?\\s*(?:ب)?\\s*';
      let found = true, g;
      while (found) {
        found = false;
        if ((g = this.take(w(before + '(\\d{1,4})\\s*(?:دقيقه|دقايق|دقائق|د)')))) { this.addOffset(parseInt(g[1], 10)); found = true; }
        else if (this.take(w(before + '(?:ربع|الربع)\\s*ساعه'))) { this.addOffset(15); found = true; }
        else if (this.take(w(before + '(?:نص|نصف)\\s*ساعه'))) { this.addOffset(30); found = true; }
        else if (this.take(w(before + '(?:ساعه|بساعه)'))) { this.addOffset(60); found = true; }
        else if (this.take(w(before + '(?:يوم|بيوم)'))) { this.addOffset(1440); found = true; }
      }
    }

    addOffset(min) {
      if (ALLOWED_OFFSETS.includes(min)) { this.reminderOffsets.push(min); return; }
      const nearest = ALLOWED_OFFSETS.reduce((a, b) => (Math.abs(b - min) < Math.abs(a - min) ? b : a));
      this.reminderOffsets.push(nearest);
      this.hints.push('تم تقريب التذكير إلى ' + reminderLabel(nearest) + '.');
    }

    parseRecurrence() {
      let g;
      if ((g = this.take(w('كل\\s*(?:يوم\\s*)?(?:ال)?(' + WD + ')')))) { this.recurrence = 'weekly'; this.weekdayTarget = weekday(g[1]); }
      else if ((g = this.take(w('(?:يوم\\s*)?(\\d{1,2})\\s*من\\s*كل\\s*شهر')))) { this.recurrence = 'monthly'; this.monthlyDay = parseInt(g[1], 10); }
      else if ((g = this.take(w('كل\\s*شهر\\s*(?:يوم|في)\\s*(\\d{1,2})')))) { this.recurrence = 'monthly'; this.monthlyDay = parseInt(g[1], 10); }
      else if (this.take(w('كل\\s*يوم|يوميا|كل\\s*صباح|كل\\s*ليله'))) this.recurrence = 'daily';
      else if (this.take(w('كل\\s*اسبوع|اسبوعيا'))) this.recurrence = 'weekly';
      else if (this.take(w('كل\\s*شهر|شهريا'))) this.recurrence = 'monthly';
      if (this.monthlyDay != null && (this.monthlyDay < 1 || this.monthlyDay > 31)) {
        this.monthlyDay = null; this.issues.push('يوم الشهر غير صالح، حدّده يدوياً.');
      }
    }

    parseDates() {
      let g;
      if (this.take(w('بعد\\s*(?:بكره|بكرا|غد|الغد)'))) this.dayOffset = 2;
      else if (this.take(w('بكره|بكرا|غدا|الغد|غدوه'))) this.dayOffset = 1;
      else if (this.take(w('اليوم|النهارده|النهارد|انهارده|هاليوم'))) this.dayOffset = 0;

      if (this.dayOffset == null && (g = this.take(w('بعد\\s*(?:(يومين|اسبوعين|شهرين)|' + NUM + '\\s*(يوم|ايام|اسبوع|اسابيع|شهر|شهور|اشهر)|(يوم|اسبوع|شهر))')))) {
        if (g[1]) { if (g[1] === 'يومين') this.dayOffset = 2; else if (g[1] === 'اسبوعين') this.dayOffset = 14; else this.relativeMonths(2); }
        else if (g[3] && number(g[2]) != null) {
          const n = number(g[2]), u = g[3];
          if (u.startsWith('يوم') || u === 'ايام') this.dayOffset = n; else if (u.includes('اسب')) this.dayOffset = n * 7; else this.relativeMonths(n);
        } else if (g[4]) { if (g[4] === 'يوم') this.dayOffset = 1; else if (g[4] === 'اسبوع') this.dayOffset = 7; else this.relativeMonths(1); }
      }

      if (this.weekdayTarget == null && (g = this.take(w('(?:يوم\\s*(?:ال)?|ال)(' + WD + ')(?:\\s*(?:' + NEXT_WORDS + '))?')))) this.weekdayTarget = weekday(g[1]);

      if (!this.explicitDay && (g = this.take('(?<![\\p{N}:.])(\\d{1,2})\\s*[/\\-]\\s*(\\d{1,2})(?:\\s*[/\\-]\\s*(\\d{2,4}))?(?![\\p{N}:])')))
        this.setExplicit(parseInt(g[1], 10), parseInt(g[2], 10), g[3] ? parseInt(g[3], 10) : null);

      if (!this.explicitDay && (g = this.take(w('(?:يوم\\s*)?(\\d{1,2})\\s*(?:من\\s*)?(?:شهر\\s*)?(' + MONTH_P + ')(?:\\s*(\\d{4}))?')))) {
        const mo = (MONTHS.find(x => x[0] === g[2]) || [])[1];
        this.setExplicit(parseInt(g[1], 10), mo, g[3] ? parseInt(g[3], 10) : null);
      }

      const monthMod = 'هذا\\s*الشهر|الشهر\\s*(?:' + NEXT_WORDS + ')|الشهر|شهر';
      if (!this.explicitDay) {
        g = this.take(w('يوم\\s*(\\d{1,2})(?:\\s*من\\s*(' + monthMod + '))?'));
        if (!g) g = this.take(w('(\\d{1,2})\\s*من\\s*(' + monthMod + ')'));
        if (g) {
          const mod = (g[2] || '').trim();
          const forceNext = mod.includes('الشهر') && mod !== 'الشهر' && !mod.includes('هذا');
          this.dayOfMonth(parseInt(g[1], 10), forceNext);
          if ((mod === 'الشهر' || mod === 'شهر') && this.recurrence === 'none')
            this.hints.push('إذا كانت المهمة تتكرر كل شهر، اختر «شهرياً» من التكرار.');
        }
      }

      if (this.take(w('(?:اخر|نهايه)\\s*(?:هذا\\s*)?الشهر'))) {
        const n = this.now; this.explicitDay = new Date(n.getFullYear(), n.getMonth(), D.daysInMonth(n.getFullYear(), n.getMonth()));
      }
      if (this.take(w('الاسبوع\\s*(?:' + NEXT_WORDS + ')'))) {
        if (this.weekdayTarget == null && this.dayOffset == null && !this.explicitDay) { this.dayOffset = 7; this.issues.push('حدّد يوم المهمة في الأسبوع القادم.'); }
        else this.nextWeekRequested = true;
      }
      if (this.take(w('الشهر\\s*(?:' + NEXT_WORDS + ')')) && !this.explicitDay && this.dayOffset == null && this.weekdayTarget == null) {
        this.relativeMonths(1); this.issues.push('حدّد يوم المهمة في الشهر القادم.');
      }
    }

    relativeMonths(n) { const x = new Date(this.now); const day = x.getDate(); const t = new Date(x.getFullYear(), x.getMonth() + n, 1); this.explicitDay = new Date(t.getFullYear(), t.getMonth(), Math.min(day, D.daysInMonth(t.getFullYear(), t.getMonth()))); }

    setExplicit(day, month, year) {
      if (!day || !month || day < 1 || day > 31 || month < 1 || month > 12) { this.issues.push('لم أفهم التاريخ المكتوب، حدّده يدوياً.'); return; }
      let y;
      if (year != null) y = year < 100 ? 2000 + year : year;
      else { y = this.now.getFullYear(); if (new Date(y, month - 1, day) < D.startOfDay(this.now)) y += 1; }
      const date = new Date(y, month - 1, day);
      if (date.getDate() !== day) { this.issues.push('هذا التاريخ غير موجود في التقويم، حدّده يدوياً.'); return; }
      this.explicitDay = date;
    }

    dayOfMonth(day, forceNext) {
      if (!day || day < 1 || day > 31) { this.issues.push('يوم الشهر غير صالح، حدّده يدوياً.'); return; }
      if (this.recurrence === 'monthly' && this.monthlyDay == null) this.monthlyDay = day;
      let month = D.startOfMonth(this.now);
      if (forceNext) month = D.addMonths(month, 1);
      for (let i = 0; i < 13; i++) {
        if (day <= D.daysInMonth(month.getFullYear(), month.getMonth())) {
          const c = new Date(month.getFullYear(), month.getMonth(), day);
          if (c >= D.startOfDay(this.now)) { this.explicitDay = c; return; }
        }
        month = D.addMonths(month, 1);
      }
    }

    removeCommandWords() {
      const polite = '^\\s*(?:من\\s*فضلك|لو\\s*سمحت|ممكن|رجاء|رجاءا)\\s*';
      const remind = '^\\s*(?:ذكرني|ذكريني|ذكرنا|فكرني|فكريني|نبهني|نبهيني|ذكرنى)(?![\\p{L}])\\s*(?:ب(?=\\p{L})|ان\\s+|اني\\s+|انه\\s+|عشان\\s+|علشان\\s+|ب\\s+)?';
      const add = '^\\s*(?:اضف|اضيف|ضيف|ضيفي|سجل|سجلي|اكتب|انشئ|حط|ضع)(?![\\p{L}])\\s*(?:لي\\s*)?(?:مهمه\\s*(?:جديده)?)?\\s*:?\\s*';
      const task = '^\\s*(?:مهمه\\s*جديده|مهمه)(?![\\p{L}])\\s*:?\\s*';
      const want = '^\\s*(?:عندي|لدي|لازم|يجب|ابغى|ابغي|ابي|بدي|عايز|عاوز|محتاج|احتاج|اريد|اود)(?![\\p{L}])\\s*(?:ان\\s+|اني\\s+)?';
      for (let i = 0; i < 4; i++) {
        let changed = false;
        if (this.take(polite)) changed = true;
        if (this.take(remind)) { this.hasReminderVerb = true; changed = true; }
        if (this.take(add)) changed = true;
        if (this.take(task)) changed = true;
        if (this.take(want)) changed = true;
        if (!changed) break;
      }
      if (this.take(w('ذكرني|فكرني|نبهني') + '\\s*(?:ب(?=\\p{L}))?')) this.hasReminderVerb = true;
    }

    buildTitle() {
      const words = this.base.split(/\s+/).filter(Boolean);
      const edge = new Set(['في', 'يوم', 'على', 'علي', 'الساعه', 'الساعة', 'و', 'من', 'عند', 'بتاريخ', 'تاريخ', 'ب', 'الى', 'إلى', 'ل', 'مع', '،', ',', '-', ':']);
      const n = s => normalizeLetters(s).replace(/^[\p{P}]+|[\p{P}]+$/gu, '');
      while (words.length && (edge.has(n(words[0])) || !n(words[0]))) words.shift();
      while (words.length && (edge.has(n(words[words.length - 1])) || !n(words[words.length - 1]))) words.pop();
      return words.join(' ').replace(/^[\s\p{P}]+|[\s\p{P}]+$/gu, '');
    }

    finalHour() {
      const h = this.hour; if (h == null) return null;
      switch (this.period) {
        case 'morning': return h === 12 ? 0 : h;
        case 'noon': if (h === 12 || h === 11) return h; return h < 12 ? h + 12 : h;
        case 'afternoon': case 'evening': return h < 12 ? h + 12 : h;
        case 'night': if (h === 12) return 0; if (h <= 4) return h; return h < 12 ? h + 12 : h;
        default: if (h === 0 || h >= 12) return h; return h <= 6 ? h + 12 : h;
      }
    }

    resolveDate() {
      const now = this.now;
      if (this.relativeDate) return [this.relativeDate, true, true];
      let day = null;
      if (this.explicitDay) day = D.startOfDay(this.explicitDay);
      else if (this.weekdayTarget != null) {
        let delta = (this.weekdayTarget - now.getDay() + 7) % 7;
        if (delta === 0) {
          const fh = this.finalHour();
          delta = (fh != null && D.atTime(now, fh, this.minute) > now) ? 0 : 7;
        }
        if (this.nextWeekRequested && delta < 7) delta += 7;
        day = D.addDays(D.startOfDay(now), delta);
      } else if (this.dayOffset != null) day = D.addDays(D.startOfDay(now), this.dayOffset);
      else if (this.recurrence === 'monthly' && this.monthlyDay != null) {
        this.dayOfMonth(this.monthlyDay, false);
        if (this.explicitDay) day = D.startOfDay(this.explicitDay);
      }
      const h = this.finalHour();
      if (h != null) {
        if (this.hour >= 1 && this.hour <= 11 && !this.period) this.issues.push('حدّد إن كان الوقت صباحاً أم مساءً.');
        if (this.timeIsApproximate) this.issues.push('الوقت تقريبي، حدّده بدقة.');
        const baseDay = day || D.startOfDay(now);
        let date = D.atTime(baseDay, h, this.minute);
        if (!day && date <= now) date = D.addDays(date, 1);
        return [date, true, true];
      }
      if (day) {
        this.issues.push('لم تحدد وقتاً؛ اقترحت وقتاً افتراضياً، راجعه.');
        let date = D.atTime(day, 9, 0);
        if (date <= now) date = D.suggestedDue(now);
        return [date, true, false];
      }
      if (this.recurrence !== 'none') {
        this.issues.push('لم تحدد وقتاً؛ اقترحت وقتاً افتراضياً، راجعه.');
        return [D.suggestedDue(now), true, false];
      }
      this.issues.push('لم أفهم موعد المهمة؛ حدّد التاريخ والوقت.');
      return [D.suggestedDue(now), false, false];
    }
  }

  function parse(input, now = new Date(), defaultOffsets = [0]) {
    return new Engine(input, now).run(defaultOffsets);
  }

  function reminderLabel(o) {
    return { 0: 'في وقت المهمة', 15: 'قبلها بـ 15 دقيقة', 30: 'قبلها بـ 30 دقيقة', 60: 'قبلها بساعة', 1440: 'قبلها بيوم' }[o] || ('قبلها بـ ' + o + ' دقيقة');
  }

  const api = { D, Recurrence, parse, reminderLabel, normalizeLetters, ALLOWED_OFFSETS };
  if (typeof module !== 'undefined' && module.exports) module.exports = api; else root.EGOCore = api;
})(typeof window !== 'undefined' ? window : globalThis);
