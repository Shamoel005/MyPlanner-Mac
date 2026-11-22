import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

// MARK: - Planner model

struct Item: Identifiable, Codable, Equatable {
    var id: Int64
    var kind: String
    var title: String
    var body: String = ""
    var scope: String = "Month"
    var due: Int64 = 0
    var priority: Int = 1
    var target: Int = 10
    var current: Int = 0
    var done: Bool = false
    var pinned: Bool = false
    var days: String = ""
    var doneAt: Int64 = 0

    init(kind: String, title: String, due: Int64 = 0) {
        self.id = Int64(Date().timeIntervalSince1970 * 1000)
        self.kind = kind
        self.title = title
        self.due = due
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, title, body, scope, due, priority, target, current, done, pinned, days, doneAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        kind = try c.decode(String.self, forKey: .kind)
        title = try c.decode(String.self, forKey: .title)
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        scope = try c.decodeIfPresent(String.self, forKey: .scope) ?? "Month"
        due = try c.decodeIfPresent(Int64.self, forKey: .due) ?? 0
        priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 1
        target = try c.decodeIfPresent(Int.self, forKey: .target) ?? 10
        current = try c.decodeIfPresent(Int.self, forKey: .current) ?? 0
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        days = try c.decodeIfPresent(String.self, forKey: .days) ?? ""
        doneAt = try c.decodeIfPresent(Int64.self, forKey: .doneAt) ?? 0
    }
}

func supportURL(_ name: String) -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let dir = base.appendingPathComponent("MyPlanner", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent(name)
}

final class Store: ObservableObject {
    @Published var items: [Item] = [] { didSet { save() } }
    private let url = supportURL("items.json")

    init() {
        if let d = try? Data(contentsOf: url), let l = try? JSONDecoder().decode([Item].self, from: d) { items = l }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(items) { try? d.write(to: url, options: .atomic) }
    }

    func update(_ id: Int64, _ change: (inout Item) -> Void) {
        if let ix = items.firstIndex(where: { $0.id == id }) {
            var i = items[ix]
            change(&i)
            items[ix] = i
        }
    }

    func remove(_ id: Int64) { items.removeAll { $0.id == id } }
}

struct FullBackup: Codable {
    var items: [Item]
    var budget: BudgetData
    var study: StudyData
}

// MARK: - Date helpers

func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
func msOf(_ d: Date) -> Int64 { Int64(d.timeIntervalSince1970 * 1000) }
func dateOf(_ ms: Int64) -> Date { Date(timeIntervalSince1970: Double(ms) / 1000) }
func dayStartMs() -> Int64 { msOf(Calendar.current.startOfDay(for: Date())) }

func endOfDayMs(_ d: Date) -> Int64 {
    let end = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: d) ?? d
    return msOf(end) + 999
}

func dayEndMs(_ plus: Int) -> Int64 {
    let base = Calendar.current.date(byAdding: .day, value: plus, to: Date()) ?? Date()
    return endOfDayMs(base)
}

func fmt(_ pattern: String, _ d: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = pattern
    return f.string(from: d)
}

func fmtDeadline(_ ms: Int64) -> String {
    let d = dateOf(ms)
    let cal = Calendar.current
    if cal.isDateInToday(d) { return "Today " + fmt("h:mm a", d) }
    if cal.isDateInTomorrow(d) { return "Tomorrow " + fmt("h:mm a", d) }
    if cal.isDateInYesterday(d) { return "Yesterday " + fmt("h:mm a", d) }
    return fmt("EEE d MMM, h:mm a", d)
}

func leftText(_ due: Int64, _ now: Int64) -> String {
    let m = Int((due - now) / 60000)
    if m < 1 { return "under a minute left" }
    if m < 60 { return "\(m)m left" }
    if m < 1440 { return "\(m / 60)h \(m % 60)m left" }
    return "\(m / 1440)d \((m % 1440) / 60)h left"
}

func dayKey(_ offset: Int) -> String {
    let d = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyyMMdd"
    return f.string(from: d)
}

func habitSet(_ s: String) -> Set<String> { Set(s.split(separator: ",").map { String($0) }) }

func streak(_ s: String) -> Int {
    let set = habitSet(s)
    var o = set.contains(dayKey(0)) ? 0 : -1
    var n = 0
    while set.contains(dayKey(o)) { n += 1; o -= 1 }
    return n
}

func dayLetter(_ back: Int) -> String {
    let d = Calendar.current.date(byAdding: .day, value: -back, to: Date()) ?? Date()
    return fmt("EEEEE", d)
}

struct DL: Identifiable {
    let label: String
    let date: Date
    var id: String { label }
}

func deadlinePresets() -> [DL] {
    let cal = Calendar.current
    let now = Date()
    var out = [
        DL(label: "In 1 hour", date: now.addingTimeInterval(3600)),
        DL(label: "In 2 hours", date: now.addingTimeInterval(7200)),
        DL(label: "In 4 hours", date: now.addingTimeInterval(14400))
    ]
    if let t = cal.date(bySettingHour: 21, minute: 0, second: 0, of: now), t > now.addingTimeInterval(900) {
        out.append(DL(label: "Tonight 9 PM", date: t))
    }
    if let tm = cal.date(byAdding: .day, value: 1, to: now), let t = cal.date(bySettingHour: 9, minute: 0, second: 0, of: tm) {
        out.append(DL(label: "Tomorrow 9 AM", date: t))
    }
    return out
}

func defaultDeadline() -> Date {
    let now = Date()
    if let t = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: now), t > now.addingTimeInterval(1800) { return t }
    return now.addingTimeInterval(3600)
}

func taskRank(_ i: Item, _ now: Int64) -> Int { i.done ? 2 : ((i.due > 0 && i.due < now) ? 0 : 1) }

/// Live clock so deadlines can expire while the panel is just sitting on the desktop.
final class Ticker: ObservableObject {
    @Published var now = Date()
    private var timer: Timer?
    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.now = Date() }
    }
}

// MARK: - App + desktop window

@main
struct PlannerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}

final class DeskWindow: NSWindow {
    var dragStart: NSPoint?
    var dragOrigin: NSPoint = .zero

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ e: NSEvent) {
        switch e.type {
        case .leftMouseDown:
            if !isKeyWindow {
                NSApp.activate(ignoringOtherApps: true)
                makeKeyAndOrderFront(nil)
            }
            dragStart = e.locationInWindow.y > frame.height - 84 ? NSEvent.mouseLocation : nil
            dragOrigin = frame.origin
        case .leftMouseDragged:
            if let s = dragStart {
                let m = NSEvent.mouseLocation
                setFrameOrigin(NSPoint(x: dragOrigin.x + m.x - s.x, y: dragOrigin.y + m.y - s.y))
                return
            }
        case .leftMouseUp:
            dragStart = nil
        default:
            break
        }
        super.sendEvent(e)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: DeskWindow!
    var statusItem: NSStatusItem!
    let store = Store()
    let budget = BudgetStore()
    let study = StudyStore()
    let ticker = Ticker()
    let focus = FocusModel()
    var onTop = false
    let deskLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    let sizes: [(String, CGFloat, CGFloat)] = [("Compact", 360, 600), ("Comfortable", 420, 720), ("Large", 500, 840)]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMainMenu()
        focus.logger = { [weak self] subject, minutes in
            self?.study.data.sessions.insert(Session(id: nowMs(), subject: subject, minutes: minutes, date: nowMs()), at: 0)
        }

        let w = DeskWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 720),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.appearance = NSAppearance(named: .darkAqua)
        w.level = deskLevel
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let root = RootView()
            .environmentObject(store).environmentObject(budget).environmentObject(study)
            .environmentObject(ticker).environmentObject(focus)
        w.contentView = NSHostingView(rootView: root)

        let restored = w.setFrameUsingName("PlannerPanel2")
        if !restored, let s = NSScreen.main {
            w.setFrameOrigin(NSPoint(x: s.visibleFrame.maxX - 452, y: s.visibleFrame.maxY - 740))
        }
        w.setFrameAutosaveName("PlannerPanel2")
        w.orderFrontRegardless()
        window = w

        if !UserDefaults.standard.bool(forKey: "loginAsked") {
            UserDefaults.standard.set(true, forKey: "loginAsked")
            try? SMAppService.mainApp.register()
        }
        setupStatusItem()
    }

    /// A hidden main menu is what makes Cmd+C, Cmd+V, Cmd+Z and Cmd+A work inside text fields.
    func setupMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit My Planner", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        editItem.submenu = edit
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = main
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Planner")
        let m = NSMenu()
        m.addItem(withTitle: "Show Planner", action: #selector(showPanel), keyEquivalent: "")
        m.addItem(withTitle: "Hide Planner", action: #selector(hidePanel), keyEquivalent: "")
        let top = m.addItem(withTitle: "Keep Above Windows", action: #selector(toggleTop(_:)), keyEquivalent: "")
        top.state = .off
        let sizeItem = NSMenuItem(title: "Panel Size", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (i, s) in sizes.enumerated() {
            let it = sub.addItem(withTitle: s.0, action: #selector(setSize(_:)), keyEquivalent: "")
            it.tag = i
            it.target = self
        }
        sizeItem.submenu = sub
        m.addItem(sizeItem)
        m.addItem(.separator())
        let login = m.addItem(withTitle: "Launch at Login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        m.addItem(withTitle: "Back Up Everything…", action: #selector(backup), keyEquivalent: "")
        m.addItem(withTitle: "Restore From Backup…", action: #selector(restore), keyEquivalent: "")
        m.addItem(withTitle: "Export Budget as CSV…", action: #selector(exportCSV), keyEquivalent: "")
        m.addItem(.separator())
        let quit = m.addItem(withTitle: "Quit My Planner", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in m.items where item !== quit && item.submenu == nil { item.target = self }
        statusItem.menu = m
    }

    @objc func showPanel() { window.orderFrontRegardless() }
    @objc func hidePanel() { window.orderOut(nil) }

    @objc func setSize(_ sender: NSMenuItem) {
        let s = sizes[sender.tag]
        let f = window.frame
        window.setFrame(NSRect(x: f.origin.x, y: f.maxY - s.2, width: s.1, height: s.2), display: true, animate: true)
    }

    @objc func toggleTop(_ sender: NSMenuItem) {
        onTop.toggle()
        sender.state = onTop ? .on : .off
        window.level = onTop ? .floating : deskLevel
        window.orderFrontRegardless()
    }

    @objc func toggleLogin(_ sender: NSMenuItem) {
        let s = SMAppService.mainApp
        do {
            if s.status == .enabled { try s.unregister(); sender.state = .off }
            else { try s.register(); sender.state = .on }
        } catch {}
    }

    @objc func backup() {
        NSApp.activate(ignoringOtherApps: true)
        let p = NSSavePanel()
        p.nameFieldStringValue = "planner-backup.json"
        p.allowedContentTypes = [.json]
        if p.runModal() == .OK, let u = p.url {
            let e = JSONEncoder()
            e.outputFormatting = [.prettyPrinted]
            if let d = try? e.encode(FullBackup(items: store.items, budget: budget.data, study: study.data)) { try? d.write(to: u) }
        }
    }

    @objc func restore() {
        NSApp.activate(ignoringOtherApps: true)
        let p = NSOpenPanel()
        p.allowedContentTypes = [.json]
        guard p.runModal() == .OK, let u = p.url, let d = try? Data(contentsOf: u) else { return }
        let dec = JSONDecoder()
        if let f = try? dec.decode(FullBackup.self, from: d) {
            store.items = f.items; budget.data = f.budget; study.data = f.study
        } else if let l = try? dec.decode([Item].self, from: d), !l.isEmpty {
            store.items = l
        } else if let b = try? dec.decode(BudgetData.self, from: d), !(b.txns.isEmpty && b.goals.isEmpty && b.bills.isEmpty && b.budget == 0) {
            budget.data = b
        }
    }

    @objc func exportCSV() {
        NSApp.activate(ignoringOtherApps: true)
        let p = NSSavePanel()
        p.nameFieldStringValue = "budget-transactions.csv"
        p.allowedContentTypes = [.commaSeparatedText]
        if p.runModal() == .OK, let u = p.url { try? budget.csv().write(to: u, atomically: true, encoding: .utf8) }
    }
}

// MARK: - Theme + shared components

enum Theme {
    static let accent = Color(red: 0.49, green: 0.40, blue: 1.00)
    static let pink = Color(red: 1.00, green: 0.38, blue: 0.62)
    static let tabColors: [Color] = [
        Color(red: 1.00, green: 0.55, blue: 0.30),   // Today
        Color(red: 0.30, green: 0.62, blue: 1.00),   // Tasks
        Color(red: 0.25, green: 0.85, blue: 0.65),   // Goals
        Color(red: 1.00, green: 0.40, blue: 0.48),   // Habits
        Color(red: 0.25, green: 0.80, blue: 0.92),   // Study
        Color(red: 1.00, green: 0.80, blue: 0.30),   // Notes
        Color(red: 1.00, green: 0.45, blue: 0.80),   // Budget
        Color(red: 0.66, green: 0.46, blue: 1.00)    // Focus
    ]
}

private struct TintKey: EnvironmentKey { static let defaultValue = Theme.accent }
extension EnvironmentValues {
    var tintC: Color {
        get { self[TintKey.self] }
        set { self[TintKey.self] = newValue }
    }
}

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

struct Ring: View {
    @Environment(\.tintC) var tintC
    var progress: Double
    var label: String
    var size: CGFloat = 54
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.16), lineWidth: 6)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(progress, 0), 1)))
                .stroke(LinearGradient(colors: [tintC, Theme.pink], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .shadow(color: tintC.opacity(0.7), radius: 5)
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: progress)
            Text(label).font(.system(size: size > 60 ? 15 : 12, weight: .semibold, design: .rounded))
        }
        .frame(width: size, height: size)
    }
}

struct SectionLabel: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
            .padding(.leading, 4)
    }
}

struct EmptyHint: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Color.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
    }
}

struct Page<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ c: () -> Content) { content = c() }
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 8) { content }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
    }
}

struct RowCard<Content: View>: View {
    let content: Content
    var tint: Color? = nil
    init(tint: Color? = nil, @ViewBuilder _ c: () -> Content) { self.tint = tint; content = c() }
    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.11))
                    if let t = tint { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(t) }
                }
            )
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
    }
}

struct PillButton: View {
    @Environment(\.tintC) var tintC
    let text: String
    var selected: Bool = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(selected ? tintC.opacity(0.55) : Color.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }
}

struct FieldBox<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ c: () -> Content) { content = c() }
    var body: some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.12)))
    }
}

struct DeadlinePopover: View {
    @Binding var date: Date
    var onDone: () -> Void
    var body: some View {
        VStack(spacing: 8) {
            DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.graphical)
                .labelsHidden()
            Button("Set deadline", action: onDone).keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }
}

// MARK: - Root

struct RootView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var budget: BudgetStore
    @EnvironmentObject var study: StudyStore
    @EnvironmentObject var ticker: Ticker
    @EnvironmentObject var focus: FocusModel
    @State private var tab = 0
    @State private var draft = ""
    @State private var draftTarget = ""
    @State private var dlChoice: Date? = nil
    @State private var pickDate = Date()
    @State private var showPick = false
    @State private var openNote: Int64? = nil

    var tintC: Color { Theme.tabColors[tab] }

    let icons = ["sun.max", "checklist", "target", "flame", "graduationcap", "note.text", "creditcard", "timer"]
    let names = ["Today", "Tasks", "Goals", "Habits", "Study", "Notes", "Budget", "Focus"]
    let placeholders = ["Add a task for today", "Add a task", "Add a goal", "Add a habit", "", "Write a note title", "", ""]

    var ring: (Double, String)? {
        let now = msOf(ticker.now)
        let s = dayStartMs(), e = dayEndMs(0)
        switch tab {
        case 0:
            let all = store.items.filter { $0.kind == "task" && $0.due >= s && $0.due <= e }
            let d = all.filter { $0.done }.count
            return (all.isEmpty ? 0 : Double(d) / Double(all.count), "\(d)/\(all.count)")
        case 1:
            let all = store.items.filter { $0.kind == "task" }
            let d = all.filter { $0.done }.count
            let ex = all.filter { !$0.done && $0.due > 0 && $0.due < now }.count
            return (all.isEmpty ? 0 : Double(d) / Double(all.count), ex > 0 ? "\(ex)✕" : "\(d)/\(all.count)")
        case 2:
            let g = store.items.filter { $0.kind == "goal" }
            let avg = g.isEmpty ? 0 : g.map { $0.target > 0 ? min(1, Double($0.current) / Double($0.target)) : 0 }.reduce(0, +) / Double(g.count)
            return (avg, "\(Int(avg * 100))%")
        case 3:
            let h = store.items.filter { $0.kind == "habit" }
            let d = h.filter { habitSet($0.days).contains(dayKey(0)) }.count
            return (h.isEmpty ? 0 : Double(d) / Double(h.count), "\(d)/\(h.count)")
        case 4:
            let t = Double(study.data.minutes(onOffset: 0))
            let goal = Double(max(study.data.dailyMinutes, 1))
            return (min(1, t / goal), "\(Int(min(t / goal, 9.99) * 100))%")
        case 5:
            return (0, "\(store.items.filter { $0.kind == "note" }.count)")
        case 6:
            let lim = budget.data.budget
            let r = lim > 0 ? min(1, budget.data.monthTx(nowYm()).expense / lim) : 0
            return (r, lim > 0 ? "\(Int(r * 100))%" : "--")
        default:
            return nil
        }
    }

    var dateString: String { fmt("EEEE, d MMM", Date()).uppercased() }
    var showsAddBar: Bool { [0, 1, 2, 3, 5].contains(tab) && !(tab == 5 && openNote != nil) }

    var body: some View {
        ZStack {
            VisualEffect()
            LinearGradient(
                colors: [tintC.opacity(0.55), Color(red: 0.35, green: 0.20, blue: 0.75).opacity(0.45), Color(red: 0.08, green: 0.08, blue: 0.28).opacity(0.55)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Circle().fill(tintC.opacity(0.40)).frame(width: 260, height: 260).blur(radius: 70).offset(x: 130, y: -250)
            Circle().fill(Theme.pink.opacity(0.28)).frame(width: 230, height: 230).blur(radius: 70).offset(x: -140, y: 260)

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dateString)
                            .font(.system(size: 11, weight: .semibold)).tracking(0.8)
                            .foregroundStyle(tintC)
                        Text(names[tab])
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                    }
                    Spacer()
                    if let r = ring { Ring(progress: r.0, label: r.1) }
                }
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 10)

                tabBar

                Group {
                    switch tab {
                    case 0: TodayView()
                    case 1: TasksView()
                    case 2: GoalsView()
                    case 3: HabitsView()
                    case 4: StudyView()
                    case 5: NotesView(openNote: $openNote)
                    case 6: BudgetView()
                    default: FocusView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showsAddBar { addBar }
            }
        }
        .environment(\.tintC, tintC)
        .animation(.easeInOut(duration: 0.35), value: tab)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        )
    }

    var tabBar: some View {
        HStack(spacing: 3) {
            ForEach(0..<icons.count, id: \.self) { i in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { tab = i }
                } label: {
                    Image(systemName: icons[i])
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .foregroundStyle(tab == i ? Color.white : Color.white.opacity(0.55))
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(tab == i ? tintC.opacity(0.45) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(names[i])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.10)))
        .padding(.horizontal, 16)
    }

    var addBar: some View {
        VStack(spacing: 8) {
            if tab == 0 || tab == 1 {
                HStack {
                    Menu {
                        ForEach(deadlinePresets()) { p in
                            Button(p.label) { dlChoice = p.date }
                        }
                        Divider()
                        Button("Pick date & time…") {
                            pickDate = dlChoice ?? defaultDeadline()
                            showPick = true
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "clock")
                            Text("Deadline: " + fmtDeadline(msOf(dlChoice ?? defaultDeadline())))
                        }
                        .font(.system(size: 11.5, weight: .medium))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(tintC.opacity(0.35)))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    Spacer()
                }
                .popover(isPresented: $showPick) {
                    DeadlinePopover(date: $pickDate) { dlChoice = pickDate; showPick = false }
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill").foregroundStyle(tintC)
                TextField(placeholders[tab], text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .onSubmit { add() }
                if tab == 2 {
                    TextField("Target", text: $draftTarget)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 64)
                        .onSubmit { add() }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.14)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        }
        .padding(16)
    }

    func add() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        switch tab {
        case 0, 1:
            store.items.insert(Item(kind: "task", title: t, due: msOf(dlChoice ?? defaultDeadline())), at: 0)
            dlChoice = nil
        case 2:
            var g = Item(kind: "goal", title: t)
            g.target = max(1, Int(draftTarget.trimmingCharacters(in: .whitespaces)) ?? 10)
            store.items.insert(g, at: 0)
            draftTarget = ""
        case 3:
            store.items.insert(Item(kind: "habit", title: t), at: 0)
        case 5:
            let n = Item(kind: "note", title: t)
            store.items.insert(n, at: 0)
            openNote = n.id
        default:
            break
        }
        draft = ""
    }
}

// MARK: - Today / Tasks

struct TodayView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ticker: Ticker
    @EnvironmentObject var study: StudyStore
    @Environment(\.tintC) var tintC

    var body: some View {
        let now = msOf(ticker.now)
        let s = dayStartMs()
        let e = dayEndMs(0)
        let tasks = store.items.filter { $0.kind == "task" }
        let earlier = tasks.filter { !$0.done && $0.due > 0 && $0.due < s }
        let todays = tasks.filter { $0.due >= s && $0.due <= e }.sorted { a, b in
            let ra = taskRank(a, now), rb = taskRank(b, now)
            return ra != rb ? ra < rb : a.due < b.due
        }
        let habits = store.items.filter { $0.kind == "habit" }
        let studied = study.data.minutes(onOffset: 0)
        Page {
            RowCard {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "graduationcap.fill").foregroundStyle(Theme.tabColors[4])
                        Text("Study today").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text("\(hm(studied)) / \(hm(study.data.dailyMinutes))")
                            .font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(Color.secondary)
                    }
                    ProgressView(value: min(1, Double(studied) / Double(max(study.data.dailyMinutes, 1)))).tint(Theme.tabColors[4])
                    if let ex = study.nextExam {
                        Text("\(ex.name): \(ex.daysLeft) days to go")
                            .font(.system(size: 11.5)).foregroundStyle(Color.secondary)
                    }
                }
            }
            if !earlier.isEmpty {
                SectionLabel("Expired earlier")
                ForEach(earlier) { TaskRow(item: $0) }
            }
            SectionLabel("Today")
            if todays.isEmpty { EmptyHint("Nothing due today.\nAdd a task with a deadline below.") }
            ForEach(todays) { TaskRow(item: $0) }
            if !habits.isEmpty {
                SectionLabel("Habits")
                ForEach(habits) { HabitRow(item: $0, compact: true) }
            }
        }
    }
}

struct TasksView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ticker: Ticker
    @State private var f = 0
    var body: some View {
        let now = msOf(ticker.now)
        let list = store.items.filter { i in
            guard i.kind == "task" else { return false }
            let ex = !i.done && i.due > 0 && i.due < now
            switch f {
            case 1: return !i.done && !ex
            case 2: return ex
            case 3: return i.done
            default: return true
            }
        }.sorted { a, b in
            let ra = taskRank(a, now), rb = taskRank(b, now)
            if ra != rb { return ra < rb }
            return (a.due == 0 ? Int64.max : a.due) < (b.due == 0 ? Int64.max : b.due)
        }
        Page {
            Picker("", selection: $f) {
                Text("All").tag(0); Text("Pending").tag(1); Text("Expired").tag(2); Text("Done").tag(3)
            }
            .pickerStyle(.segmented).labelsHidden()
            if list.isEmpty { EmptyHint("No tasks here") }
            ForEach(list) { TaskRow(item: $0) }
        }
    }
}

struct TaskRow: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ticker: Ticker
    let item: Item
    @State private var showPick = false
    @State private var pickDate = Date()

    var body: some View {
        let now = msOf(ticker.now)
        let expired = !item.done && item.due > 0 && item.due < now
        let late = item.done && item.due > 0 && item.doneAt > item.due
        let soon = !item.done && !expired && item.due > 0 && item.due - now < 3_600_000
        RowCard(tint: expired ? Color.red.opacity(0.16) : (item.done ? Color.green.opacity(0.10) : nil)) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    store.update(item.id) { $0.done.toggle(); $0.doneAt = $0.done ? nowMs() : 0 }
                } label: {
                    Image(systemName: item.done ? "checkmark.circle.fill" : (expired ? "xmark.circle.fill" : "circle"))
                        .font(.system(size: 21))
                        .foregroundStyle(item.done ? Color.green : (expired ? Color.red : Color.secondary))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .medium))
                        .strikethrough(item.done)
                        .foregroundStyle(item.done ? Color.secondary : Color.primary)
                    if item.done {
                        Text(late ? "Completed late" : "Completed")
                            .font(.system(size: 11)).foregroundStyle(late ? Color.orange : Color.green)
                    } else if expired {
                        Text("Expired · was due " + fmtDeadline(item.due))
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Color.red)
                    } else if item.due > 0 {
                        Text("Due " + fmtDeadline(item.due) + " · " + leftText(item.due, now))
                            .font(.system(size: 11)).foregroundStyle(soon ? Color.orange : Color.secondary)
                    } else {
                        Text("No deadline · open ••• to set one")
                            .font(.system(size: 11)).foregroundStyle(Color.secondary)
                    }
                }
                Spacer(minLength: 4)
                if item.priority == 2 {
                    Image(systemName: "flag.fill").font(.system(size: 11)).foregroundStyle(Color.red)
                }
                Menu {
                    Menu("Priority") {
                        Button("Low") { store.update(item.id) { $0.priority = 0 } }
                        Button("Medium") { store.update(item.id) { $0.priority = 1 } }
                        Button("High") { store.update(item.id) { $0.priority = 2 } }
                    }
                    Menu("Deadline") {
                        ForEach(deadlinePresets()) { p in
                            Button(p.label) { store.update(item.id) { $0.due = msOf(p.date) } }
                        }
                        Button("Pick date & time…") {
                            pickDate = item.due > 0 ? dateOf(item.due) : defaultDeadline()
                            showPick = true
                        }
                    }
                    Divider()
                    Button("Delete", role: .destructive) { store.remove(item.id) }
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(Color.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 22)
            }
        }
        .popover(isPresented: $showPick) {
            DeadlinePopover(date: $pickDate) {
                store.update(item.id) { $0.due = msOf(pickDate) }
                showPick = false
            }
        }
    }
}

// MARK: - Goals / Habits

struct GoalsView: View {
    @EnvironmentObject var store: Store
    @State private var f = 0
    let opts = ["All", "Week", "Month", "Year"]
    var body: some View {
        let list = store.items.filter { $0.kind == "goal" && (f == 0 || $0.scope == opts[f]) }
        Page {
            Picker("", selection: $f) {
                ForEach(0..<4, id: \.self) { Text(opts[$0]).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            if list.isEmpty { EmptyHint("Type a goal and its target below,\nlike “Mock tests” and 30") }
            ForEach(list) { GoalRow(item: $0) }
        }
    }
}

struct GoalRow: View {
    @EnvironmentObject var store: Store
    @Environment(\.tintC) var tintC
    let item: Item
    @State private var showEdit = false
    @State private var curText = ""
    @State private var tgtText = ""

    var body: some View {
        let p = item.target > 0 ? min(1, Double(item.current) / Double(item.target)) : 0
        RowCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.scope.uppercased() + " GOAL")
                            .font(.system(size: 9.5, weight: .bold)).tracking(0.6).foregroundStyle(tintC)
                        Text(item.title).font(.system(size: 14, weight: .semibold))
                    }
                    Spacer()
                    Text("\(Int(p * 100))%").font(.system(size: 20, weight: .semibold, design: .rounded))
                    Menu {
                        Button("Edit target & progress…") { openEditor() }
                        Menu("Period") {
                            Button("Week") { store.update(item.id) { $0.scope = "Week" } }
                            Button("Month") { store.update(item.id) { $0.scope = "Month" } }
                            Button("Year") { store.update(item.id) { $0.scope = "Year" } }
                        }
                        Divider()
                        Button("Delete", role: .destructive) { store.remove(item.id) }
                    } label: {
                        Image(systemName: "ellipsis").foregroundStyle(Color.secondary)
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22)
                }
                ProgressView(value: p).tint(tintC)
                HStack {
                    Button { openEditor() } label: {
                        HStack(spacing: 4) {
                            Text("\(item.current) of \(item.target)")
                            Image(systemName: "pencil").font(.system(size: 9))
                        }
                        .font(.system(size: 11.5)).foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    stepper("minus") { store.update(item.id) { $0.current = max(0, $0.current - 1) } }
                    stepper("plus") { store.update(item.id) { $0.current += 1 } }
                }
            }
        }
        .popover(isPresented: $showEdit) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Edit goal").font(.system(size: 13, weight: .semibold))
                FieldBox { TextField("Done so far", text: $curText) }
                FieldBox { TextField("Target (any number)", text: $tgtText) }
                Button("Save") {
                    store.update(item.id) {
                        $0.current = max(0, Int(curText.trimmingCharacters(in: .whitespaces)) ?? $0.current)
                        $0.target = max(1, Int(tgtText.trimmingCharacters(in: .whitespaces)) ?? $0.target)
                    }
                    showEdit = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(14).frame(width: 220)
        }
    }

    func openEditor() { curText = String(item.current); tgtText = String(item.target); showEdit = true }

    func stepper(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}

struct HabitsView: View {
    @EnvironmentObject var store: Store
    let suggestions = ["Read newspaper", "Revise yesterday's topics", "Answer writing practice", "Exercise", "Sleep by 11 PM", "No phone for first hour"]
    var body: some View {
        let list = store.items.filter { $0.kind == "habit" }
        Page {
            if list.isEmpty {
                EmptyHint("Build a daily habit. Type one below, or tap a suggestion.")
            }
            ForEach(list) { HabitRow(item: $0, compact: false) }
            SectionLabel("Suggestions")
            ForEach(suggestions.filter { s in !list.contains { $0.title == s } }, id: \.self) { s in
                Button {
                    store.items.insert(Item(kind: "habit", title: s), at: 0)
                } label: {
                    HStack {
                        Image(systemName: "plus.circle").foregroundStyle(Color.secondary)
                        Text(s).font(.system(size: 13))
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct HabitRow: View {
    @EnvironmentObject var store: Store
    @Environment(\.tintC) var tintC
    let item: Item
    let compact: Bool

    var body: some View {
        let set = habitSet(item.days)
        let today = dayKey(0)
        let doneToday = set.contains(today)
        RowCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.system(size: 14, weight: .semibold))
                        Label("\(streak(item.days)) day streak", systemImage: "flame.fill")
                            .font(.system(size: 11)).foregroundStyle(Color.secondary)
                    }
                    Spacer()
                    Button {
                        store.update(item.id) { i in
                            var s = habitSet(i.days)
                            if s.contains(today) { s.remove(today) } else { s.insert(today) }
                            i.days = s.sorted().joined(separator: ",")
                        }
                    } label: {
                        Image(systemName: doneToday ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22))
                            .foregroundStyle(doneToday ? Color.green : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    if !compact {
                        Menu {
                            Button("Delete", role: .destructive) { store.remove(item.id) }
                        } label: {
                            Image(systemName: "ellipsis").foregroundStyle(Color.secondary)
                        }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22)
                    }
                }
                if !compact {
                    HStack(spacing: 0) {
                        ForEach((0..<7).reversed(), id: \.self) { b in
                            VStack(spacing: 4) {
                                Circle()
                                    .fill(set.contains(dayKey(-b)) ? tintC : Color.white.opacity(0.18))
                                    .frame(width: 10, height: 10)
                                Text(dayLetter(b)).font(.system(size: 9)).foregroundStyle(Color.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Notes (list + full-page editor)

func wordCount(_ s: String) -> Int { s.split { $0.isWhitespace || $0.isNewline }.count }

struct NotesView: View {
    @EnvironmentObject var store: Store
    @Binding var openNote: Int64?
    @State private var q = ""

    var body: some View {
        if let id = openNote, store.items.contains(where: { $0.id == id }) {
            NoteDetail(id: id) { openNote = nil }
        } else {
            let list = store.items.filter { n in
                n.kind == "note" && (q.isEmpty || n.title.localizedCaseInsensitiveContains(q) || n.body.localizedCaseInsensitiveContains(q))
            }.sorted { a, b in
                if a.pinned != b.pinned { return a.pinned }
                return max(a.doneAt, a.id) > max(b.doneAt, b.id)
            }
            Page {
                FieldBox {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(Color.secondary)
                        TextField("Search notes", text: $q)
                    }
                }
                if list.isEmpty { EmptyHint("Type a title below to start a note.\nClick a note to open it as a full page.") }
                ForEach(list) { n in
                    Button { openNote = n.id } label: {
                        RowCard {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(n.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                                    Spacer()
                                    if n.pinned { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(Color.orange) }
                                    Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Color.secondary)
                                }
                                if !n.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(n.body.trimmingCharacters(in: .whitespacesAndNewlines))
                                        .font(.system(size: 12)).foregroundStyle(Color.secondary)
                                        .lineLimit(3).multilineTextAlignment(.leading)
                                }
                                Text("\(wordCount(n.body)) words · " + fmt("d MMM, h:mm a", dateOf(max(n.doneAt, n.id))))
                                    .font(.system(size: 10)).foregroundStyle(Color.secondary.opacity(0.8))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct NoteDetail: View {
    @EnvironmentObject var store: Store
    @Environment(\.tintC) var tintC
    let id: Int64
    var close: () -> Void
    @State private var confirmDelete = false
    @State private var flash = ""

    var note: Item? { store.items.first { $0.id == id } }

    func bodyBinding() -> Binding<String> {
        Binding(
            get: { note?.body ?? "" },
            set: { v in store.update(id) { $0.body = v; $0.doneAt = nowMs() } }
        )
    }

    func titleBinding() -> Binding<String> {
        Binding(
            get: { note?.title ?? "" },
            set: { v in store.update(id) { $0.title = v; $0.doneAt = nowMs() } }
        )
    }

    func append(_ text: String) {
        store.update(id) { n in
            var b = n.body
            if !b.isEmpty && !b.hasSuffix("\n") { b += "\n" }
            n.body = b + text
            n.doneAt = nowMs()
        }
    }

    func fullText(_ n: Item) -> String { n.title + "\n\n" + n.body }

    func copyAll(_ n: Item) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fullText(n), forType: .string)
        flash = "Copied to clipboard"
    }

    func export(_ n: Item) {
        NSApp.activate(ignoringOtherApps: true)
        let p = NSSavePanel()
        p.nameFieldStringValue = (n.title.isEmpty ? "note" : n.title) + ".txt"
        p.allowedContentTypes = [.plainText]
        if p.runModal() == .OK, let u = p.url {
            try? fullText(n).write(to: u, atomically: true, encoding: .utf8)
            flash = "Saved as a text file"
        }
    }

    func tool(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        if let n = note {
            let words = wordCount(n.body)
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Button(action: close) {
                        HStack(spacing: 4) { Image(systemName: "chevron.left"); Text("Notes") }
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(tintC)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button { store.update(id) { $0.pinned.toggle() } } label: {
                        Image(systemName: n.pinned ? "pin.fill" : "pin").foregroundStyle(n.pinned ? Color.orange : Color.secondary)
                    }
                    .buttonStyle(.plain).help("Pin to top")
                    Button { copyAll(n) } label: { Image(systemName: "doc.on.doc").foregroundStyle(Color.secondary) }
                        .buttonStyle(.plain).help("Copy the whole note")
                    Button { export(n) } label: { Image(systemName: "square.and.arrow.up").foregroundStyle(Color.secondary) }
                        .buttonStyle(.plain).help("Save as a text file")
                    Button {
                        if confirmDelete { store.remove(id); close() } else { confirmDelete = true }
                    } label: {
                        if confirmDelete {
                            Text("Tap again to delete").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.red)
                        } else {
                            Image(systemName: "trash").foregroundStyle(Color.red.opacity(0.85))
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18).padding(.top, 4)

                TextField("Title", text: titleBinding())
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .padding(.horizontal, 18)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        tool("• Bullet") { append("• ") }
                        tool("☐ Checkbox") { append("☐ ") }
                        tool("☑ Done") { append("☑ ") }
                        tool("— Divider") { append("——————————\n") }
                        tool("📅 Today") { append(fmt("EEEE, d MMMM yyyy", Date()) + "\n") }
                        tool("🕒 Time") { append(fmt("h:mm a", Date()) + " ") }
                    }
                    .padding(.horizontal, 18)
                }

                TextEditor(text: bodyBinding())
                    .font(.system(size: 14.5))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.09)))
                    .overlay(alignment: .topLeading) {
                        if n.body.isEmpty {
                            Text("Start writing…")
                                .font(.system(size: 14.5)).foregroundStyle(Color.secondary.opacity(0.7))
                                .padding(.horizontal, 15).padding(.vertical, 16)
                                .allowsHitTesting(false)
                        }
                    }
                    .padding(.horizontal, 14)

                HStack {
                    Text("\(words) words · \(n.body.count) characters · ~\(max(1, words / 200)) min read")
                    Spacer()
                    Text(flash.isEmpty ? "Edited " + fmt("d MMM, h:mm a", dateOf(max(n.doneAt, n.id))) : flash)
                }
                .font(.system(size: 10.5)).foregroundStyle(Color.secondary)
                .padding(.horizontal, 18).padding(.bottom, 12)
            }
        }
    }
}
