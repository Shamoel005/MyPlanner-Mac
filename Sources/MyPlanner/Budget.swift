import SwiftUI
import AppKit

// MARK: - Categories

struct BCat {
    let name: String
    let emoji: String
    let color: Color
}

let expenseCats = [
    BCat(name: "Food", emoji: "🍔", color: Color(red: 1.00, green: 0.60, blue: 0.30)),
    BCat(name: "Groceries", emoji: "🛒", color: Color(red: 0.30, green: 0.75, blue: 0.50)),
    BCat(name: "Transport", emoji: "🚗", color: Color(red: 0.30, green: 0.62, blue: 1.00)),
    BCat(name: "Shopping", emoji: "🛍️", color: Color(red: 0.93, green: 0.45, blue: 0.75)),
    BCat(name: "Bills", emoji: "💡", color: Color(red: 0.96, green: 0.70, blue: 0.10)),
    BCat(name: "Rent", emoji: "🏠", color: Color(red: 0.55, green: 0.36, blue: 0.96)),
    BCat(name: "Health", emoji: "💊", color: Color(red: 0.08, green: 0.72, blue: 0.65)),
    BCat(name: "Fun", emoji: "🎬", color: Color(red: 0.94, green: 0.27, blue: 0.27)),
    BCat(name: "Travel", emoji: "✈️", color: Color(red: 0.02, green: 0.71, blue: 0.83)),
    BCat(name: "Education", emoji: "📚", color: Color(red: 0.39, green: 0.40, blue: 0.95)),
    BCat(name: "Other", emoji: "📦", color: Color(red: 0.58, green: 0.64, blue: 0.72))
]
let incomeCats = [
    BCat(name: "Salary", emoji: "💼", color: Color(red: 0.07, green: 0.63, blue: 0.31)),
    BCat(name: "Freelance", emoji: "💻", color: Color(red: 0.23, green: 0.51, blue: 0.96)),
    BCat(name: "Gift", emoji: "🎁", color: Color(red: 0.93, green: 0.28, blue: 0.60)),
    BCat(name: "Stipend", emoji: "🎓", color: Color(red: 0.96, green: 0.70, blue: 0.10)),
    BCat(name: "Other", emoji: "➕", color: Color(red: 0.58, green: 0.64, blue: 0.72))
]
let goalIcons = ["✈️", "📱", "🏠", "🚗", "🎓", "💍", "🎁", "💻", "🏝️", "🎯"]

func catOf(_ name: String, _ type: String) -> BCat {
    let list = type == "income" ? incomeCats : expenseCats
    return list.first { $0.name == name } ?? list[list.count - 1]
}

// MARK: - Models (same JSON layout as the Android budget app)

struct Txn: Identifiable, Codable, Equatable {
    var id: Int64
    var type: String
    var amount: Double
    var category: String
    var note: String
    var date: Int64
}

struct SGoal: Identifiable, Codable, Equatable {
    var id: Int64
    var name: String
    var icon: String
    var target: Double
    var saved: Double
    var deadline: Int64
}

struct Bill: Identifiable, Codable, Equatable {
    var id: Int64
    var name: String
    var amount: Double
    var day: Int
    var category: String
    var lastPaid: Int
}

struct LegacyExpense: Codable {
    var id: Int64
    var amount: Double
    var category: String
    var note: String
    var date: Int64
}

struct BudgetData: Codable {
    var budget: Double = 0
    var catBudgets: [String: Double] = [:]
    var txns: [Txn] = []
    var goals: [SGoal] = []
    var bills: [Bill] = []

    init() {}

    private enum LegacyKeys: String, CodingKey { case monthly, expenses }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let l = try decoder.container(keyedBy: LegacyKeys.self)
        var b = try c.decodeIfPresent(Double.self, forKey: .budget)
        if b == nil { b = try l.decodeIfPresent(Double.self, forKey: .monthly) }
        budget = b ?? 0
        catBudgets = try c.decodeIfPresent([String: Double].self, forKey: .catBudgets) ?? [:]
        goals = try c.decodeIfPresent([SGoal].self, forKey: .goals) ?? []
        bills = try c.decodeIfPresent([Bill].self, forKey: .bills) ?? []
        if let t = try c.decodeIfPresent([Txn].self, forKey: .txns) {
            txns = t
        } else if let old = try l.decodeIfPresent([LegacyExpense].self, forKey: .expenses) {
            // Upgrade from the first version of the Mac budget: keep every old expense.
            txns = old.map { Txn(id: $0.id, type: "expense", amount: $0.amount, category: $0.category, note: $0.note, date: $0.date) }
        }
    }
}

final class BudgetStore: ObservableObject {
    @Published var data = BudgetData() { didSet { save() } }
    private let url = supportURL("budget.json")

    init() {
        if let d = try? Data(contentsOf: url), let v = try? JSONDecoder().decode(BudgetData.self, from: d) { data = v }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(data) { try? d.write(to: url, options: .atomic) }
    }

    func upsert(_ t: Txn) {
        if let i = data.txns.firstIndex(where: { $0.id == t.id }) { data.txns[i] = t } else { data.txns.insert(t, at: 0) }
    }

    func csv() -> String {
        var out = "Date,Type,Category,Amount,Note\n"
        for t in data.txns.sorted(by: { $0.date < $1.date }) {
            let note = t.note.replacingOccurrences(of: "\"", with: "\"\"")
            out += "\(fmt("yyyy-MM-dd", dateOf(t.date))),\(t.type),\(t.category),\(t.amount),\"\(note)\"\n"
        }
        return out
    }
}

// MARK: - Helpers

func num(_ s: String) -> Double {
    Double(s.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)) ?? 0
}

func money(_ v: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.locale = Locale(identifier: "en_IN")
    let frac = abs(v).truncatingRemainder(dividingBy: 1) < 0.005 ? 0 : 2
    f.minimumFractionDigits = frac
    f.maximumFractionDigits = frac
    return (v < -0.004 ? "-" : "") + "₹" + (f.string(from: NSNumber(value: abs(v))) ?? "0")
}

func compact(_ v: Double) -> String {
    if v >= 1e7 { return String(format: "%.1fCr", v / 1e7) }
    if v >= 1e5 { return String(format: "%.1fL", v / 1e5) }
    if v >= 1e3 { return String(format: "%.1fK", v / 1e3) }
    return String(Int(v.rounded()))
}

func pct(_ a: Double, _ b: Double) -> Int { b <= 0 ? 0 : Int((a / b * 100).rounded()) }

func ymOf(_ d: Date) -> Int {
    let c = Calendar.current.dateComponents([.year, .month], from: d)
    return (c.year ?? 2000) * 12 + ((c.month ?? 1) - 1)
}
func ymOfMs(_ ms: Int64) -> Int { ymOf(dateOf(ms)) }
func nowYm() -> Int { ymOf(Date()) }
func ymDate(_ ym: Int) -> Date {
    var c = DateComponents()
    c.year = ym / 12; c.month = ym % 12 + 1; c.day = 1
    return Calendar.current.date(from: c) ?? Date()
}
func ymLabel(_ ym: Int) -> String { fmt("MMMM yyyy", ymDate(ym)) }
func ymShort(_ ym: Int) -> String { fmt("MMM yy", ymDate(ym)) }
func monthName(_ ym: Int) -> String { fmt("MMMM", ymDate(ym)) }
func daysIn(_ ym: Int) -> Int { Calendar.current.range(of: .day, in: .month, for: ymDate(ym))?.count ?? 30 }
func dayOfMonth(_ ms: Int64) -> Int { Calendar.current.component(.day, from: dateOf(ms)) }

func dailyTotals(_ tx: [Txn], _ days: Int) -> [Double] {
    var out = [Double](repeating: 0, count: days)
    for t in tx where t.type == "expense" { out[max(0, min(dayOfMonth(t.date), days) - 1)] += t.amount }
    return out
}

struct CatTotal: Identifiable {
    let name: String
    let total: Double
    var id: String { name }
}

extension BudgetData {
    func monthTx(_ ym: Int) -> [Txn] { txns.filter { ymOfMs($0.date) == ym } }
}

extension Array where Element == Txn {
    var expense: Double { filter { $0.type == "expense" }.reduce(0) { $0 + $1.amount } }
    var income: Double { filter { $0.type == "income" }.reduce(0) { $0 + $1.amount } }
    func byCategory() -> [CatTotal] {
        var m: [String: Double] = [:]
        for t in self where t.type == "expense" { m[t.category, default: 0] += t.amount }
        return m.map { CatTotal(name: $0.key, total: $0.value) }.sorted { $0.total > $1.total }
    }
}

func billDueMs(_ b: Bill, _ ym: Int) -> Int64 {
    var c = DateComponents()
    c.year = ym / 12; c.month = ym % 12 + 1; c.day = min(b.day, daysIn(ym)); c.hour = 9
    return msOf(Calendar.current.date(from: c) ?? Date())
}
func nextDueYm(_ b: Bill) -> Int { b.lastPaid == nowYm() ? nowYm() + 1 : nowYm() }
func nextDue(_ b: Bill) -> Int64 { billDueMs(b, nextDueYm(b)) }

// MARK: - Advice engine

struct Advice: Identifiable {
    let id = UUID()
    let emoji: String
    let title: String
    let text: String
    let tone: Int   // 0 info, 1 good, 2 warning
}

func monthAdvice(_ d: BudgetData, _ ym: Int) -> [Advice] {
    var out: [Advice] = []
    let tx = d.monthTx(ym)
    let exp = tx.filter { $0.type == "expense" }
    let spent = exp.expense
    let income = tx.income
    if exp.isEmpty {
        return [Advice(emoji: "📝", title: "Nothing logged yet", text: "Add your expenses as you spend. The more you log, the smarter these insights get.", tone: 0)]
    }
    let isCur = ym == nowYm()
    let days = daysIn(ym)
    let elapsed = isCur ? Calendar.current.component(.day, from: Date()) : days
    let left = days - elapsed
    let b = d.budget
    if b > 0 {
        if spent > b {
            out.append(Advice(emoji: "🚨", title: "Over budget", text: "You are \(money(spent - b)) over your \(money(b)) budget." + (isCur && left > 0 ? " Try a no-spend stretch for the last \(left) days." : ""), tone: 2))
        } else if isCur {
            let used = spent / b
            let time = Double(elapsed) / Double(days)
            let perDay = money((b - spent) / Double(left + 1))
            if used > time + 0.15 {
                out.append(Advice(emoji: "⚠️", title: "Spending is ahead of schedule", text: "You've used \(Int(used * 100))% of your budget but only \(Int(time * 100))% of the month has passed. Aim for about \(perDay) a day from here.", tone: 2))
            } else if used < time - 0.10 {
                out.append(Advice(emoji: "✅", title: "Nicely on track", text: "Only \(Int(used * 100))% of your budget is used. You can spend about \(perDay) a day and still finish within budget.", tone: 1))
            }
            if elapsed >= 5 {
                let proj = spent / Double(elapsed) * Double(days)
                if proj > b { out.append(Advice(emoji: "📈", title: "Projected overspend", text: "At this pace you'll spend about \(money(proj)), which is \(money(proj - b)) over budget.", tone: 2)) }
            }
        } else {
            out.append(Advice(emoji: "✅", title: "Within budget", text: "You finished \(money(b - spent)) under budget. Well done!", tone: 1))
        }
    } else {
        out.append(Advice(emoji: "🎯", title: "Set a monthly budget", text: "Add a budget so I can track your pace and warn you before you overspend.", tone: 0))
    }
    for c in d.catBudgets.keys.sorted() {
        let lim = d.catBudgets[c] ?? 0
        let s = exp.filter { $0.category == c }.reduce(0) { $0 + $1.amount }
        if lim > 0 && s > lim {
            out.append(Advice(emoji: "🔔", title: "\(c) is over its limit", text: "\(money(s)) spent against a \(money(lim)) limit.", tone: 2))
        }
    }
    let cats = tx.byCategory()
    if let top = cats.first, cats.count > 1, spent > 0, top.total / spent > 0.35 {
        out.append(Advice(emoji: "🔍", title: "\(top.name) leads your spending", text: "\(pct(top.total, spent))% of this month (\(money(top.total))) went to \(top.name). Trimming 10% would save \(money(top.total * 0.1)).", tone: 0))
    }
    let prev = d.monthTx(ym - 1).filter { $0.type == "expense" }
    if !prev.isEmpty {
        var prevMap: [String: Double] = [:]
        for t in prev { prevMap[t.category, default: 0] += t.amount }
        var n = 0
        for c in cats {
            let p = prevMap[c.name] ?? 0
            if p > 0 && c.total > p * 1.25 && c.total - p > 500 && n < 2 {
                out.append(Advice(emoji: "📊", title: "\(c.name) is up \(Int((c.total / p - 1) * 100))%", text: "\(money(c.total)) this month vs \(money(p)) last month.", tone: 2))
                n += 1
            }
        }
        let prevTotal = prev.reduce(0) { $0 + $1.amount }
        if !isCur && spent < prevTotal * 0.9 {
            out.append(Advice(emoji: "🎉", title: "Spending is down", text: "\(money(prevTotal - spent)) less than last month.", tone: 1))
        }
    }
    if income > 0 {
        let rate = (income - spent) / income
        if rate < 0 {
            out.append(Advice(emoji: "🚨", title: "Spending exceeds income", text: "You spent \(money(spent - income)) more than you earned this month.", tone: 2))
        } else if rate < 0.10 {
            out.append(Advice(emoji: "💰", title: "Low savings rate", text: "You're saving \(Int(rate * 100))% of your income. A common target is 20%, about \(money(income * 0.2)) a month.", tone: 2))
        } else if rate >= 0.20 {
            out.append(Advice(emoji: "🏆", title: "Great savings rate", text: "You're saving \(Int(rate * 100))% of your income. Consider moving some into a savings goal.", tone: 1))
        }
    } else {
        out.append(Advice(emoji: "💼", title: "Add your income", text: "Log your stipend, salary or other income to see your savings rate.", tone: 0))
    }
    let grouped = Dictionary(grouping: exp, by: { $0.category })
    for c in grouped.keys.sorted() {
        let l = grouped[c] ?? []
        if l.count >= 10 {
            let tot = l.reduce(0) { $0 + $1.amount }
            let avg = tot / Double(l.count)
            if avg < 400 {
                out.append(Advice(emoji: "☕", title: "Small \(c) spends add up", text: "\(l.count) purchases averaging \(money(avg)) total \(money(tot)). Skipping 3 a week would save about \(money(avg * 12)) a month.", tone: 0))
            }
        }
    }
    if let big = exp.max(by: { $0.amount < $1.amount }) {
        out.append(Advice(emoji: "🧾", title: "Biggest expense", text: "\(money(big.amount)) on \(big.note.isEmpty ? big.category : big.note) (\(fmt("d MMM", dateOf(big.date)))).", tone: 0))
    }
    return Array(out.prefix(8))
}

func yearAdvice(_ d: BudgetData, _ yr: Int) -> [Advice] {
    var out: [Advice] = []
    let months = (0..<12).map { d.monthTx(yr * 12 + $0) }
    let exps = months.map { $0.expense }
    let incs = months.map { $0.income }
    let totalExp = exps.reduce(0, +)
    let totalInc = incs.reduce(0, +)
    if totalExp == 0 && totalInc == 0 {
        return [Advice(emoji: "📝", title: "No data for \(yr)", text: "Once you log transactions, yearly insights will appear here.", tone: 0)]
    }
    if totalInc > 0 {
        let rate = (totalInc - totalExp) / totalInc
        if rate >= 0.20 {
            out.append(Advice(emoji: "🏆", title: "Strong year of saving", text: "You saved \(Int(rate * 100))% of your income (\(money(totalInc - totalExp))).", tone: 1))
        } else if rate >= 0 {
            out.append(Advice(emoji: "💰", title: "Room to save more", text: "You saved \(Int(rate * 100))% of income this year. Reaching 20% would add about \(money(totalInc * 0.2 - (totalInc - totalExp))).", tone: 2))
        } else {
            out.append(Advice(emoji: "🚨", title: "Spent more than you earned", text: "Spending was \(money(totalExp - totalInc)) above income this year.", tone: 2))
        }
    }
    if let mx = exps.indices.max(by: { exps[$0] < exps[$1] }), exps[mx] > 0 {
        out.append(Advice(emoji: "📅", title: "Costliest month: \(monthName(yr * 12 + mx))", text: "You spent \(money(exps[mx])). Check what drove it and plan ahead next time.", tone: 0))
    }
    let nz = exps.filter { $0 > 0 }
    if nz.count >= 6 {
        let last3 = nz.suffix(3).reduce(0, +) / 3
        let prev3 = nz.dropLast(3).suffix(3).reduce(0, +) / 3
        if last3 > prev3 * 1.15 {
            out.append(Advice(emoji: "📈", title: "Spending is trending up", text: "Your last 3 months average \(money(last3)), up from \(money(prev3)) before.", tone: 2))
        } else if last3 < prev3 * 0.85 {
            out.append(Advice(emoji: "📉", title: "Spending is trending down", text: "Your last 3 months average \(money(last3)), down from \(money(prev3)) before.", tone: 1))
        }
    }
    let cats = months.flatMap { $0 }.byCategory()
    if let top = cats.first, totalExp > 0 {
        out.append(Advice(emoji: "🔍", title: "\(top.name) is your biggest category", text: "\(pct(top.total, totalExp))% of the year's spending (\(money(top.total))).", tone: 0))
    }
    return out
}

// MARK: - Charts

struct DailyBars: View {
    let values: [Double]
    let todayIdx: Int
    let line: Double
    let color: Color
    var body: some View {
        let maxV = max(values.max() ?? 0, line, 1)
        GeometryReader { g in
            ZStack(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(0..<values.count, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(i == todayIdx ? color : color.opacity(0.45))
                            .frame(height: max(3, CGFloat(values[i] / maxV) * g.size.height))
                    }
                }
                .frame(width: g.size.width, height: g.size.height, alignment: .bottom)
                if line > 0 {
                    Path { p in
                        let y = g.size.height - CGFloat(line / maxV) * g.size.height
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: g.size.width, y: y))
                    }
                    .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
        }
        .frame(height: 90)
    }
}

struct DonutChart: View {
    let parts: [(Color, Double)]
    let top: String
    let bottom: String
    var body: some View {
        let total = max(parts.reduce(0) { $0 + $1.1 }, 1)
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: 18)
            ForEach(0..<parts.count, id: \.self) { i in
                let start = parts.prefix(i).reduce(0) { $0 + $1.1 } / total
                let end = start + parts[i].1 / total
                Circle()
                    .trim(from: CGFloat(start), to: CGFloat(max(start, end - 0.004)))
                    .stroke(parts[i].0, style: StrokeStyle(lineWidth: 18, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 0) {
                Text(top).font(.system(size: 10)).foregroundStyle(Color.secondary)
                Text(bottom).font(.system(size: 15, weight: .bold, design: .rounded))
            }
        }
        .frame(width: 124, height: 124)
        .padding(9)
    }
}

struct YearBars: View {
    let inc: [Double]
    let exp: [Double]
    var body: some View {
        let maxV = max(inc.max() ?? 0, exp.max() ?? 0, 1)
        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(0..<12, id: \.self) { i in
                    HStack(alignment: .bottom, spacing: 2) {
                        Capsule().fill(Color.green).frame(width: 7, height: inc[i] > 0 ? max(4, CGFloat(inc[i] / maxV) * 100) : 0)
                        Capsule().fill(Color(red: 1, green: 0.4, blue: 0.45)).frame(width: 7, height: exp[i] > 0 ? max(4, CGFloat(exp[i] / maxV) * 100) : 0)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 100, alignment: .bottom)
            HStack(spacing: 0) {
                ForEach(["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"].indices, id: \.self) { i in
                    Text(["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"][i])
                        .font(.system(size: 9)).foregroundStyle(Color.secondary).frame(maxWidth: .infinity)
                }
            }
        }
    }
}

struct MiniRing: View {
    let frac: Double
    let color: Color
    let emoji: String
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.14), lineWidth: 6)
            Circle().trim(from: 0, to: CGFloat(min(max(frac, 0), 1)))
                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(emoji).font(.system(size: 20))
        }
        .frame(width: 54, height: 54)
    }
}

// MARK: - Budget screen

enum BForm {
    case txn(Txn), goal(SGoal), bill(Bill), limits
}

struct BudgetView: View {
    @EnvironmentObject var budget: BudgetStore
    @State private var sub = 0
    @State private var ym = nowYm()
    @State private var form: BForm? = nil

    var body: some View {
        ZStack {
            VStack(spacing: 8) {
                Picker("", selection: $sub) {
                    Text("Home").tag(0); Text("Activity").tag(1); Text("Insights").tag(2)
                    Text("Savings").tag(3); Text("Bills").tag(4)
                }
                .pickerStyle(.segmented).labelsHidden()
                .padding(.horizontal, 16)
                Group {
                    switch sub {
                    case 0: OverviewView(ym: $ym, form: $form)
                    case 1: ActivityView(ym: $ym, form: $form)
                    case 2: InsightsView(ym: $ym) { m in ym = m; sub = 1 }
                    case 3: SavingsView(form: $form)
                    default: BillsView(form: $form)
                    }
                }
            }
            if let f = form {
                Group {
                    switch f {
                    case .txn(let t): TxnForm(start: t) { form = nil }
                    case .goal(let g): GoalForm(start: g) { form = nil }
                    case .bill(let b): BillForm(start: b) { form = nil }
                    case .limits: LimitsForm { form = nil }
                    }
                }
                .transition(.opacity)
            }
        }
    }
}

struct MonthSwitcher: View {
    @Binding var ym: Int
    var body: some View {
        HStack {
            Button { ym -= 1 } label: { Image(systemName: "chevron.left").frame(width: 28, height: 28) }.buttonStyle(.plain)
            Spacer()
            Text(ymLabel(ym)).font(.system(size: 15, weight: .semibold))
            Spacer()
            Button { if ym < nowYm() { ym += 1 } } label: {
                Image(systemName: "chevron.right").frame(width: 28, height: 28)
                    .foregroundStyle(ym < nowYm() ? Color.primary : Color.secondary.opacity(0.3))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
    }
}

struct TxnRowView: View {
    let t: Txn
    let showDate: Bool
    let onTap: () -> Void
    var body: some View {
        let c = catOf(t.category, t.type)
        Button(action: onTap) {
            HStack(spacing: 10) {
                Text(c.emoji).font(.system(size: 17))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(c.color.opacity(0.18)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.note.isEmpty ? t.category : t.note).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text(t.category + (showDate ? " · " + fmt("d MMM", dateOf(t.date)) : " · " + fmt("h:mm a", dateOf(t.date))))
                        .font(.system(size: 11)).foregroundStyle(Color.secondary)
                }
                Spacer()
                Text((t.type == "income" ? "+" : "-") + money(t.amount))
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(t.type == "income" ? Color.green : Color.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
    }
}

// MARK: Overview

struct OverviewView: View {
    @EnvironmentObject var budget: BudgetStore
    @Environment(\.tintC) var tintC
    @Binding var ym: Int
    @Binding var form: BForm?
    @State private var qType = "expense"
    @State private var qAmount = ""
    @State private var qNote = ""
    @State private var qCat = "Food"
    @State private var qError = false

    func quickAdd() {
        let a = num(qAmount)
        guard a > 0 else { qError = true; return }
        budget.upsert(Txn(id: nowMs(), type: qType, amount: a, category: qCat, note: qNote.trimmingCharacters(in: .whitespacesAndNewlines), date: nowMs()))
        qAmount = ""; qNote = ""; qError = false
    }

    var body: some View {
        let d = budget.data
        let tx = d.monthTx(ym)
        let spent = tx.expense
        let inc = tx.income
        let isCur = ym == nowYm()
        let days = daysIn(ym)
        let today = Calendar.current.component(.day, from: Date())
        let daysLeft = isCur ? days - today + 1 : 0
        let limit = d.budget
        let left = limit - spent
        let ratio = limit > 0 ? min(1.0, spent / limit) : 0
        let cats = tx.byCategory()
        let daily = dailyTotals(tx, days)
        let upcoming = d.bills.filter { $0.lastPaid != nowYm() }.sorted { nextDue($0) < nextDue($1) }.prefix(3)
        let recent = tx.sorted { $0.date > $1.date }.prefix(5)

        Page {
            MonthSwitcher(ym: $ym)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.04, green: 0.48, blue: 0.37), Color(red: 0.09, green: 0.72, blue: 0.56)], startPoint: .topLeading, endPoint: .bottomTrailing))
                VStack(alignment: .leading, spacing: 7) {
                    if limit > 0 {
                        Text(left >= 0 ? "Left to spend" : "Over budget by").font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.8))
                        Text(money(abs(left))).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(Color.white)
                        ProgressView(value: ratio).tint(spent > limit ? Color(red: 1, green: 0.7, blue: 0.7) : (ratio > 0.8 ? Color(red: 1, green: 0.88, blue: 0.54) : Color.white))
                        HStack {
                            Text("Spent \(money(spent))")
                            Spacer()
                            Text("Budget \(money(limit))")
                        }
                        .font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.9))
                        Text(isCur && left > 0 ? "About \(money(left / Double(daysLeft))) a day for the next \(daysLeft) days"
                             : (left >= 0 ? "Finished \(money(left)) under budget" : (isCur ? "Time to slow down this month" : "Finished \(money(-left)) over budget")))
                            .font(.system(size: 11.5)).foregroundStyle(Color.white.opacity(0.85))
                    } else {
                        Text("Net this month").font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.8))
                        Text(money(inc - spent)).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(Color.white)
                        Text("Set a monthly budget to see what's left to spend.").font(.system(size: 11.5)).foregroundStyle(Color.white.opacity(0.85))
                    }
                    Button { form = .limits } label: {
                        Text(limit > 0 ? "Edit budgets" : "Set budget")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.white)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(Color.white.opacity(0.22)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(18)
            }

            if isCur {
                RowCard {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 6) {
                            PillButton(text: "Expense", selected: qType == "expense") { qType = "expense"; qCat = "Food" }
                            PillButton(text: "Income", selected: qType == "income") { qType = "income"; qCat = "Salary" }
                            Spacer()
                        }
                        HStack(spacing: 8) {
                            Text("₹").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(tintC)
                            TextField("Amount", text: $qAmount)
                                .textFieldStyle(.plain)
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .onSubmit { quickAdd() }
                                .onChange(of: qAmount) { _ in qError = false }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.12)))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(qError ? Color.red : Color.clear, lineWidth: 1.5))
                        FieldBox { TextField("What was it for? (optional)", text: $qNote).font(.system(size: 13)).onSubmit { quickAdd() } }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(qType == "income" ? incomeCats : expenseCats, id: \.name) { c in
                                    Button { qCat = c.name } label: {
                                        Text(c.emoji + " " + c.name)
                                            .font(.system(size: 11.5, weight: .medium))
                                            .padding(.horizontal, 10).padding(.vertical, 5)
                                            .background(Capsule().fill(qCat == c.name ? c.color.opacity(0.55) : Color.white.opacity(0.10)))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        if qError { Text("Type an amount first, like 130").font(.system(size: 11)).foregroundStyle(Color.red) }
                        Button(action: quickAdd) {
                            Text("Add " + qType).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(Capsule().fill(tintC))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 8) {
                statCard("Income", money(inc), Color.green, "")
                statCard("Spent", money(spent), Color(red: 1, green: 0.4, blue: 0.45), "")
                statCard("Saved", money(inc - spent), inc - spent >= 0 ? tintC : Color(red: 1, green: 0.4, blue: 0.45), inc > 0 ? "\(pct(inc - spent, inc))% of income" : "")
            }

            RowCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Daily spending").font(.system(size: 14, weight: .semibold))
                        Spacer()
                        if spent > 0 {
                            Text("avg \(money(spent / Double(isCur ? today : days)))/day").font(.system(size: 11)).foregroundStyle(Color.secondary)
                        }
                    }
                    DailyBars(values: daily, todayIdx: isCur ? today - 1 : -1, line: limit > 0 ? limit / Double(days) : 0, color: tintC)
                    HStack {
                        ForEach([1, 8, 15, 22, days], id: \.self) { n in
                            Text("\(n)").font(.system(size: 9)).foregroundStyle(Color.secondary)
                            if n != days { Spacer() }
                        }
                    }
                    if limit > 0 { Text("Dashed line = daily budget (\(money(limit / Double(days))))").font(.system(size: 10.5)).foregroundStyle(Color.secondary) }
                }
            }

            RowCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Where your money went").font(.system(size: 14, weight: .semibold))
                    if cats.isEmpty { Text("No expenses this month.").font(.system(size: 12)).foregroundStyle(Color.secondary) }
                    ForEach(Array(cats.prefix(6))) { c in
                        let cat = catOf(c.name, "expense")
                        let lim = d.catBudgets[c.name] ?? 0
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(cat.emoji + " " + c.name).font(.system(size: 13, weight: .medium))
                                Spacer()
                                Text(money(c.total)).font(.system(size: 13, weight: .semibold, design: .rounded))
                            }
                            ProgressView(value: lim > 0 ? min(1, c.total / lim) : (spent > 0 ? c.total / spent : 0))
                                .tint(lim > 0 && c.total > lim ? Color.red : cat.color)
                            if lim > 0 {
                                Text("\(money(c.total)) of \(money(lim)) limit").font(.system(size: 10.5))
                                    .foregroundStyle(c.total > lim ? Color.red : Color.secondary)
                            }
                        }
                    }
                }
            }

            if !upcoming.isEmpty {
                RowCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Upcoming bills").font(.system(size: 14, weight: .semibold))
                        ForEach(Array(upcoming)) { b in
                            let due = nextDue(b)
                            let late = due < dayStartMs()
                            HStack {
                                Text(catOf(b.category, "expense").emoji)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(b.name).font(.system(size: 13, weight: .medium))
                                    Text((late ? "Overdue · " : "Due ") + fmt("d MMM", dateOf(due)))
                                        .font(.system(size: 11)).foregroundStyle(late ? Color.red : Color.secondary)
                                }
                                Spacer()
                                Text(money(b.amount)).font(.system(size: 13, weight: .semibold, design: .rounded))
                            }
                        }
                    }
                }
            }

            RowCard {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent transactions").font(.system(size: 14, weight: .semibold))
                    if recent.isEmpty { Text("Nothing yet this month.").font(.system(size: 12)).foregroundStyle(Color.secondary) }
                    ForEach(Array(recent)) { t in TxnRowView(t: t, showDate: true) { form = .txn(t) } }
                }
            }
        }
    }

    func statCard(_ label: String, _ value: String, _ color: Color, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11)).foregroundStyle(Color.secondary)
            Text(value).font(.system(size: 13.5, weight: .bold, design: .rounded)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
            if !sub.isEmpty { Text(sub).font(.system(size: 9.5)).foregroundStyle(Color.secondary) }
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.11)))
    }
}

// MARK: Activity

struct DayGroup: Identifiable {
    let day: Date
    let txs: [Txn]
    var id: Date { day }
}

struct ActivityView: View {
    @EnvironmentObject var budget: BudgetStore
    @Binding var ym: Int
    @Binding var form: BForm?
    @State private var q = ""
    @State private var f = 0

    var body: some View {
        let all = budget.data.monthTx(ym)
        let list = all.filter {
            (f == 0 || (f == 1 && $0.type == "expense") || (f == 2 && $0.type == "income")) &&
            (q.isEmpty || $0.note.localizedCaseInsensitiveContains(q) || $0.category.localizedCaseInsensitiveContains(q))
        }
        let groups = Dictionary(grouping: list, by: { Calendar.current.startOfDay(for: dateOf($0.date)) })
            .map { DayGroup(day: $0.key, txs: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
        Page {
            MonthSwitcher(ym: $ym)
            FieldBox {
                HStack { Image(systemName: "magnifyingglass").foregroundStyle(Color.secondary); TextField("Search notes or categories", text: $q) }
            }
            HStack(spacing: 6) {
                PillButton(text: "All", selected: f == 0) { f = 0 }
                PillButton(text: "Expenses", selected: f == 1) { f = 1 }
                PillButton(text: "Income", selected: f == 2) { f = 2 }
                Spacer()
            }
            HStack {
                Text("\(list.count) transactions").font(.system(size: 11.5)).foregroundStyle(Color.secondary)
                Spacer()
                Text("Net " + money(list.income - list.expense)).font(.system(size: 11.5)).foregroundStyle(Color.secondary)
            }
            if groups.isEmpty { EmptyHint("No transactions found.") }
            ForEach(groups) { g in
                RowCard {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(dayHeader(g.day)).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.secondary)
                            Spacer()
                            if g.txs.expense > 0 { Text("-" + money(g.txs.expense)).font(.system(size: 11.5)).foregroundStyle(Color.secondary) }
                        }
                        ForEach(g.txs) { t in TxnRowView(t: t, showDate: false) { form = .txn(t) } }
                    }
                }
            }
        }
    }

    func dayHeader(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        return fmt("EEE, d MMM", d)
    }
}

// MARK: Insights

struct AdviceRow: View {
    let a: Advice
    var body: some View {
        let tint: Color = a.tone == 1 ? Color.green : (a.tone == 2 ? Color.orange : Color(red: 0.5, green: 0.55, blue: 1))
        RowCard {
            HStack(alignment: .top, spacing: 10) {
                Text(a.emoji).font(.system(size: 17)).frame(width: 34, height: 34).background(Circle().fill(tint.opacity(0.2)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.title).font(.system(size: 13.5, weight: .semibold))
                    Text(a.text).font(.system(size: 12)).foregroundStyle(Color.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct InsightsView: View {
    @EnvironmentObject var budget: BudgetStore
    @Environment(\.tintC) var tintC
    @Binding var ym: Int
    var openMonth: (Int) -> Void
    @State private var mode = 0
    @State private var yr = nowYm() / 12

    var body: some View {
        Page {
            HStack(spacing: 6) {
                PillButton(text: "Monthly", selected: mode == 0) { mode = 0 }
                PillButton(text: "Yearly", selected: mode == 1) { mode = 1 }
                Spacer()
            }
            if mode == 0 { monthly } else { yearly }
        }
    }

    @ViewBuilder var monthly: some View {
        let d = budget.data
        let tx = d.monthTx(ym)
        let spent = tx.expense
        let cats = tx.byCategory()
        let prev = d.monthTx(ym - 1)
        let prevSpent = prev.expense
        MonthSwitcher(ym: $ym)
        RowCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("Spending by category").font(.system(size: 14, weight: .semibold)); Spacer(); Text(money(spent)).font(.system(size: 12)).foregroundStyle(Color.secondary) }
                if cats.isEmpty { Text("No expenses this month.").font(.system(size: 12)).foregroundStyle(Color.secondary) } else {
                    HStack(spacing: 10) {
                        DonutChart(parts: cats.map { (catOf($0.name, "expense").color, $0.total) }, top: "Total", bottom: compact(spent))
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(Array(cats.prefix(6))) { c in
                                HStack(spacing: 6) {
                                    Circle().fill(catOf(c.name, "expense").color).frame(width: 8, height: 8)
                                    Text("\(c.name)  \(pct(c.total, spent))%").font(.system(size: 11.5)).lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
        }
        RowCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Compared with \(ymShort(ym - 1))").font(.system(size: 14, weight: .semibold))
                if prevSpent <= 0 {
                    Text("No spending recorded last month to compare with.").font(.system(size: 12)).foregroundStyle(Color.secondary)
                } else {
                    let delta = spent - prevSpent
                    Text((delta >= 0 ? "▲ " : "▼ ") + money(abs(delta)) + " (\(abs(pct(delta, prevSpent)))%) " + (delta >= 0 ? "more" : "less") + " than last month")
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(delta > 0 ? Color(red: 1, green: 0.4, blue: 0.45) : Color.green)
                    let curMap = Dictionary(uniqueKeysWithValues: cats.map { ($0.name, $0.total) })
                    let prevMap = Dictionary(uniqueKeysWithValues: prev.byCategory().map { ($0.name, $0.total) })
                    let names = Array(Set(curMap.keys).union(prevMap.keys))
                    let diffs = names.map { CatTotal(name: $0, total: (curMap[$0] ?? 0) - (prevMap[$0] ?? 0)) }
                        .sorted { abs($0.total) > abs($1.total) }.prefix(5)
                    ForEach(Array(diffs)) { c in
                        HStack {
                            Text(catOf(c.name, "expense").emoji + " " + c.name).font(.system(size: 12.5))
                            Spacer()
                            Text((c.total >= 0 ? "▲ " : "▼ ") + money(abs(c.total))).font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(c.total > 0 ? Color(red: 1, green: 0.4, blue: 0.45) : Color.green)
                        }
                    }
                }
            }
        }
        ForEach(monthAdvice(d, ym)) { AdviceRow(a: $0) }
        let big = tx.filter { $0.type == "expense" }.sorted { $0.amount > $1.amount }.prefix(3)
        if !big.isEmpty {
            RowCard {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Biggest expenses").font(.system(size: 14, weight: .semibold))
                    ForEach(Array(big)) { t in TxnRowView(t: t, showDate: true) { } }
                }
            }
        }
    }

    @ViewBuilder var yearly: some View {
        let d = budget.data
        let months = (0..<12).map { d.monthTx(yr * 12 + $0) }
        let exps = months.map { $0.expense }
        let incs = months.map { $0.income }
        let totalExp = exps.reduce(0, +)
        let totalInc = incs.reduce(0, +)
        let active = exps.filter { $0 > 0 }.count
        let cats = months.flatMap { $0 }.byCategory()
        HStack {
            Button { yr -= 1 } label: { Image(systemName: "chevron.left").frame(width: 28, height: 28) }.buttonStyle(.plain)
            Spacer()
            Text("\(yr)").font(.system(size: 15, weight: .semibold))
            Spacer()
            Button { if yr < nowYm() / 12 { yr += 1 } } label: {
                Image(systemName: "chevron.right").frame(width: 28, height: 28)
                    .foregroundStyle(yr < nowYm() / 12 ? Color.primary : Color.secondary.opacity(0.3))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        RowCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(yr) at a glance").font(.system(size: 14, weight: .semibold))
                HStack {
                    VStack(alignment: .leading) { Text("Income").font(.system(size: 11)).foregroundStyle(Color.secondary); Text(money(totalInc)).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Color.green) }
                    Spacer()
                    VStack(alignment: .leading) { Text("Spent").font(.system(size: 11)).foregroundStyle(Color.secondary); Text(money(totalExp)).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Color(red: 1, green: 0.4, blue: 0.45)) }
                    Spacer()
                    VStack(alignment: .leading) { Text("Saved").font(.system(size: 11)).foregroundStyle(Color.secondary); Text(money(totalInc - totalExp)).font(.system(size: 15, weight: .bold, design: .rounded)) }
                }
                Text(active > 0 ? "Average spend: \(money(totalExp / Double(active))) a month" + (totalInc > 0 ? " · saving \(pct(totalInc - totalExp, totalInc))% of income" : "") : "No spending logged in \(yr) yet.")
                    .font(.system(size: 11.5)).foregroundStyle(Color.secondary)
            }
        }
        RowCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Income vs spending").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Circle().fill(Color.green).frame(width: 7, height: 7); Text("Income").font(.system(size: 10)).foregroundStyle(Color.secondary)
                    Circle().fill(Color(red: 1, green: 0.4, blue: 0.45)).frame(width: 7, height: 7); Text("Spent").font(.system(size: 10)).foregroundStyle(Color.secondary)
                }
                YearBars(inc: incs, exp: exps)
            }
        }
        ForEach(yearAdvice(d, yr)) { AdviceRow(a: $0) }
        RowCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Top categories").font(.system(size: 14, weight: .semibold))
                if cats.isEmpty { Text("No expenses this year.").font(.system(size: 12)).foregroundStyle(Color.secondary) }
                ForEach(Array(cats.prefix(6))) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(catOf(c.name, "expense").emoji + " " + c.name).font(.system(size: 12.5, weight: .medium))
                            Spacer()
                            Text(money(c.total)).font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        }
                        ProgressView(value: totalExp > 0 ? c.total / totalExp : 0).tint(catOf(c.name, "expense").color)
                    }
                }
            }
        }
        RowCard {
            VStack(alignment: .leading, spacing: 4) {
                HStack { Text("Month by month").font(.system(size: 14, weight: .semibold)); Spacer(); Text("tap a month").font(.system(size: 10.5)).foregroundStyle(Color.secondary) }
                HStack {
                    Text("Month").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Income").frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Spent").frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Saved").frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.system(size: 10.5)).foregroundStyle(Color.secondary)
                ForEach((0..<12).reversed().filter { !months[$0].isEmpty }, id: \.self) { m in
                    let net = incs[m] - exps[m]
                    Button { openMonth(yr * 12 + m) } label: {
                        HStack {
                            Text(String(monthName(yr * 12 + m).prefix(3))).font(.system(size: 12.5, weight: .medium)).frame(maxWidth: .infinity, alignment: .leading)
                            Text("₹" + compact(incs[m])).foregroundStyle(Color.green).frame(maxWidth: .infinity, alignment: .trailing)
                            Text("₹" + compact(exps[m])).frame(maxWidth: .infinity, alignment: .trailing)
                            Text((net < 0 ? "-" : "") + "₹" + compact(abs(net))).fontWeight(.semibold)
                                .foregroundStyle(net >= 0 ? tintC : Color(red: 1, green: 0.4, blue: 0.45)).frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .font(.system(size: 12))
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if months.allSatisfy({ $0.isEmpty }) { Text("No data for \(yr) yet.").font(.system(size: 12)).foregroundStyle(Color.secondary) }
            }
        }
    }
}

// MARK: Savings goals

struct SavingsView: View {
    @EnvironmentObject var budget: BudgetStore
    @Environment(\.tintC) var tintC
    @Binding var form: BForm?

    var body: some View {
        let goals = budget.data.goals
        let totalT = goals.reduce(0) { $0 + $1.target }
        let totalS = goals.reduce(0) { $0 + min($1.saved, $1.target) }
        Page {
            Button { form = .goal(SGoal(id: nowMs(), name: "", icon: "🎯", target: 0, saved: 0, deadline: 0)) } label: {
                HStack { Image(systemName: "plus.circle.fill"); Text("New savings goal") }
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 9).background(Capsule().fill(tintC))
            }
            .buttonStyle(.plain)
            if goals.isEmpty { EmptyHint("Save for a trip, a gadget, books or anything you want.\nTap “New savings goal”.") } else {
                RowCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Saved so far").font(.system(size: 11.5)).foregroundStyle(Color.secondary)
                        Text(money(totalS)).font(.system(size: 24, weight: .bold, design: .rounded))
                        ProgressView(value: totalT > 0 ? totalS / totalT : 0).tint(tintC)
                        Text("of \(money(totalT)) across \(goals.count) goal\(goals.count == 1 ? "" : "s")").font(.system(size: 11)).foregroundStyle(Color.secondary)
                    }
                }
            }
            ForEach(goals.sorted { ($0.deadline == 0 ? Int64.max : $0.deadline) < ($1.deadline == 0 ? Int64.max : $1.deadline) }) { g in
                SavingsCard(g: g, form: $form)
            }
        }
    }
}

struct SavingsCard: View {
    @EnvironmentObject var budget: BudgetStore
    @Environment(\.tintC) var tintC
    let g: SGoal
    @Binding var form: BForm?
    @State private var show = false
    @State private var amt = ""

    func apply(_ delta: Double) {
        guard let i = budget.data.goals.firstIndex(where: { $0.id == g.id }) else { return }
        budget.data.goals[i].saved = max(0, budget.data.goals[i].saved + delta)
        amt = ""
        show = false
    }

    var body: some View {
        let frac = g.target > 0 ? g.saved / g.target : 0
        let reached = g.target > 0 && g.saved >= g.target
        RowCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    MiniRing(frac: frac, color: reached ? Color.green : tintC, emoji: g.icon)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(g.name).font(.system(size: 14.5, weight: .bold)).lineLimit(1)
                        Text("\(money(g.saved)) of \(money(g.target))").font(.system(size: 12)).foregroundStyle(Color.secondary)
                        if reached {
                            Text("Goal reached! 🎉").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.green)
                        } else if g.deadline > 0 {
                            let months = max(1.0, ((Double(g.deadline) - Double(nowMs())) / (30.44 * 86_400_000)).rounded(.up))
                            let late = g.deadline < nowMs()
                            Text(late ? "Deadline passed · \(money(g.target - g.saved)) to go" : "Save \(money((g.target - g.saved) / months))/month to finish by \(fmt("d MMM yyyy", dateOf(g.deadline)))")
                                .font(.system(size: 11)).foregroundStyle(late ? Color.red : Color.secondary)
                        } else {
                            Text("\(money(g.target - g.saved)) to go").font(.system(size: 11)).foregroundStyle(Color.secondary)
                        }
                    }
                    Spacer()
                    Text("\(min(100, Int(frac * 100)))%").font(.system(size: 16, weight: .bold, design: .rounded))
                }
                HStack(spacing: 8) {
                    Button { show = true } label: {
                        Text("Add or withdraw").font(.system(size: 12, weight: .semibold)).foregroundStyle(tintC)
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                            .background(Capsule().fill(tintC.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                    Button { form = .goal(g) } label: {
                        Text("Edit").font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 16).padding(.vertical, 7)
                            .background(Capsule().fill(Color.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .popover(isPresented: $show) {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(g.icon) \(g.name)").font(.system(size: 13, weight: .semibold))
                FieldBox { TextField("Amount in ₹", text: $amt) }
                HStack(spacing: 6) {
                    ForEach([500, 1000, 5000], id: \.self) { v in PillButton(text: "+\(v)", selected: false) { amt = String(v) } }
                }
                HStack {
                    Button("Withdraw") { let a = num(amt); if a > 0 { apply(-a) } }
                    Spacer()
                    Button("Add") { let a = num(amt); if a > 0 { apply(a) } }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(14).frame(width: 240)
        }
    }
}

// MARK: Bills

struct BillsView: View {
    @EnvironmentObject var budget: BudgetStore
    @Environment(\.tintC) var tintC
    @Binding var form: BForm?

    var body: some View {
        let bills = budget.data.bills
        let total = bills.reduce(0) { $0 + $1.amount }
        let paid = bills.filter { $0.lastPaid == nowYm() }.reduce(0) { $0 + $1.amount }
        Page {
            Button { form = .bill(Bill(id: nowMs(), name: "", amount: 0, day: 1, category: "Bills", lastPaid: -1)) } label: {
                HStack { Image(systemName: "plus.circle.fill"); Text("New recurring bill") }
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 9).background(Capsule().fill(tintC))
            }
            .buttonStyle(.plain)
            if bills.isEmpty { EmptyHint("Add rent, coaching fees, subscriptions or any recurring bill.") } else {
                RowCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("This month").font(.system(size: 11.5)).foregroundStyle(Color.secondary)
                        Text("\(money(paid)) paid of \(money(total))").font(.system(size: 17, weight: .bold, design: .rounded))
                        ProgressView(value: total > 0 ? paid / total : 0).tint(tintC)
                    }
                }
            }
            ForEach(bills.sorted { nextDue($0) < nextDue($1) }) { b in
                let isPaid = b.lastPaid == nowYm()
                let due = nextDue(b)
                let late = !isPaid && due < dayStartMs()
                let c = catOf(b.category, "expense")
                RowCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Text(c.emoji).font(.system(size: 19)).frame(width: 40, height: 40).background(Circle().fill(c.color.opacity(0.18)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(b.name).font(.system(size: 14, weight: .bold)).lineLimit(1)
                                Text(isPaid ? "Paid · next on \(fmt("d MMM", dateOf(due)))" : (late ? "Overdue since " : "Due ") + fmt("d MMM", dateOf(due)))
                                    .font(.system(size: 11.5)).foregroundStyle(late ? Color.red : Color.secondary)
                            }
                            Spacer()
                            Text(money(b.amount)).font(.system(size: 14, weight: .bold, design: .rounded))
                        }
                        HStack(spacing: 8) {
                            if !isPaid {
                                Button { pay(b) } label: {
                                    Text("Mark as paid").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.white)
                                        .frame(maxWidth: .infinity).padding(.vertical, 7).background(Capsule().fill(tintC))
                                }
                                .buttonStyle(.plain)
                            }
                            Button { form = .bill(b) } label: {
                                Text("Edit").font(.system(size: 12, weight: .medium))
                                    .padding(.horizontal, 16).padding(.vertical, 7).background(Capsule().fill(Color.white.opacity(0.10)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    func pay(_ b: Bill) {
        budget.upsert(Txn(id: nowMs(), type: "expense", amount: b.amount, category: b.category, note: b.name, date: nowMs()))
        if let i = budget.data.bills.firstIndex(where: { $0.id == b.id }) { budget.data.bills[i].lastPaid = nowYm() }
    }
}

// MARK: Forms (shown as an overlay inside the panel)

struct FormShell<Content: View>: View {
    let title: String
    var canDelete: Bool
    let onSave: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void
    let content: Content

    init(title: String, canDelete: Bool = false, onSave: @escaping () -> Void, onDelete: @escaping () -> Void = {},
         onCancel: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title; self.canDelete = canDelete; self.onSave = onSave
        self.onDelete = onDelete; self.onCancel = onCancel; self.content = content()
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).onTapGesture(perform: onCancel)
            VStack(spacing: 12) {
                Text(title).font(.system(size: 16, weight: .bold, design: .rounded)).frame(maxWidth: .infinity, alignment: .leading)
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) { content }
                }
                HStack {
                    if canDelete { Button("Delete", role: .destructive, action: onDelete) }
                    Spacer()
                    Button("Cancel", action: onCancel)
                    Button("Save", action: onSave).keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
            .frame(maxWidth: 370, maxHeight: 580)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(red: 0.10, green: 0.11, blue: 0.20)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
            .padding(14)
        }
    }
}

struct CatPicker: View {
    let cats: [BCat]
    @Binding var selected: String
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(cats, id: \.name) { c in
                Button { selected = c.name } label: {
                    VStack(spacing: 2) {
                        Text(c.emoji).font(.system(size: 18))
                        Text(c.name).font(.system(size: 9.5)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected == c.name ? c.color.opacity(0.35) : Color.white.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(selected == c.name ? c.color : Color.clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct TxnForm: View {
    @EnvironmentObject var budget: BudgetStore
    let start: Txn
    let close: () -> Void
    @State private var type: String
    @State private var amount: String
    @State private var cat: String
    @State private var note: String
    @State private var date: Date
    @State private var error = false

    init(start: Txn, close: @escaping () -> Void) {
        self.start = start; self.close = close
        _type = State(initialValue: start.type)
        _amount = State(initialValue: start.amount.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(start.amount)) : String(start.amount))
        _cat = State(initialValue: start.category)
        _note = State(initialValue: start.note)
        _date = State(initialValue: dateOf(start.date))
    }

    var body: some View {
        FormShell(title: "Edit transaction", canDelete: true, onSave: {
            let a = num(amount)
            if a <= 0 { error = true; return }
            var t = start
            t.type = type; t.amount = a; t.category = cat; t.note = note.trimmingCharacters(in: .whitespacesAndNewlines); t.date = msOf(date)
            budget.upsert(t)
            close()
        }, onDelete: {
            budget.data.txns.removeAll { $0.id == start.id }
            close()
        }, onCancel: close) {
            HStack(spacing: 6) {
                PillButton(text: "Expense", selected: type == "expense") { type = "expense"; cat = "Food" }
                PillButton(text: "Income", selected: type == "income") { type = "income"; cat = "Salary" }
            }
            FieldBox { HStack { Text("₹"); TextField(error ? "Enter an amount" : "Amount", text: $amount) } }
            CatPicker(cats: type == "income" ? incomeCats : expenseCats, selected: $cat)
            FieldBox { TextField("Note (optional)", text: $note) }
            DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
        }
    }
}

struct GoalForm: View {
    @EnvironmentObject var budget: BudgetStore
    let start: SGoal
    let close: () -> Void
    @State private var name: String
    @State private var icon: String
    @State private var target: String
    @State private var saved: String
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var error = false

    init(start: SGoal, close: @escaping () -> Void) {
        self.start = start; self.close = close
        _name = State(initialValue: start.name)
        _icon = State(initialValue: start.icon)
        _target = State(initialValue: start.target > 0 ? String(Int(start.target)) : "")
        _saved = State(initialValue: start.saved > 0 ? String(Int(start.saved)) : "")
        _hasDeadline = State(initialValue: start.deadline > 0)
        _deadline = State(initialValue: start.deadline > 0 ? dateOf(start.deadline) : (Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()))
    }

    var body: some View {
        FormShell(title: budget.data.goals.contains { $0.id == start.id } ? "Edit goal" : "New savings goal",
                  canDelete: budget.data.goals.contains { $0.id == start.id }, onSave: {
            let t = num(target)
            if name.trimmingCharacters(in: .whitespaces).isEmpty || t <= 0 { error = true; return }
            var g = start
            g.name = name.trimmingCharacters(in: .whitespaces); g.icon = icon; g.target = t; g.saved = num(saved)
            g.deadline = hasDeadline ? msOf(deadline) : 0
            if let i = budget.data.goals.firstIndex(where: { $0.id == g.id }) { budget.data.goals[i] = g } else { budget.data.goals.append(g) }
            close()
        }, onDelete: {
            budget.data.goals.removeAll { $0.id == start.id }
            close()
        }, onCancel: close) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(goalIcons, id: \.self) { e in
                        Button { icon = e } label: {
                            Text(e).font(.system(size: 20)).frame(width: 38, height: 38)
                                .background(Circle().fill(icon == e ? Color.white.opacity(0.25) : Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            FieldBox { TextField(error ? "Name and target are required" : "Goal name (e.g. Delhi coaching trip)", text: $name) }
            FieldBox { HStack { Text("₹"); TextField("Target amount", text: $target) } }
            FieldBox { HStack { Text("₹"); TextField("Already saved", text: $saved) } }
            Toggle("Has a deadline", isOn: $hasDeadline)
            if hasDeadline { DatePicker("Deadline", selection: $deadline, displayedComponents: .date) }
        }
    }
}

struct BillForm: View {
    @EnvironmentObject var budget: BudgetStore
    let start: Bill
    let close: () -> Void
    @State private var name: String
    @State private var amount: String
    @State private var day: String
    @State private var cat: String
    @State private var error = false

    init(start: Bill, close: @escaping () -> Void) {
        self.start = start; self.close = close
        _name = State(initialValue: start.name)
        _amount = State(initialValue: start.amount > 0 ? String(Int(start.amount)) : "")
        _day = State(initialValue: String(start.day))
        _cat = State(initialValue: start.category)
    }

    var body: some View {
        let exists = budget.data.bills.contains { $0.id == start.id }
        FormShell(title: exists ? "Edit bill" : "New recurring bill", canDelete: exists, onSave: {
            let a = num(amount)
            let d = Int(day.trimmingCharacters(in: .whitespaces)) ?? 0
            if name.trimmingCharacters(in: .whitespaces).isEmpty || a <= 0 || d < 1 || d > 31 { error = true; return }
            var b = start
            b.name = name.trimmingCharacters(in: .whitespaces); b.amount = a; b.day = d; b.category = cat
            if let i = budget.data.bills.firstIndex(where: { $0.id == b.id }) { budget.data.bills[i] = b } else { budget.data.bills.append(b) }
            close()
        }, onDelete: {
            budget.data.bills.removeAll { $0.id == start.id }
            close()
        }, onCancel: close) {
            FieldBox { TextField(error ? "Fill name, amount and a day (1-31)" : "Name (e.g. Rent, Test series)", text: $name) }
            FieldBox { HStack { Text("₹"); TextField("Amount every month", text: $amount) } }
            FieldBox { TextField("Due day of month (1-31)", text: $day) }
            CatPicker(cats: expenseCats, selected: $cat)
        }
    }
}

struct LimitsForm: View {
    @EnvironmentObject var budget: BudgetStore
    let close: () -> Void
    @State private var total = ""
    @State private var limits: [String: String] = [:]

    init(close: @escaping () -> Void) { self.close = close }

    var body: some View {
        FormShell(title: "Monthly budget", onSave: {
            budget.data.budget = num(total)
            var m: [String: Double] = [:]
            for (k, v) in limits { let x = num(v); if x > 0 { m[k] = x } }
            budget.data.catBudgets = m
            close()
        }, onCancel: close) {
            FieldBox { HStack { Text("₹"); TextField("Total budget per month", text: $total) } }
            Text("Tip: a popular split is 50% needs, 30% wants and 20% savings.").font(.system(size: 11)).foregroundStyle(Color.secondary)
            Text("Category limits (optional)").font(.system(size: 12, weight: .semibold))
            ForEach(expenseCats, id: \.name) { c in
                HStack {
                    Text(c.emoji + " " + c.name).font(.system(size: 12.5)).frame(width: 110, alignment: .leading)
                    FieldBox { HStack { Text("₹"); TextField("none", text: Binding(get: { limits[c.name] ?? "" }, set: { limits[c.name] = $0 })) } }
                }
            }
        }
        .onAppear {
            let d = budget.data
            total = d.budget > 0 ? String(Int(d.budget)) : ""
            for c in expenseCats { if let v = d.catBudgets[c.name], v > 0 { limits[c.name] = String(Int(v)) } }
        }
    }
}
