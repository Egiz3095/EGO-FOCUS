import Foundation

/// Result of parsing an Arabic task command. Never saved automatically: the assistant shows
/// a preview, and anything uncertain is listed in `issues` and must be confirmed by the user.
struct ParsedTask: Equatable {
    var title: String
    var date: Date
    var recurrence: TaskRecurrence
    var reminderOffsets: [Int]
    var dateDetected: Bool
    var timeDetected: Bool
    /// Problems that need the user's confirmation before saving.
    var issues: [String]
    /// Non-blocking suggestions.
    var hints: [String]

    var needsClarification: Bool { !issues.isEmpty }
}

/// Local rule-based parser for Gulf, Egyptian and Modern Standard Arabic task commands.
/// No network, no external AI service.
enum NaturalLanguageTaskParser {
    static func parse(_ input: String, now: Date = .now, calendar: Calendar = AppCalendar.calendar,
                      defaultReminderOffsets: [Int] = [0]) -> ParsedTask {
        var engine = Engine(input: input, now: now, calendar: calendar)
        return engine.run(defaultReminderOffsets: defaultReminderOffsets)
    }

    // MARK: - Engine

    private struct Engine {
        let now: Date
        let calendar: Calendar
        let original: String
        /// Text used for the title (diacritics removed, digits converted).
        let base: NSMutableString
        /// Same length as `base`, with letter variants unified, used for matching.
        let norm: NSMutableString

        init(input: String, now: Date, calendar: Calendar) {
            self.now = now
            self.calendar = calendar
            self.original = input.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleaned = Engine.clean(original)
            self.base = NSMutableString(string: cleaned)
            self.norm = NSMutableString(string: Engine.normalizeLetters(cleaned))
        }

        // Parsed state
        var dayOffset: Int?
        var explicitDay: DateComponents?
        var weekdayTarget: Int?
        var relativeDate: Date?
        var hour: Int?
        var minute = 0
        var period: Period?
        var timeIsApproximate = false
        var recurrence: TaskRecurrence = .none
        var monthlyDay: Int?
        var reminderOffsets: [Int] = []
        var hasReminderVerb = false
        var issues: [String] = []
        var hints: [String] = []
        var nextWeekRequested = false

        enum Period { case morning, noon, afternoon, evening, night }

        // MARK: Run

        mutating func run(defaultReminderOffsets: [Int]) -> ParsedTask {
            parseRelativeTime()
            parseReminderOffsets()
            parseClockTime()
            parseRecurrence()
            parseDates()
            parseStandalonePeriod()
            removeCommandWords()

            var title = buildTitle()
            if title.isEmpty {
                issues.append("لم أتمكن من تحديد عنوان المهمة، اكتبه بنفسك.")
                title = ""
            }

            let (date, dateDetected, timeDetected) = resolveDate()
            var offsets = reminderOffsets
            if offsets.isEmpty { offsets = hasReminderVerb ? [0] : defaultReminderOffsets }

            if dateDetected && timeDetected && date < now && relativeDate == nil {
                issues.append("الموعد المفهوم في الماضي، راجع التاريخ والوقت.")
            }
            let anchor = monthlyDay ?? calendar.component(.day, from: date)
            if recurrence == .monthly, anchor > 28 {
                let day = anchor
                hints.append("في الأشهر الأقصر من اليوم \(day) ستظهر المهمة في آخر يوم من الشهر.")
            }
            return ParsedTask(title: title, date: date, recurrence: recurrence,
                              reminderOffsets: Array(Set(offsets)).sorted(),
                              dateDetected: dateDetected, timeDetected: timeDetected,
                              issues: issues, hints: hints)
        }

        // MARK: Matching helpers

        /// Wraps a pattern with Arabic-aware word boundaries.
        static func w(_ pattern: String) -> String {
            "(?<![\\p{L}\\p{N}])(?:\(pattern))(?![\\p{L}\\p{N}])"
        }

        /// Finds the first match in the normalized text, returns captured groups and masks the match.
        mutating func take(_ pattern: String) -> [String?]? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                assertionFailure("Bad pattern: \(pattern)")
                return nil
            }
            let text = norm as String
            guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: norm.length)) else {
                return nil
            }
            var groups: [String?] = []
            for index in 0..<match.numberOfRanges {
                let r = match.range(at: index)
                groups.append(r.location == NSNotFound ? nil : norm.substring(with: r))
            }
            mask(match.range)
            return groups
        }

        func contains(_ pattern: String) -> Bool {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
            return regex.firstMatch(in: norm as String, range: NSRange(location: 0, length: norm.length)) != nil
        }

        func mask(_ range: NSRange) {
            let blank = String(repeating: " ", count: range.length)
            norm.replaceCharacters(in: range, with: blank)
            base.replaceCharacters(in: range, with: blank)
        }

        // MARK: Vocabulary (normalized spelling: ا for أإآ, ي for ى, ه for ة)

        static let numberWords: [String: Int] = [
            "واحد": 1, "واحده": 1, "الواحده": 1,
            "اتنين": 2, "اثنين": 2, "ثنتين": 2, "اثنتين": 2, "تنتين": 2,
            "تلاته": 3, "ثلاثه": 3, "ثلاث": 3, "تلات": 3,
            "اربعه": 4, "اربع": 4,
            "خمسه": 5, "خمس": 5,
            "سته": 6, "ست": 6,
            "سبعه": 7, "سبع": 7,
            "تمانيه": 8, "ثمانيه": 8, "ثماني": 8, "ثمان": 8, "تمن": 8,
            "تسعه": 9, "تسع": 9,
            "عشره": 10, "عشر": 10,
            "حداشر": 11, "احدعشر": 11, "احد عشر": 11, "احدي عشر": 11, "احدي عشره": 11,
            "اتناشر": 12, "اطناشر": 12, "اثنا عشر": 12, "اثني عشر": 12, "اثنتا عشره": 12, "اثنتي عشره": 12,
            "الاولي": 1, "الثانيه": 2, "الثالثه": 3, "الرابعه": 4, "الخامسه": 5, "السادسه": 6,
            "السابعه": 7, "الثامنه": 8, "التاسعه": 9, "العاشره": 10,
            "الحاديه عشر": 11, "الحاديه عشره": 11, "الثانيه عشر": 12, "الثانيه عشره": 12
        ]

        static var numberPattern: String {
            let words = numberWords.keys.sorted { $0.count > $1.count }.joined(separator: "|")
            return "(\\d{1,2}|(?:\(words))(?![\\p{L}]))"
        }

        static func number(_ token: String?) -> Int? {
            guard let token = token?.trimmingCharacters(in: .whitespaces), !token.isEmpty else { return nil }
            return Int(token) ?? numberWords[token]
        }

        static let periodWords = "صباحا|صباح|الصباح|الصبح|صبحا|فجرا|الفجر|فجر|ظهرا|الظهر|ظهر|بعد الظهر|عصرا|العصر|عصر|مساء|مساءا|المساء|المسا|مسا|مغربا|المغرب|ليلا|الليل|بالليل|بليل|am|pm|ص|م"

        static func period(from word: String?) -> Period? {
            guard let raw = word?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
            let w = raw.lowercased()
            if w == "بعد الظهر" { return .afternoon }
            if w.contains("صب") || w.contains("فجر") || w == "am" || w == "ص" { return .morning }
            if w.contains("ظهر") { return .noon }
            if w.contains("عصر") { return .afternoon }
            if w.contains("ليل") { return .night }
            if w.contains("مس") || w.contains("مغرب") || w == "pm" || w == "م" { return .evening }
            return nil
        }

        static let weekdays: [(String, Int)] = [
            ("احد", 1), ("اثنين", 2), ("اتنين", 2), ("ثلاثاء", 3), ("ثلاثا", 3), ("تلات", 3),
            ("اربعاء", 4), ("اربعا", 4), ("اربع", 4), ("خميس", 5), ("جمعه", 6), ("سبت", 7)
        ]
        static var weekdayPattern: String { weekdays.map(\.0).joined(separator: "|") }
        static func weekday(_ token: String?) -> Int? {
            guard let token else { return nil }
            return weekdays.first { $0.0 == token }?.1
        }

        static let months: [(String, Int)] = [
            ("يناير", 1), ("كانون الثاني", 1), ("فبراير", 2), ("شباط", 2), ("مارس", 3), ("اذار", 3),
            ("ابريل", 4), ("نيسان", 4), ("مايو", 5), ("ايار", 5), ("يونيو", 6), ("حزيران", 6),
            ("يوليو", 7), ("تموز", 7), ("اغسطس", 8), ("اب", 8), ("سبتمبر", 9), ("ايلول", 9),
            ("اكتوبر", 10), ("تشرين الاول", 10), ("نوفمبر", 11), ("تشرين الثاني", 11),
            ("ديسمبر", 12), ("كانون الاول", 12)
        ]
        static var monthPattern: String { months.map(\.0).sorted { $0.count > $1.count }.joined(separator: "|") }

        // MARK: Relative time ("بعد ساعة", "بعد 20 دقيقة")

        mutating func parseRelativeTime() {
            let n = Engine.numberPattern
            var minutes: Int?
            if let g = take(Engine.w("(?:بعد|خلال)\\s*\(n)\\s*(?:دقيقه|دقايق|دقائق|دقيقة)")) {
                minutes = Engine.number(g[1])
            } else if let g = take(Engine.w("(?:بعد|خلال)\\s*(نص|نصف|ربع)\\s*ساعه")) {
                minutes = g[1] == "ربع" ? 15 : 30
            } else if let g = take(Engine.w("(?:بعد|خلال)\\s*(ساعتين|ساعه)")) {
                minutes = g[1] == "ساعتين" ? 120 : 60
            } else if let g = take(Engine.w("(?:بعد|خلال)\\s*\(n)\\s*(?:ساعات|ساعه)")) {
                minutes = Engine.number(g[1]).map { $0 * 60 }
            }
            if let minutes, minutes > 0 {
                relativeDate = calendar.date(byAdding: .minute, value: minutes, to: now)
            }
        }

        // MARK: Clock time

        mutating func parseClockTime() {
            guard relativeDate == nil else { return }
            let n = Engine.numberPattern
            let minutePart = "(?:\\s*[:.]\\s*(\\d{2}))?"
            let fraction = "(?:\\s*(و\\s*(?:نص|النص|نصف|النصف|ربع|الربع|ثلث|الثلث|\\d{1,2}\\s*(?:دقيقه|دقايق|دقائق|د)?)|الا\\s*(?:ربع|الربع|ثلث|الثلث|\\d{1,2}\\s*(?:دقيقه|دقايق|دقائق|د)?)))?"
            let periodPart = "(?:\\s*(?:في\\s*|ب)?(\(Engine.periodWords))(?![\\p{L}]))"

            // 1) "الساعة 10" / "الساعه 3:30 عصرا" / "ساعة عشرة ونص"
            if let g = take("(?<![\\p{L}])(?:ال)?ساعه\\s*\(n)\(minutePart)\(fraction)\(periodPart)?") {
                applyTime(hourToken: g[1], minuteToken: g[2], fraction: g[3], periodWord: g[4])
                return
            }
            // 2) "10 صباحا" / "3:30 م" (period required without the word الساعة)
            if let g = take("(?<![\\p{L}\\p{N}/])\(n)\(minutePart)\(fraction)\(periodPart)") {
                applyTime(hourToken: g[1], minuteToken: g[2], fraction: g[3], periodWord: g[4])
                return
            }
            // 3) "15:30"
            if let g = take("(?<![\\p{N}/])(\\d{1,2}):(\\d{2})(?![\\p{N}])\(periodPart)?") {
                applyTime(hourToken: g[1], minuteToken: g[2], fraction: nil, periodWord: g[3])
            }
        }

        mutating func applyTime(hourToken: String?, minuteToken: String?, fraction: String?, periodWord: String?) {
            guard var h = Engine.number(hourToken) else { return }
            var m = Int(minuteToken ?? "") ?? 0
            if let fraction = fraction?.trimmingCharacters(in: .whitespaces), !fraction.isEmpty {
                let digits = Int(fraction.filter(\.isNumber)) ?? 0
                if fraction.hasPrefix("الا") {
                    let minus = fraction.contains("ربع") ? 15 : (fraction.contains("ثلث") ? 20 : digits)
                    h = h == 0 ? 23 : h - 1
                    m = 60 - minus
                } else if fraction.contains("نص") {
                    m = 30
                } else if fraction.contains("ربع") {
                    m = 15
                } else if fraction.contains("ثلث") {
                    m = 20
                } else {
                    m = digits
                }
            }
            guard (0...24).contains(h), (0...59).contains(m) else {
                issues.append("الوقت المذكور غير صالح، حدّده يدوياً.")
                return
            }
            hour = h == 24 ? 0 : h
            minute = m
            period = Engine.period(from: periodWord)
        }

        mutating func parseStandalonePeriod() {
            if let g = take(Engine.w("الليله|الليلة")) {
                _ = g
                if dayOffset == nil && explicitDay == nil && weekdayTarget == nil { dayOffset = 0 }
                if period == nil { period = .evening }
            }
            guard period == nil else { return }
            let words = "الصبح|الصباح|صباحا|الفجر|فجرا|الظهر|ظهرا|بعد الظهر|العصر|عصرا|المغرب|المساء|مساء|بالليل|ليلا"
            if let g = take(Engine.w(words)) {
                period = Engine.period(from: g[0])
                if hour == nil {
                    // Named part of day without a clock time: approximate, must be confirmed.
                    switch period {
                    case .morning?: hour = g[0]?.contains("فجر") == true ? 5 : 9
                    case .noon?: hour = 12
                    case .afternoon?: hour = 15; minute = 30
                    case .evening?: hour = g[0]?.contains("مغرب") == true ? 18 : 19
                    case .night?: hour = 21
                    case nil: break
                    }
                    timeIsApproximate = true
                }
            }
        }

        // MARK: Reminder offsets ("قبلها بساعة")

        mutating func parseReminderOffsets() {
            let before = "قبل(?:ها|ه|الموعد|\\s*الموعد)?\\s*(?:ب)?\\s*"
            var found = true
            while found {
                found = false
                if let g = take(Engine.w(before + "(\\d{1,4})\\s*(?:دقيقه|دقايق|دقائق|د)")) {
                    addOffset(Int(g[1] ?? "") ?? 0); found = true
                } else if take(Engine.w(before + "(?:ربع|الربع)\\s*ساعه")) != nil {
                    addOffset(15); found = true
                } else if take(Engine.w(before + "(?:نص|نصف)\\s*ساعه")) != nil {
                    addOffset(30); found = true
                } else if take(Engine.w(before + "(?:ساعه|بساعه)")) != nil {
                    addOffset(60); found = true
                } else if take(Engine.w(before + "(?:يوم|بيوم)")) != nil {
                    addOffset(1440); found = true
                }
            }
        }

        mutating func addOffset(_ minutes: Int) {
            let allowed = ReminderOption.all
            if allowed.contains(minutes) {
                reminderOffsets.append(minutes)
            } else if let nearest = allowed.min(by: { abs($0 - minutes) < abs($1 - minutes) }) {
                reminderOffsets.append(nearest)
                hints.append("تم تقريب التذكير إلى \(AppFormat.reminderLabel(nearest)).")
            }
        }

        // MARK: Recurrence

        mutating func parseRecurrence() {
            let wd = Engine.weekdayPattern
            if let g = take(Engine.w("كل\\s*(?:يوم\\s*)?(?:ال)?(\(wd))")) {
                recurrence = .weekly
                weekdayTarget = Engine.weekday(g[1])
            } else if let g = take(Engine.w("(?:يوم\\s*)?(\\d{1,2})\\s*من\\s*كل\\s*شهر")) {
                recurrence = .monthly
                monthlyDay = Int(g[1] ?? "")
            } else if let g = take(Engine.w("كل\\s*شهر\\s*(?:يوم|في)\\s*(\\d{1,2})")) {
                recurrence = .monthly
                monthlyDay = Int(g[1] ?? "")
            } else if take(Engine.w("كل\\s*يوم|يوميا|كل\\s*صباح|كل\\s*ليله")) != nil {
                recurrence = .daily
            } else if take(Engine.w("كل\\s*اسبوع|اسبوعيا")) != nil {
                recurrence = .weekly
            } else if take(Engine.w("كل\\s*شهر|شهريا")) != nil {
                recurrence = .monthly
            }
            if let day = monthlyDay, !(1...31).contains(day) {
                monthlyDay = nil
                issues.append("يوم الشهر غير صالح، حدّده يدوياً.")
            }
        }

        // MARK: Dates

        mutating func parseDates() {
            let n = Engine.numberPattern
            let wd = Engine.weekdayPattern
            let nextWords = "الجاي|الجايه|القادم|القادمه|المقبل|المقبله|اللي\\s*جاي"

            if take(Engine.w("بعد\\s*(?:بكره|بكرا|بكرة|غد|الغد|بكره)")) != nil {
                dayOffset = 2
            } else if take(Engine.w("بكره|بكرا|غدا|الغد|غدوه")) != nil {
                dayOffset = 1
            } else if take(Engine.w("اليوم|النهارده|النهارد|انهارده|هاليوم")) != nil {
                dayOffset = 0
            }

            if dayOffset == nil, let g = take(Engine.w("بعد\\s*(?:(يومين|اسبوعين|شهرين)|\(n)\\s*(يوم|ايام|اسبوع|اسابيع|شهر|شهور|اشهر)|(يوم|اسبوع|شهر))")) {
                if let pair = g[1] {
                    switch pair {
                    case "يومين": dayOffset = 2
                    case "اسبوعين": dayOffset = 14
                    default: relativeMonths(2)
                    }
                } else if let unit = g[3], let count = Engine.number(g[2]) {
                    if unit.hasPrefix("يوم") || unit == "ايام" { dayOffset = count }
                    else if unit.contains("اسب") { dayOffset = count * 7 }
                    else { relativeMonths(count) }
                } else if let single = g[4] {
                    if single == "يوم" { dayOffset = 1 } else if single == "اسبوع" { dayOffset = 7 } else { relativeMonths(1) }
                }
            }

            if weekdayTarget == nil, let g = take(Engine.w("(?:يوم\\s*(?:ال)?|ال)(\(wd))(?:\\s*(?:\(nextWords)))?")) {
                weekdayTarget = Engine.weekday(g[1])
            }

            if explicitDay == nil, let g = take("(?<![\\p{N}:.])(\\d{1,2})\\s*[/\\-]\\s*(\\d{1,2})(?:\\s*[/\\-]\\s*(\\d{2,4}))?(?![\\p{N}:])") {
                setExplicit(day: Int(g[1] ?? ""), month: Int(g[2] ?? ""), year: Int(g[3] ?? ""))
            }

            if explicitDay == nil, let g = take(Engine.w("(?:يوم\\s*)?(\\d{1,2})\\s*(?:من\\s*)?(?:شهر\\s*)?(\(Engine.monthPattern))(?:\\s*(\\d{4}))?")) {
                let month = Engine.months.first { $0.0 == g[2] }?.1
                setExplicit(day: Int(g[1] ?? ""), month: month, year: Int(g[3] ?? ""))
            }

            let monthModifier = "هذا\\s*الشهر|الشهر\\s*(?:\(nextWords))|الشهر|شهر"
            var dayMatch: [String?]?
            if explicitDay == nil {
                dayMatch = take(Engine.w("يوم\\s*(\\d{1,2})(?:\\s*من\\s*(\(monthModifier)))?"))
                if dayMatch == nil {
                    dayMatch = take(Engine.w("(\\d{1,2})\\s*من\\s*(\(monthModifier))"))
                }
            }
            if let g = dayMatch {
                let day = Int(g[1] ?? "")
                let modifier = (g[2] ?? "").trimmingCharacters(in: .whitespaces)
                let forceNext = modifier.contains("الشهر") && modifier != "الشهر" && !modifier.contains("هذا")
                dayOfMonth(day, forceNextMonth: forceNext)
                if (modifier == "الشهر" || modifier == "شهر") && recurrence == .none {
                    hints.append("إذا كانت المهمة تتكرر كل شهر، اختر «شهرياً» من التكرار.")
                }
            }

            if take(Engine.w("(?:اخر|نهايه)\\s*(?:هذا\\s*)?الشهر")) != nil {
                let monthStart = RecurrenceEngine.startOfMonth(now, calendar)
                let count = calendar.range(of: .day, in: .month, for: now)?.count ?? 28
                if let last = calendar.date(byAdding: .day, value: count - 1, to: monthStart) {
                    explicitDay = calendar.dateComponents([.year, .month, .day], from: last)
                }
            }

            if take(Engine.w("(?:الاسبوع|الاسبوع)\\s*(?:\(nextWords))")) != nil {
                if weekdayTarget == nil && dayOffset == nil && explicitDay == nil {
                    dayOffset = 7
                    issues.append("حدّد يوم المهمة في الأسبوع القادم.")
                } else {
                    nextWeekRequested = true
                }
            }

            if take(Engine.w("الشهر\\s*(?:\(nextWords))")) != nil, explicitDay == nil, dayOffset == nil, weekdayTarget == nil {
                relativeMonths(1)
                issues.append("حدّد يوم المهمة في الشهر القادم.")
            }
        }

        mutating func relativeMonths(_ count: Int) {
            if let date = calendar.date(byAdding: .month, value: count, to: now) {
                explicitDay = calendar.dateComponents([.year, .month, .day], from: date)
            }
        }

        mutating func setExplicit(day: Int?, month: Int?, year: Int?) {
            guard let day, let month, (1...31).contains(day), (1...12).contains(month) else {
                issues.append("لم أفهم التاريخ المكتوب، حدّده يدوياً.")
                return
            }
            var components = DateComponents()
            components.day = day
            components.month = month
            if let year {
                components.year = year < 100 ? 2000 + year : year
            } else {
                // Without a year: this year, or next year if the date has passed.
                let thisYear = calendar.component(.year, from: now)
                components.year = thisYear
                if let candidate = calendar.date(from: components), calendar.startOfDay(for: candidate) < calendar.startOfDay(for: now) {
                    components.year = thisYear + 1
                }
            }
            guard let date = calendar.date(from: components),
                  calendar.component(.day, from: date) == day else {
                issues.append("هذا التاريخ غير موجود في التقويم، حدّده يدوياً.")
                return
            }
            explicitDay = calendar.dateComponents([.year, .month, .day], from: date)
        }

        mutating func dayOfMonth(_ day: Int?, forceNextMonth: Bool) {
            guard let day, (1...31).contains(day) else {
                issues.append("يوم الشهر غير صالح، حدّده يدوياً.")
                return
            }
            if recurrence == .monthly && monthlyDay == nil { monthlyDay = day }
            var month = RecurrenceEngine.startOfMonth(now, calendar)
            if forceNextMonth, let next = calendar.date(byAdding: .month, value: 1, to: month) { month = next }
            // Find the first month (from this one) that contains that day and is not in the past.
            for _ in 0..<13 {
                let count = calendar.range(of: .day, in: .month, for: month)?.count ?? 28
                if day <= count {
                    var c = calendar.dateComponents([.year, .month], from: month)
                    c.day = day
                    if let candidate = calendar.date(from: c), candidate >= calendar.startOfDay(for: now) {
                        explicitDay = calendar.dateComponents([.year, .month, .day], from: candidate)
                        return
                    }
                }
                guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { break }
                month = next
            }
        }

        // MARK: Title

        mutating func removeCommandWords() {
            let polite = "^\\s*(?:من\\s*فضلك|لو\\s*سمحت|ممكن|رجاء|رجاءا)\\s*"
            let remind = "^\\s*(?:ذكرني|ذكريني|ذكرنا|فكرني|فكريني|نبهني|نبهيني|ذكرنى)(?![\\p{L}])\\s*(?:ب(?=\\p{L})|ان\\s+|اني\\s+|انه\\s+|عشان\\s+|علشان\\s+|ب\\s+)?"
            let add = "^\\s*(?:اضف|اضيف|ضيف|ضيفي|سجل|سجلي|اكتب|انشئ|حط|ضع)(?![\\p{L}])\\s*(?:لي\\s*)?(?:مهمه\\s*(?:جديده)?)?\\s*:?\\s*"
            let task = "^\\s*(?:مهمه\\s*جديده|مهمه)(?![\\p{L}])\\s*:?\\s*"
            let want = "^\\s*(?:عندي|لدي|لازم|يجب|ابغى|ابغي|ابي|بدي|عايز|عاوز|محتاج|احتاج|اريد|اود)(?![\\p{L}])\\s*(?:ان\\s+|اني\\s+)?"
            for _ in 0..<4 {
                var changed = false
                if take(polite) != nil { changed = true }
                if take(remind) != nil { hasReminderVerb = true; changed = true }
                if take(add) != nil { changed = true }
                if take(task) != nil { changed = true }
                if take(want) != nil { changed = true }
                if !changed { break }
            }
            // A reminder verb in the middle of the sentence ("بكرة الساعة 10 ذكرني بالاجتماع").
            if take(Engine.w("ذكرني|فكرني|نبهني") + "\\s*(?:ب(?=\\p{L}))?") != nil { hasReminderVerb = true }
        }

        func buildTitle() -> String {
            var words = (base as String).split(whereSeparator: { $0.isWhitespace }).map(String.init)
            let edge: Set<String> = ["في", "يوم", "على", "علي", "الساعه", "الساعة", "و", "من", "عند", "بتاريخ",
                                     "تاريخ", "ب", "الى", "إلى", "ل", "مع", "،", ",", "-", ":"]
            func normalized(_ s: String) -> String {
                Engine.normalizeLetters(s).trimmingCharacters(in: .punctuationCharacters)
            }
            while let first = words.first, edge.contains(normalized(first)) || normalized(first).isEmpty { words.removeFirst() }
            while let last = words.last, edge.contains(normalized(last)) || normalized(last).isEmpty { words.removeLast() }
            let title = words.joined(separator: " ")
            return title.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        }

        // MARK: Resolve

        mutating func resolveDate() -> (Date, Bool, Bool) {
            if let relativeDate { return (relativeDate, true, true) }

            var day: Date?
            if let explicitDay, let date = calendar.date(from: explicitDay) {
                day = date
            } else if let weekdayTarget {
                let today = calendar.component(.weekday, from: now)
                var delta = (weekdayTarget - today + 7) % 7
                if delta == 0 {
                    // Same weekday: today only if a later time today was given.
                    if let h = finalHour(), let candidate = calendar.date(bySettingHour: h, minute: minute, second: 0, of: now), candidate > now {
                        delta = 0
                    } else {
                        delta = 7
                    }
                }
                if nextWeekRequested && delta < 7 { delta += 7 }
                day = calendar.date(byAdding: .day, value: delta, to: calendar.startOfDay(for: now))
            } else if let dayOffset {
                day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now))
            } else if recurrence == .monthly, let monthlyDay {
                dayOfMonth(monthlyDay, forceNextMonth: false)
                if let explicitDay { day = calendar.date(from: explicitDay) }
            }

            let h = finalHour()

            if let h {
                if (hour ?? 0) >= 1 && (hour ?? 0) <= 11 && period == nil {
                    issues.append("حدّد إن كان الوقت صباحاً أم مساءً.")
                }
                if timeIsApproximate {
                    issues.append("الوقت تقريبي، حدّده بدقة.")
                }
                let baseDay = day ?? calendar.startOfDay(for: now)
                var date = calendar.date(bySettingHour: h, minute: minute, second: 0, of: baseDay) ?? baseDay
                if day == nil && date <= now {
                    // Time only: the next time it occurs.
                    date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
                }
                return (date, true, true)
            }

            // No time given.
            if let day {
                issues.append("لم تحدد وقتاً؛ اقترحت وقتاً افتراضياً، راجعه.")
                var date = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
                if date <= now { date = TaskDraft.suggestedDueDate(now: now, calendar: calendar) }
                return (date, true, false)
            }

            if recurrence != .none {
                issues.append("لم تحدد وقتاً؛ اقترحت وقتاً افتراضياً، راجعه.")
                return (TaskDraft.suggestedDueDate(now: now, calendar: calendar), true, false)
            }

            issues.append("لم أفهم موعد المهمة؛ حدّد التاريخ والوقت.")
            return (TaskDraft.suggestedDueDate(now: now, calendar: calendar), false, false)
        }

        /// 24h hour after applying the period, or the heuristic when no period was said.
        func finalHour() -> Int? {
            guard let h = hour else { return nil }
            switch period {
            case .morning?:
                return h == 12 ? 0 : h
            case .noon?:
                if h == 12 || h == 11 { return h }
                return h < 12 ? h + 12 : h
            case .afternoon?, .evening?:
                return h < 12 ? h + 12 : h
            case .night?:
                if h == 12 { return 0 }
                if h <= 4 { return h }
                return h < 12 ? h + 12 : h
            case nil:
                if h == 0 || h >= 12 { return h }
                // Heuristic for "الساعة 3": 1–6 → afternoon/evening, 7–11 → morning (flagged for review).
                return h <= 6 ? h + 12 : h
            }
        }

        // MARK: Text normalization

        static func clean(_ text: String) -> String {
            var scalars = String.UnicodeScalarView()
            for scalar in text.unicodeScalars {
                switch scalar.value {
                case 0x064B...0x0652, 0x0670, 0x0640: // tashkeel, superscript alef, tatweel
                    continue
                case 0x0660...0x0669: // Arabic-Indic digits
                    scalars.append(UnicodeScalar(scalar.value - 0x0660 + 0x30)!)
                case 0x06F0...0x06F9: // Extended Arabic-Indic digits
                    scalars.append(UnicodeScalar(scalar.value - 0x06F0 + 0x30)!)
                case 0x060C: // Arabic comma
                    scalars.append(",")
                default:
                    scalars.append(scalar)
                }
            }
            return String(scalars)
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        /// One-to-one letter mapping (keeps UTF-16 length identical to the input).
        static func normalizeLetters(_ text: String) -> String {
            var scalars = String.UnicodeScalarView()
            for scalar in text.unicodeScalars {
                switch scalar {
                case "أ", "إ", "آ", "ٱ": scalars.append("ا")
                case "ى": scalars.append("ي")
                case "ة": scalars.append("ه")
                case "ؤ": scalars.append("و")
                case "ئ": scalars.append("ي")
                default:
                    if (65...90).contains(scalar.value), let lower = UnicodeScalar(scalar.value + 32) {
                        scalars.append(lower) // ASCII only, keeps UTF-16 length unchanged
                    } else {
                        scalars.append(scalar)
                    }
                }
            }
            return String(scalars)
        }
    }
}
