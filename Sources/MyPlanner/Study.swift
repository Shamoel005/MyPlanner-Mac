import SwiftUI
import AppKit

func hm(_ minutes: Int) -> String {
    if minutes < 60 { return "\(minutes)m" }
    return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
}

// MARK: - Study model

struct Topic: Identifiable, Codable, Equatable {
    var id: Int64
    var title: String
    var done: Bool = false
    var studiedAt: Int64 = 0
    var revised: Bool = false
}

struct Subject: Identifiable, Codable, Equatable {
    var id: Int64
    var name: String
    var topics: [Topic] = []
}

struct Session: Identifiable, Codable, Equatable {
    var id: Int64
    var subject: String
    var minutes: Int
    var date: Int64
}

struct Exam: Identifiable, Codable, Equatable {
    var id: Int64
    var name: String
    var date: Int64
    var daysLeft: Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: dateOf(date))).day ?? 0
    }
}

struct Mock: Identifiable, Codable, Equatable {
    var id: Int64
    var name: String
    var score: Double
    var total: Double
    var date: Int64
    var percent: Double { total > 0 ? score / total * 100 : 0 }
}

struct StudyData: Codable {
    var subjects: [Subject] = []
    var sessions: [Session] = []
    var exams: [Exam] = []
    var mocks: [Mock] = []
    var dailyMinutes: Int = 240

    func minutes(onOffset o: Int) -> Int {
        let cal = Calendar.current
        let d = cal.date(byAdding: .day, value: o, to: Date()) ?? Date()
        let s = msOf(cal.startOfDay(for: d))
        let e = endOfDayMs(d)
        return sessions.filter { $0.date >= s && $0.date <= e }.reduce(0) { $0 + $1.minutes }
    }

    func streak() -> Int {
        guard dailyMinutes > 0 else { return 0 }
        var o = minutes(onOffset: 0) >= dailyMinutes ? 0 : -1
        var n = 0
        while n < 366 && minutes(onOffset: o) >= dailyMinutes { n += 1; o -= 1 }
        return n
    }
}

final class StudyStore: ObservableObject {
    @Published var data = StudyData() { didSet { save() } }
    private let url = supportURL("study.json")

    init() {
        if let d = try? Data(contentsOf: url), let v = try? JSONDecoder().decode(StudyData.self, from: d) { data = v }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(data) { try? d.write(to: url, options: .atomic) }
    }

    var nextExam: Exam? {
        data.exams.filter { $0.daysLeft >= 0 }.min { $0.date < $1.date }
    }

    func mutateSubject(_ id: Int64, _ change: (inout Subject) -> Void) {
        if let i = data.subjects.firstIndex(where: { $0.id == id }) {
            var s = data.subjects[i]
            change(&s)
            data.subjects[i] = s
        }
    }
}

// MARK: - Focus timer model

final class FocusModel: ObservableObject {
    @Published var mode = 0          // 0 = timer, 1 = stopwatch
    @Published var total = 25 * 60
    @Published var left = 25 * 60
    @Published var elapsed = 0
    @Published var running = false
    @Published var subject = "General"
    @Published var message = ""
    var logger: ((String, Int) -> Void)?
    private var timer: Timer?

    func toggle() {
        if running { stop(); return }
        if mode == 0 && left <= 0 { left = total; elapsed = 0 }
        message = ""
        running = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }

    func stop() { running = false; timer?.invalidate(); timer = nil }
    func reset() { stop(); elapsed = 0; left = total }
    func setMinutes(_ m: Int) { stop(); total = max(1, m) * 60; left = total; elapsed = 0; mode = 0 }
    func setMode(_ m: Int) { stop(); mode = m; elapsed = 0; left = total }

    func logAndReset() {
        let m = elapsed / 60
        if m >= 1 {
            logger?(subject, m)
            message = "Logged \(hm(m)) to \(subject)"
        } else {
            message = "Nothing to log yet (under 1 minute)"
        }
        stop()
        elapsed = 0
        left = total
    }

    private func tick() {
        elapsed += 1
        if mode == 0 {
            left = max(0, left - 1)
            if left == 0 { NSSound.beep(); logAndReset() }
        }
    }
}

// MARK: - Focus screen

struct FocusView: View {
    @EnvironmentObject var focus: FocusModel
    @EnvironmentObject var study: StudyStore
    @Environment(\.tintC) var tintC
    @State private var hText = ""
    @State private var mText = ""

    var subjects: [String] { ["General"] + study.data.subjects.map { $0.name } }

    func clock(_ s: Int) -> String {
        s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60)
    }

    var body: some View {
        let shown = focus.mode == 0 ? focus.left : focus.elapsed
        Page {
            HStack(spacing: 6) {
                PillButton(text: "Timer", selected: focus.mode == 0) { focus.setMode(0) }
                PillButton(text: "Stopwatch", selected: focus.mode == 1) { focus.setMode(1) }
                Spacer()
            }
            VStack(spacing: 12) {
                Text(clock(shown))
                    .font(.system(size: 62, weight: .thin, design: .rounded))
                    .monospacedDigit()
                if focus.mode == 0 {
                    ProgressView(value: 1 - Double(focus.left) / Double(max(focus.total, 1))).tint(tintC).padding(.horizontal, 24)
                } else {
                    Text(focus.running ? "Counting up…" : "Start when you sit down to study").font(.system(size: 12)).foregroundStyle(Color.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)

            if focus.mode == 0 {
                RowCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Set the time").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach([15, 25, 45, 60, 90, 120, 180], id: \.self) { m in
                                    PillButton(text: hm(m), selected: focus.total == m * 60) { focus.setMinutes(m) }
                                }
                            }
                        }
                        HStack(spacing: 8) {
                            FieldBox { TextField("hours", text: $hText) }.frame(width: 90)
                            FieldBox { TextField("minutes", text: $mText) }.frame(width: 90)
                            Button("Set") {
                                let h = Int(hText.trimmingCharacters(in: .whitespaces)) ?? 0
                                let m = Int(mText.trimmingCharacters(in: .whitespaces)) ?? 0
                                if h * 60 + m > 0 { focus.setMinutes(h * 60 + m); hText = ""; mText = "" }
                            }
                            .keyboardShortcut(.defaultAction)
                            Spacer()
                        }
                        Text("Any length works, for example 2 hours 30 minutes.").font(.system(size: 10.5)).foregroundStyle(Color.secondary)
                    }
                }
            }

            RowCard {
                HStack {
                    Image(systemName: "book.closed.fill").foregroundStyle(tintC)
                    Text("Studying").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Picker("", selection: $focus.subject) {
                        ForEach(subjects, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden().frame(width: 170)
                }
            }

            HStack(spacing: 10) {
                Button { focus.toggle() } label: {
                    Text(focus.running ? "Pause" : "Start")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 10).background(Capsule().fill(tintC))
                }
                .buttonStyle(.plain)
                Button { focus.logAndReset() } label: {
                    Text("Log & reset").font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 16).padding(.vertical, 10).background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                Button { focus.reset() } label: {
                    Text("Reset").font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 14).padding(.vertical, 10).background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
            if !focus.message.isEmpty {
                Text(focus.message).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.green)
            }
            RowCard {
                HStack {
                    Text("Studied today").font(.system(size: 12.5))
                    Spacer()
                    Text("\(hm(study.data.minutes(onOffset: 0))) of \(hm(study.data.dailyMinutes))").font(.system(size: 12.5, weight: .semibold, design: .rounded))
                }
            }
        }
    }
}

// MARK: - Study screen

struct StudyView: View {
    @State private var sub = 0
    var body: some View {
        VStack(spacing: 8) {
            Picker("", selection: $sub) {
                Text("Overview").tag(0); Text("Syllabus").tag(1); Text("Mock tests").tag(2)
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(.horizontal, 16)
            switch sub {
            case 0: StudyOverview()
            case 1: SyllabusView()
            default: MocksView()
            }
        }
    }
}

struct SubMin: Identifiable {
    let name: String
    let minutes: Int
    var id: String { name }
}

struct RevItem: Identifiable {
    let subjectId: Int64
    let topicId: Int64
    let subject: String
    let title: String
    let days: Int
    var id: Int64 { topicId }
}

func weekBySubject(_ d: StudyData, _ cutoff: Int64) -> [SubMin] {
    var m: [String: Int] = [:]
    for s in d.sessions where s.date >= cutoff { m[s.subject, default: 0] += s.minutes }
    return m.map { SubMin(name: $0.key, minutes: $0.value) }.sorted { $0.minutes > $1.minutes }
}

func revisionQueue(_ d: StudyData) -> [RevItem] {
    let now = nowMs()
    var out: [RevItem] = []
    for s in d.subjects {
        for t in s.topics where t.done && !t.revised && t.studiedAt > 0 && now - t.studiedAt >= 3 * 86_400_000 {
            out.append(RevItem(subjectId: s.id, topicId: t.id, subject: s.name, title: t.title, days: Int((now - t.studiedAt) / 86_400_000)))
        }
    }
    return out
}

struct StudyOverview: View {
    @EnvironmentObject var study: StudyStore
    @Environment(\.tintC) var tintC
    @State private var showTarget = false
    @State private var targetText = ""
    @State private var logSubject = "General"
    @State private var logMin = ""
    @State private var examName = ""
    @State private var examDate = Date().addingTimeInterval(86400 * 30)

    var body: some View {
        let d = study.data
        let today = d.minutes(onOffset: 0)
        let week = (0..<7).map { d.minutes(onOffset: -$0) }
        let weekTotal = week.reduce(0, +)
        let maxDay = max(week.max() ?? 0, d.dailyMinutes, 1)
        let cutoff = msOf(Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date())) ?? Date())
        let subRows = weekBySubject(d, cutoff)
        let rev = revisionQueue(d)
        let todaySessions = d.sessions.sorted { $0.date > $1.date }.prefix(5)
        let subjectNames = ["General"] + d.subjects.map { $0.name }

        Page {
            RowCard {
                HStack(spacing: 14) {
                    Ring(progress: min(1, Double(today) / Double(max(d.dailyMinutes, 1))), label: "\(min(999, pct(Double(today), Double(max(d.dailyMinutes, 1)))))%", size: 74)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Today").font(.system(size: 11)).foregroundStyle(Color.secondary)
                        Text(hm(today)).font(.system(size: 24, weight: .bold, design: .rounded))
                        Button {
                            targetText = String(format: "%g", Double(d.dailyMinutes) / 60)
                            showTarget = true
                        } label: {
                            HStack(spacing: 4) { Text("Target \(hm(d.dailyMinutes))"); Image(systemName: "pencil").font(.system(size: 9)) }
                                .font(.system(size: 11.5)).foregroundStyle(Color.secondary)
                        }
                        .buttonStyle(.plain)
                        Text("🔥 \(d.streak()) day streak").font(.system(size: 11.5)).foregroundStyle(Color.secondary)
                    }
                    Spacer()
                }
            }
            .popover(isPresented: $showTarget) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Daily study target (hours)").font(.system(size: 13, weight: .semibold))
                    FieldBox { TextField("e.g. 6 or 4.5", text: $targetText) }
                    Button("Save") {
                        let h = num(targetText)
                        if h > 0 { study.data.dailyMinutes = Int(h * 60) }
                        showTarget = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding(14).frame(width: 220)
            }

            RowCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Last 7 days").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text("\(hm(weekTotal)) total · \(hm(weekTotal / 7))/day").font(.system(size: 11)).foregroundStyle(Color.secondary)
                    }
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach((0..<7).reversed(), id: \.self) { b in
                            VStack(spacing: 4) {
                                Text(week[b] > 0 ? hm(week[b]) : "").font(.system(size: 8.5)).foregroundStyle(Color.secondary)
                                Capsule()
                                    .fill(week[b] >= d.dailyMinutes ? Color.green : tintC)
                                    .frame(width: 14, height: week[b] > 0 ? max(4, CGFloat(week[b]) / CGFloat(maxDay) * 70) : 3)
                                    .opacity(week[b] > 0 ? 1 : 0.25)
                                Text(dayLetter(b)).font(.system(size: 9)).foregroundStyle(Color.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 104, alignment: .bottom)
                    Text("Green = you hit your daily target").font(.system(size: 10)).foregroundStyle(Color.secondary)
                }
            }

            RowCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Log study time").font(.system(size: 13, weight: .semibold))
                    HStack(spacing: 8) {
                        Picker("", selection: $logSubject) {
                            ForEach(subjectNames, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        FieldBox { TextField("minutes", text: $logMin) }.frame(width: 90)
                        Button("Add") {
                            let m = Int(logMin.trimmingCharacters(in: .whitespaces)) ?? 0
                            if m > 0 { study.data.sessions.insert(Session(id: nowMs(), subject: logSubject, minutes: m, date: nowMs()), at: 0); logMin = "" }
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                    Text("The Focus timer logs here automatically.").font(.system(size: 10.5)).foregroundStyle(Color.secondary)
                }
            }

            if !subRows.isEmpty {
                RowCard {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("This week by subject").font(.system(size: 13, weight: .semibold))
                        ForEach(Array(subRows.prefix(6))) { r in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack { Text(r.name).font(.system(size: 12.5)); Spacer(); Text(hm(r.minutes)).font(.system(size: 12, weight: .semibold, design: .rounded)) }
                                ProgressView(value: Double(r.minutes) / Double(max(subRows.first?.minutes ?? 1, 1))).tint(tintC)
                            }
                        }
                    }
                }
            }

            if !rev.isEmpty {
                RowCard {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Time to revise").font(.system(size: 13, weight: .semibold))
                        Text("Studied 3+ days ago and not revised yet").font(.system(size: 10.5)).foregroundStyle(Color.secondary)
                        ForEach(Array(rev.prefix(6))) { r in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(r.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                                    Text("\(r.subject) · studied \(r.days)d ago").font(.system(size: 10.5)).foregroundStyle(Color.secondary)
                                }
                                Spacer()
                                Button("Revised") {
                                    study.mutateSubject(r.subjectId) { s in
                                        if let i = s.topics.firstIndex(where: { $0.id == r.topicId }) { s.topics[i].revised = true }
                                    }
                                }
                                .font(.system(size: 11))
                            }
                        }
                    }
                }
            }

            RowCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Exam countdown").font(.system(size: 13, weight: .semibold))
                    ForEach(d.exams.sorted { $0.date < $1.date }) { e in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(e.name).font(.system(size: 13, weight: .medium))
                                Text(fmt("EEE, d MMM yyyy", dateOf(e.date))).font(.system(size: 10.5)).foregroundStyle(Color.secondary)
                            }
                            Spacer()
                            Text(e.daysLeft >= 0 ? "\(e.daysLeft) days" : "Over")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(e.daysLeft >= 0 && e.daysLeft <= 14 ? Color.orange : tintC)
                            Button { study.data.exams.removeAll { $0.id == e.id } } label: {
                                Image(systemName: "xmark.circle").foregroundStyle(Color.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack(spacing: 8) {
                        FieldBox { TextField("Exam name (e.g. BPSC Prelims)", text: $examName) }
                        DatePicker("", selection: $examDate, displayedComponents: .date).labelsHidden()
                        Button("Add") {
                            let n = examName.trimmingCharacters(in: .whitespaces)
                            if !n.isEmpty { study.data.exams.append(Exam(id: nowMs(), name: n, date: msOf(examDate))); examName = "" }
                        }
                    }
                }
            }

            if !todaySessions.isEmpty {
                RowCard {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Recent sessions").font(.system(size: 13, weight: .semibold))
                        ForEach(Array(todaySessions)) { s in
                            HStack {
                                Text(s.subject).font(.system(size: 12.5))
                                Text(fmt("d MMM, h:mm a", dateOf(s.date))).font(.system(size: 10.5)).foregroundStyle(Color.secondary)
                                Spacer()
                                Text(hm(s.minutes)).font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                Button { study.data.sessions.removeAll { $0.id == s.id } } label: {
                                    Image(systemName: "xmark.circle").foregroundStyle(Color.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Syllabus

struct SyllabusView: View {
    @EnvironmentObject var study: StudyStore
    @Environment(\.tintC) var tintC
    @State private var newSubject = ""
    let starter = ["History", "Geography", "Polity", "Economy", "General Science", "Bihar GK", "Current Affairs", "Maths & Reasoning", "English", "Hindi"]

    func addSubject() {
        let n = newSubject.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        study.data.subjects.append(Subject(id: nowMs(), name: n))
        newSubject = ""
    }

    var body: some View {
        Page {
            FieldBox {
                HStack {
                    TextField("Add a subject (e.g. Polity)", text: $newSubject).onSubmit { addSubject() }
                    Button { addSubject() } label: { Image(systemName: "plus.circle.fill").foregroundStyle(tintC) }.buttonStyle(.plain)
                }
            }
            if study.data.subjects.isEmpty {
                EmptyHint("Track every subject and topic you need to cover.\nAdd a subject above, or start from a ready list you can edit.")
                Button {
                    var t = nowMs()
                    for n in starter { study.data.subjects.append(Subject(id: t, name: n)); t += 1 }
                } label: {
                    Text("Add starter subjects")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 9).background(Capsule().fill(tintC))
                }
                .buttonStyle(.plain)
            }
            ForEach(study.data.subjects) { s in SubjectCard(subject: s) }
        }
    }
}

struct SubjectCard: View {
    @EnvironmentObject var study: StudyStore
    @Environment(\.tintC) var tintC
    let subject: Subject
    @State private var expanded = false
    @State private var newTopic = ""

    func addTopic() {
        let t = newTopic.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        study.mutateSubject(subject.id) { $0.topics.append(Topic(id: nowMs(), title: t)) }
        newTopic = ""
    }

    var body: some View {
        let total = subject.topics.count
        let done = subject.topics.filter { $0.done }.count
        let revised = subject.topics.filter { $0.revised }.count
        RowCard {
            VStack(alignment: .leading, spacing: 8) {
                Button { withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() } } label: {
                    HStack {
                        Text(subject.name).font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Text(total == 0 ? "no topics" : "\(done)/\(total) studied").font(.system(size: 11)).foregroundStyle(Color.secondary)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 10)).foregroundStyle(Color.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                ProgressView(value: total > 0 ? Double(done) / Double(total) : 0).tint(tintC)
                if total > 0 { Text("\(revised) revised").font(.system(size: 10.5)).foregroundStyle(Color.secondary) }
                if expanded {
                    ForEach(subject.topics) { t in
                        HStack(spacing: 8) {
                            Button {
                                study.mutateSubject(subject.id) { s in
                                    if let i = s.topics.firstIndex(where: { $0.id == t.id }) {
                                        s.topics[i].done.toggle()
                                        s.topics[i].studiedAt = s.topics[i].done ? nowMs() : 0
                                        if !s.topics[i].done { s.topics[i].revised = false }
                                    }
                                }
                            } label: {
                                Image(systemName: t.done ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(t.done ? Color.green : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            Text(t.title).font(.system(size: 12.5)).strikethrough(t.done, color: Color.secondary).lineLimit(2)
                            Spacer()
                            if t.done {
                                Button {
                                    study.mutateSubject(subject.id) { s in
                                        if let i = s.topics.firstIndex(where: { $0.id == t.id }) { s.topics[i].revised.toggle() }
                                    }
                                } label: {
                                    Text("R").font(.system(size: 10, weight: .bold))
                                        .frame(width: 20, height: 20)
                                        .background(Circle().fill(t.revised ? Color.orange : Color.white.opacity(0.12)))
                                }
                                .buttonStyle(.plain)
                                .help("Mark as revised")
                            }
                            Button {
                                study.mutateSubject(subject.id) { s in s.topics.removeAll { $0.id == t.id } }
                            } label: { Image(systemName: "xmark").font(.system(size: 9)).foregroundStyle(Color.secondary) }
                            .buttonStyle(.plain)
                        }
                    }
                    FieldBox {
                        HStack {
                            TextField("Add a topic", text: $newTopic).onSubmit { addTopic() }
                            Button { addTopic() } label: { Image(systemName: "plus.circle.fill").foregroundStyle(tintC) }.buttonStyle(.plain)
                        }
                    }
                    Button(role: .destructive) {
                        study.data.subjects.removeAll { $0.id == subject.id }
                    } label: {
                        Text("Delete subject").font(.system(size: 11))
                    }
                    .buttonStyle(.plain).foregroundStyle(Color.red.opacity(0.85))
                }
            }
        }
    }
}

// MARK: - Mock tests

struct LineChart: View {
    let values: [Double]
    let color: Color
    var body: some View {
        GeometryReader { g in
            let n = values.count
            ZStack {
                Path { p in
                    for i in 0..<n {
                        let x = n == 1 ? g.size.width / 2 : g.size.width * CGFloat(i) / CGFloat(n - 1)
                        let y = g.size.height * (1 - CGFloat(min(max(values[i], 0), 100) / 100))
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                ForEach(0..<n, id: \.self) { i in
                    Circle().fill(color).frame(width: 7, height: 7)
                        .position(x: n == 1 ? g.size.width / 2 : g.size.width * CGFloat(i) / CGFloat(n - 1),
                                  y: g.size.height * (1 - CGFloat(min(max(values[i], 0), 100) / 100)))
                }
            }
        }
        .frame(height: 80)
    }
}

struct MocksView: View {
    @EnvironmentObject var study: StudyStore
    @Environment(\.tintC) var tintC
    @State private var name = ""
    @State private var score = ""
    @State private var total = "100"
    @State private var error = false

    func add() {
        let s = num(score), t = num(total)
        guard t > 0, s >= 0, !score.isEmpty else { error = true; return }
        let n = name.trimmingCharacters(in: .whitespaces)
        study.data.mocks.insert(Mock(id: nowMs(), name: n.isEmpty ? "Mock test \(study.data.mocks.count + 1)" : n, score: s, total: t, date: nowMs()), at: 0)
        name = ""; score = ""; error = false
    }

    var body: some View {
        let mocks = study.data.mocks.sorted { $0.date < $1.date }
        let pcts = mocks.map { $0.percent }
        Page {
            RowCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Log a mock test").font(.system(size: 13, weight: .semibold))
                    FieldBox { TextField("Test name (e.g. BPSC Prelims mock 4)", text: $name) }
                    HStack(spacing: 8) {
                        FieldBox { TextField(error ? "Enter score" : "Score", text: $score).onSubmit { add() } }
                        Text("out of").font(.system(size: 11)).foregroundStyle(Color.secondary)
                        FieldBox { TextField("Total", text: $total).onSubmit { add() } }
                        Button("Add") { add() }.keyboardShortcut(.defaultAction)
                    }
                }
            }
            if mocks.isEmpty { EmptyHint("Log every mock test to watch your score trend.") } else {
                RowCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading) { Text("Average").font(.system(size: 10.5)).foregroundStyle(Color.secondary); Text("\(Int(pcts.reduce(0, +) / Double(pcts.count)))%").font(.system(size: 20, weight: .bold, design: .rounded)) }
                            Spacer()
                            VStack(alignment: .leading) { Text("Best").font(.system(size: 10.5)).foregroundStyle(Color.secondary); Text("\(Int(pcts.max() ?? 0))%").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(Color.green) }
                            Spacer()
                            VStack(alignment: .leading) { Text("Latest").font(.system(size: 10.5)).foregroundStyle(Color.secondary); Text("\(Int(pcts.last ?? 0))%").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(tintC) }
                            Spacer()
                            VStack(alignment: .leading) { Text("Tests").font(.system(size: 10.5)).foregroundStyle(Color.secondary); Text("\(mocks.count)").font(.system(size: 20, weight: .bold, design: .rounded)) }
                        }
                        LineChart(values: Array(pcts.suffix(12)), color: tintC)
                        Text("Score trend (last \(min(12, pcts.count)) tests)").font(.system(size: 10)).foregroundStyle(Color.secondary)
                    }
                }
            }
            ForEach(mocks.reversed()) { m in
                RowCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Text(fmt("d MMM yyyy", dateOf(m.date)) + " · \(String(format: "%g", m.score))/\(String(format: "%g", m.total))")
                                .font(.system(size: 10.5)).foregroundStyle(Color.secondary)
                        }
                        Spacer()
                        Text("\(Int(m.percent))%").font(.system(size: 16, weight: .bold, design: .rounded))
                        Button { study.data.mocks.removeAll { $0.id == m.id } } label: {
                            Image(systemName: "xmark.circle").foregroundStyle(Color.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
