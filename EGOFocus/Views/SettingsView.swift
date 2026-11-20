import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKey.appearance) private var appearance = "system"
    @AppStorage(SettingsKey.remindersEnabled) private var remindersEnabled = true
    @AppStorage(SettingsKey.defaultReminder) private var defaultReminder = 0
    @AppStorage(SettingsKey.dailyBriefEnabled) private var dailyBriefEnabled = false
    @AppStorage(SettingsKey.dailyBriefHour) private var dailyBriefHour = 8
    @AppStorage(SettingsKey.dailyBriefMinute) private var dailyBriefMinute = 0

    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var scheduledCount = 0
    @State private var message: String?

    private var briefTime: Binding<Date> {
        Binding(
            get: {
                AppCalendar.calendar.date(bySettingHour: dailyBriefHour, minute: dailyBriefMinute, second: 0, of: .now) ?? .now
            },
            set: { date in
                let c = AppCalendar.calendar.dateComponents([.hour, .minute], from: date)
                dailyBriefHour = c.hour ?? 8
                dailyBriefMinute = c.minute ?? 0
                NotificationService.shared.scheduleDailyBrief()
            })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("المظهر") {
                    Picker("المظهر", selection: $appearance) {
                        Text("حسب النظام").tag("system")
                        Text("فاتح").tag("light")
                        Text("داكن").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("settings.appearance")
                }

                notificationsSection

                Section {
                    Toggle("الملخص الصباحي اليومي", isOn: $dailyBriefEnabled)
                        .onChange(of: dailyBriefEnabled) { _, _ in NotificationService.shared.scheduleDailyBrief() }
                        .accessibilityIdentifier("settings.dailyBrief")
                    if dailyBriefEnabled {
                        DatePicker("وقت التذكير الصباحي", selection: briefTime, displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("التذكير الصباحي")
                } footer: {
                    Text("تنبيه يومي ثابت في الوقت الذي تختاره ليذكّرك بمراجعة مهام اليوم.")
                }

                Section("البيانات والخصوصية") {
                    NavigationLink {
                        PrivacyView()
                    } label: {
                        Label("بيان الخصوصية", systemImage: "lock.shield")
                    }
                    LabeledContent("مكان التخزين", value: "على هذا الآيفون فقط")
                    LabeledContent("المهام المحفوظة", value: "\(store.tasks.count)")
                }

                Section("حول التطبيق") {
                    HStack(spacing: 14) {
                        Image(systemName: "scope")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(Brand.heroGradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("EGO FOCUS").font(.headline)
                            Text("إيجو فوكس").font(.subheadline).foregroundStyle(.secondary)
                            Text("ركّز على ما يهمك.").font(.footnote).foregroundStyle(Brand.accent)
                        }
                    }
                    .padding(.vertical, 4)
                    LabeledContent("الإصدار", value: appVersion)
                    LabeledContent("المنصة", value: "iPhone — iOS 17 أو أحدث")
                }
            }
            .navigationTitle("الإعدادات")
            .task { await refreshStatus() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await refreshStatus() } }
            }
        }
    }

    private var notificationsSection: some View {
        Section {
            LabeledContent("حالة الإشعارات", value: statusText)
                .accessibilityIdentifier("settings.notificationStatus")
            if status == .notDetermined {
                Button {
                    Task {
                        let granted = await NotificationService.shared.requestPermission()
                        message = granted ? "تم السماح بالإشعارات." : "لم يتم منح الإذن."
                        store.syncNotifications()
                        await refreshStatus()
                    }
                } label: { Label("السماح بالإشعارات", systemImage: "bell.badge") }
            } else if status == .denied {
                Button {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: { Label("فتح إعدادات الإشعارات", systemImage: "gear") }
            }
            Toggle("تذكيرات المهام", isOn: $remindersEnabled)
                .onChange(of: remindersEnabled) { _, _ in
                    store.syncNotifications()
                    Task { try? await Task.sleep(nanoseconds: 600_000_000); await refreshStatus() }
                }
                .accessibilityIdentifier("settings.remindersEnabled")
            Picker("التذكير الافتراضي للمهام الجديدة", selection: $defaultReminder) {
                Text("بدون تذكير").tag(-1)
                ForEach(ReminderOption.all, id: \.self) { Text(AppFormat.reminderLabel($0)).tag($0) }
            }
            .disabled(!remindersEnabled)
            LabeledContent("تذكيرات مجدولة الآن") {
                Text("\(scheduledCount)")
                    .monospacedDigit()
                    .accessibilityIdentifier("settings.scheduledCountValue")
            }
            if status == .authorized || status == .provisional {
                Button {
                    NotificationService.shared.sendTestNotification()
                    message = "سيصلك تنبيه تجريبي خلال 5 ثوانٍ."
                } label: { Label("إرسال تنبيه تجريبي", systemImage: "paperplane") }
            }
            if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
        } header: {
            Text("التنبيهات")
        } footer: {
            Text("التنبيهات محلية ويجدولها iOS. قد يؤخر وضع التركيز أو الملخص المجدول أو إعدادات الإشعارات ظهورها، ولا يضمن iOS تشغيل التطبيق في الخلفية.")
        }
    }

    private var statusText: String {
        switch status {
        case .authorized: return "مفعّلة"
        case .provisional, .ephemeral: return "مفعّلة مؤقتاً"
        case .denied: return "مرفوضة"
        case .notDetermined: return "لم يُطلب الإذن"
        @unknown default: return "غير معروفة"
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func refreshStatus() async {
        status = await NotificationService.shared.currentAuthorizationStatus()
        try? await Task.sleep(nanoseconds: 300_000_000)
        scheduledCount = await NotificationService.shared.pendingTaskReminderCount()
    }
}

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Brand.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                Text("بياناتك على جهازك")
                    .font(.title2.weight(.bold))
                    .frame(maxWidth: .infinity)
                point("internaldrive", "تخزين محلي فقط",
                      "جميع المهام والتصنيفات والملاحظات وسجل الإنجاز والإعدادات محفوظة في قاعدة بيانات SwiftData على هذا الآيفون. لا يوجد خادم ولا مزامنة سحابية ولا قاعدة بيانات خارجية.")
                point("person.crop.circle.badge.xmark", "بدون حساب",
                      "لا يتطلب التطبيق تسجيلاً أو تسجيل دخول، ولا يجمع اسمك أو بريدك أو أي بيانات شخصية.")
                point("chart.bar.xaxis", "بدون تتبع أو تحليلات",
                      "لا يحتوي التطبيق على أدوات تتبع أو إعلانات أو تحليلات، ولا يرسل طلبات شبكة من تلقاء نفسه.")
                point("text.bubble", "المساعد الذكي محلي",
                      "تحليل الأوامر العربية المكتوبة يتم على الجهاز بقواعد محلية، دون أي خدمة ذكاء اصطناعي خارجية.")
                point("mic", "الإملاء الصوتي",
                      "يستخدم الإملاء خدمة التعرف على الكلام من Apple. إذا كان جهازك يدعم التعرف على العربية دون اتصال يطلب التطبيق المعالجة على الجهاز؛ وإلا فقد تعالج Apple الصوت عبر خوادمها وفق سياسة خصوصيتها. لا يحتفظ التطبيق بالتسجيلات الصوتية.")
                point("bell", "التنبيهات",
                      "التذكيرات إشعارات محلية يجدولها نظام iOS على جهازك.")
                point("trash", "الحذف",
                      "حذف مهمة يزيلها مع تذكيراتها وسجل إنجازها. حذف التطبيق يزيل جميع بياناته من الجهاز نهائياً، ولا توجد نسخة على أي خادم.")
            }
            .padding(18)
        }
        .background(Brand.canvas.ignoresSafeArea())
        .navigationTitle("الخصوصية")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func point(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(Brand.accent)
                .frame(width: 34, height: 34)
                .background(Brand.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card(padding: 14)
    }
}
