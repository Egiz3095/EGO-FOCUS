import SwiftUI

struct AssistantView: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = SpeechInputManager()

    @State private var command = ""
    @State private var parsed: ParsedTask?
    @State private var draft = TaskDraft(dueDate: .now)
    @State private var confirmed = false
    @State private var analyzedCommand = ""
    @FocusState private var inputFocused: Bool

    private let examples = [
        "ذكرني بمراجعة الفواتير بكرة الساعة 10 صباحاً",
        "أضف مهمة شراء مستلزمات المكتب يوم الأحد",
        "عندي اجتماع غداً الساعة 3 عصراً",
        "ذكرني بدفع الإيجار يوم 1 من الشهر"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("اكتب المهمة أو قلها كما تفكر بها، وسأجهزها لك للمراجعة قبل الحفظ.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    inputCard
                    if parsed == nil { examplesCard }
                    if let parsed { previewCard(parsed) }
                    privacyNote
                }
                .padding(18)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Brand.canvas.ignoresSafeArea())
            .navigationTitle("المساعد الذكي")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إغلاق") { speech.cancel(); dismiss() }
                }
            }
            .onChange(of: speech.transcript) { _, value in
                if !value.isEmpty { command = value }
            }
            .onDisappear { speech.cancel() }
        }
    }

    // MARK: Input

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("مثال: ذكرني بالاجتماع بكرة الساعة 9 صباحاً", text: $command, axis: .vertical)
                .lineLimit(2...5)
                .focused($inputFocused)
                .padding(12)
                .background(Brand.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier("assistant.input")
                .onChange(of: command) { _, value in
                    // Editing the command invalidates an older preview (not the one just produced).
                    if !speech.isRecording && value != analyzedCommand { parsed = nil }
                }

            HStack(spacing: 12) {
                Button {
                    inputFocused = false
                    Task { await speech.toggle() }
                } label: {
                    Label(speech.isRecording ? "إيقاف" : "تحدّث",
                          systemImage: speech.isRecording ? "stop.fill" : "mic.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(speech.isRecording ? .red : Brand.accent)
                .disabled(speech.isStarting)
                .accessibilityIdentifier("assistant.mic")

                if speech.isRecording {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform")
                            .foregroundStyle(.red)
                            .symbolEffect(.variableColor.iterative, isActive: true)
                        Text("جارٍ الاستماع…").font(.footnote).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                Spacer()
                Button("تحليل الأمر", action: analyze)
                    .font(.subheadline.weight(.bold))
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || speech.isRecording)
                    .accessibilityIdentifier("assistant.analyze")
            }

            if speech.isRecording || (!speech.transcript.isEmpty && parsed == nil) {
                Text("راجع النص المسموع وعدّله إن لزم قبل التحليل.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = speech.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }

    private var examplesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("جرّب مثلاً").font(.headline)
            ForEach(examples, id: \.self) { example in
                Button {
                    command = example
                    analyze()
                } label: {
                    HStack {
                        Image(systemName: "text.bubble").foregroundStyle(Brand.accent)
                        Text(example)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(Brand.canvas, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }

    // MARK: Preview

    private func previewCard(_ result: ParsedTask) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("معاينة المهمة").font(.headline)
                Spacer()
                if result.needsClarification {
                    Label("تحتاج تأكيد", systemImage: "questionmark.circle")
                        .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                } else {
                    Label("مفهومة", systemImage: "checkmark.seal")
                        .font(.caption.weight(.semibold)).foregroundStyle(Brand.accent)
                }
            }

            if !result.issues.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(result.issues, id: \.self) { issue in
                        Label(issue, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("العنوان").font(.caption).foregroundStyle(.secondary)
                TextField("عنوان المهمة", text: $draft.title)
                    .font(.body.weight(.semibold))
                    .padding(10)
                    .background(Brand.canvas, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityIdentifier("assistant.previewTitle")
            }

            DatePicker("الموعد", selection: $draft.dueDate, displayedComponents: [.date, .hourAndMinute])
                .accessibilityIdentifier("assistant.previewDate")

            Picker("التكرار", selection: $draft.recurrence) {
                ForEach(TaskRecurrence.allCases) { Text($0.rawValue).tag($0) }
            }

            Picker("التذكير", selection: reminderBinding) {
                Text("بدون تذكير").tag(-1)
                ForEach(ReminderOption.all, id: \.self) { Text(AppFormat.reminderLabel($0)).tag($0) }
            }

            ForEach(result.hints, id: \.self) { hint in
                Label(hint, systemImage: "lightbulb")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if result.needsClarification {
                Toggle("راجعتُ الموعد والعنوان وهما صحيحان", isOn: $confirmed)
                    .font(.subheadline)
                    .accessibilityIdentifier("assistant.confirm")
            }

            Button {
                store.add(draft)
                speech.cancel()
                dismiss()
            } label: {
                Label("إضافة المهمة", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSave(result))
            .accessibilityIdentifier("assistant.save")
        }
        .card()
    }

    private var reminderBinding: Binding<Int> {
        Binding(get: { draft.reminderOffsets.first ?? -1 },
                set: { draft.reminderOffsets = $0 < 0 ? [] : [$0] })
    }

    private var privacyNote: some View {
        Label("تحليل النص يتم على جهازك دون أي خدمة خارجية. الإملاء الصوتي يستخدم خدمة Apple للتعرف على الكلام\(speech.supportsOnDevice ? " على الجهاز" : "، وقد يتطلب اتصالاً بالإنترنت على بعض الأجهزة").",
              systemImage: "lock.shield")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func canSave(_ result: ParsedTask) -> Bool {
        draft.isValid && (!result.needsClarification || confirmed)
    }

    private func analyze() {
        if speech.isRecording { speech.stop() }
        inputFocused = false
        let result = NaturalLanguageTaskParser.parse(command, now: store.now,
                                                     defaultReminderOffsets: SettingsKey.defaultReminderOffsets)
        var newDraft = TaskDraft(dueDate: result.date, reminderOffsets: result.reminderOffsets)
        newDraft.title = result.title
        newDraft.recurrence = result.recurrence
        draft = newDraft
        confirmed = false
        analyzedCommand = command
        withAnimation(.snappy) { parsed = result }
    }
}
