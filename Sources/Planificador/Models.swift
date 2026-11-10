import Foundation

enum EventKind: String, Codable, CaseIterable, Identifiable {
    case trabajo = "Trabajo", personal = "Personal", bienestar = "Bienestar", estudio = "Estudio"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .trabajo: "briefcase.fill"
        case .personal: "sparkles"
        case .bienestar: "heart.fill"
        case .estudio: "book.fill"
        }
    }
}

struct PlanEvent: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var notes = ""
    var start: Date
    var end: Date
    var kind: EventKind = .personal
    var reminderMinutes: Int? = 15
    // `reminderMinutes` is kept so older saved plans still decode.
    var reminderOffsets: [Int]? = nil
    var addToCalendar = true
    var calendarEventID: String? = nil
    var tags: [String]? = nil
    var isDone: Bool? = nil
    var completedAt: Date? = nil
    var reminders: [Int] { reminderOffsets ?? reminderMinutes.map { [$0] } ?? [] }
    var isClosed: Bool { isDone == true }
}

struct PlanTask: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var notes = ""
    var due: Date
    var isDone = false
    var reminderMinutes: Int? = 15
    var reminderOffsets: [Int]? = nil
    var addToCalendar: Bool? = nil
    var calendarEventID: String? = nil
    var tags: [String]? = nil
    var completedAt: Date? = nil
    var reminders: [Int] { reminderOffsets ?? reminderMinutes.map { [$0] } ?? [] }
    var isOnCalendar: Bool { addToCalendar ?? false }
}

struct Milestone: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var isDone = false
    var dueDate: Date = .now
    var notes = ""
    var tags: [String]? = nil
    var completedAt: Date? = nil
}

struct PlanGoal: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var notes = ""
    var targetDate: Date
    var milestones: [Milestone] = []
    var tags: [String]? = nil
    var isDone: Bool? = nil
    var completedAt: Date? = nil
    var isClosed: Bool { isDone == true }
    var progress: Double {
        guard !milestones.isEmpty else { return 0 }
        return Double(milestones.filter(\.isDone).count) / Double(milestones.count)
    }
}

enum ClosureTiming: String {
    case early = "Antes de tiempo"
    case onTime = "A tiempo"
    case late = "Con atraso"

    static func classify(closed: Date?, deadline: Date, includesTime: Bool) -> Self? {
        guard let closed else { return nil }
        let calendar = Calendar.current
        if includesTime {
            if closed.timeIntervalSince(deadline) > 60 { return .late }
            if closed >= deadline { return .onTime }
            return calendar.isDate(closed, inSameDayAs: deadline) ? .onTime : .early
        }
        let closedDay = calendar.startOfDay(for: closed)
        let dueDay = calendar.startOfDay(for: deadline)
        if closedDay > dueDay { return .late }
        return closedDay == dueDay ? .onTime : .early
    }

    static func differenceText(closed: Date?, deadline: Date, includesTime: Bool) -> String? {
        guard let closed else { return nil }
        let calendar = Calendar.current
        if !includesTime {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: closed),
                                               to: calendar.startOfDay(for: deadline)).day ?? 0
            if days == 0 { return "En la fecha límite" }
            let count = abs(days)
            return "\(count) día\(count == 1 ? "" : "s") \(days > 0 ? "antes" : "después")"
        }
        let seconds = abs(Int(closed.timeIntervalSince(deadline)))
        if seconds <= 60 { return "En la hora prevista" }
        let (count, unit): (Int, String) = seconds >= 86400 ? (seconds / 86400, "día") :
            seconds >= 3600 ? (seconds / 3600, "hora") : (seconds / 60, "minuto")
        return "\(count) \(unit)\(count == 1 ? "" : "s") \(closed < deadline ? "antes" : "después")"
    }
}

enum ActivityTags {
    static func clean(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, seen.insert(value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)).inserted else { return nil }
            return value
        }
    }
}

struct ActivityRecord: Identifiable {
    enum Kind: String { case task = "Tarea", event = "Compromiso", goal = "Meta", milestone = "Hito" }
    let id: UUID
    let title: String
    let kind: Kind
    let deadline: Date
    let includesTime: Bool
    let isClosed: Bool
    let completedAt: Date?
    let tags: [String]
    var timing: ClosureTiming? { isClosed ? ClosureTiming.classify(closed: completedAt, deadline: deadline, includesTime: includesTime) : nil }
    var isOverdue: Bool {
        guard !isClosed else { return false }
        if includesTime { return deadline < .now }
        return Calendar.current.startOfDay(for: deadline) < Calendar.current.startOfDay(for: .now)
    }
}

enum MoneyKind: String, Codable, CaseIterable, Identifiable {
    case expense = "Gasto", income = "Ingreso"
    var id: String { rawValue }
}

struct MoneyCategory: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var symbol: String
    var tint: String
    var kind: MoneyKind
    var monthlyLimit: Double? = nil
    var emoji: String? = nil
    var isDebtPayment: Bool? = nil
    var archived: Bool? = nil
    var isArchived: Bool { archived == true }
}

struct MoneyEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var amount: Double
    var date: Date
    var kind: MoneyKind
    var categoryID: UUID
    var notes = ""
    var accountID: UUID? = nil
    var debtID: UUID? = nil
    var debtAction: DebtAction? = nil
    var fixedPaymentID: UUID? = nil
    var countsAsExpense: Bool { kind == .expense && debtAction != .payment }
}

enum DebtAction: String, Codable { case charge, payment }
enum DebtKind: String, Codable, CaseIterable, Identifiable {
    case creditCard = "Tarjeta de crédito", loan = "Préstamo", other = "Otra deuda"
    var id: String { rawValue }
    var symbol: String { self == .creditCard ? "creditcard.fill" : self == .loan ? "building.columns.fill" : "doc.text.fill" }
}
struct MoneyDebt: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var kind: DebtKind = .creditCard
    var openingBalance: Double = 0
    var creditLimit: Double? = nil
    var paymentDate: Date? = nil
    var notes = ""
}
enum PaymentFrequency: String, Codable, CaseIterable, Identifiable {
    case weekly = "Semanal"
    case biweekly = "Quincenal"
    case monthly = "Mensual"
    case bimonthly = "Bimestral"
    case quarterly = "Trimestral"
    case semiannual = "Semestral"
    case yearly = "Anual"
    case once = "Una vez"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .weekly: "calendar.day.timeline.left"
        case .biweekly: "calendar.badge.plus"
        case .monthly: "calendar"
        case .bimonthly: "2.circle.fill"
        case .quarterly: "3.circle.fill"
        case .semiannual: "6.circle.fill"
        case .yearly: "sparkles"
        case .once: "1.circle.fill"
        }
    }

    var standardMonths: Int? {
        switch self {
        case .weekly, .biweekly, .once: nil
        case .monthly: 1
        case .bimonthly: 2
        case .quarterly: 3
        case .semiannual: 6
        case .yearly: 12
        }
    }

    var isProratedByMonths: Bool {
        switch self {
        case .bimonthly, .quarterly, .semiannual, .yearly, .once: true
        case .weekly, .biweekly, .monthly: false
        }
    }

    var monthlyTargetChecks: Int {
        switch self {
        case .weekly: 4
        case .biweekly: 2
        case .monthly, .bimonthly, .quarterly, .semiannual, .yearly, .once: 1
        }
    }

    func nextDueDate(from date: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .weekly: calendar.date(byAdding: .day, value: 7, to: date) ?? date
        case .biweekly: calendar.date(byAdding: .day, value: 14, to: date) ?? date
        case .monthly: calendar.date(byAdding: .month, value: 1, to: date) ?? date
        case .bimonthly: calendar.date(byAdding: .month, value: 2, to: date) ?? date
        case .quarterly: calendar.date(byAdding: .month, value: 3, to: date) ?? date
        case .semiannual: calendar.date(byAdding: .month, value: 6, to: date) ?? date
        case .yearly: calendar.date(byAdding: .year, value: 1, to: date) ?? date
        case .once: date
        }
    }

    func previousDueDate(from date: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .weekly: calendar.date(byAdding: .day, value: -7, to: date) ?? date
        case .biweekly: calendar.date(byAdding: .day, value: -14, to: date) ?? date
        case .monthly: calendar.date(byAdding: .month, value: -1, to: date) ?? date
        case .bimonthly: calendar.date(byAdding: .month, value: -2, to: date) ?? date
        case .quarterly: calendar.date(byAdding: .month, value: -3, to: date) ?? date
        case .semiannual: calendar.date(byAdding: .month, value: -6, to: date) ?? date
        case .yearly: calendar.date(byAdding: .year, value: -1, to: date) ?? date
        case .once: date
        }
    }
}
enum FixedPaymentScope: String, Codable, CaseIterable, Identifiable {
    case personal = "Personal"
    case couple = "En pareja"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .personal: "person.fill"
        case .couple: "person.2.fill"
        }
    }
}

struct FixedPayment: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var amount: Double = 0
    var nextDue: Date = .now
    var frequency: PaymentFrequency = .monthly
    var categoryID: UUID? = nil
    var notes = ""
    var isActive = true
    var cycleStart: Date? = .now
    var monthlyChecks: [String: Int]? = nil
    var scope: FixedPaymentScope? = .personal
    var tags: [String]? = nil

    var effectiveScope: FixedPaymentScope { scope ?? .personal }
}


struct MoneyAccount: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var openingBalance: Double
    var symbol: String = "building.columns.fill"
}

struct MoneyTransfer: Identifiable, Codable, Equatable {
    var id = UUID()
    var amount: Double
    var date: Date
    var fromAccountID: UUID? = nil // nil means money available outside boxes.
    var toAccountID: UUID? = nil
    var notes = ""
}

enum BudgetPeriod: String, Codable, CaseIterable, Identifiable {
    case week = "Semana", month = "Mes", custom = "Personalizado"
    var id: String { rawValue }
}

struct BudgetPlan: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var limit: Double
    var period: BudgetPeriod
    var categoryID: UUID? = nil
    var start: Date = .now
    var end: Date = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
}

struct PlannerData: Codable {
    var events: [PlanEvent] = []
    var tasks: [PlanTask] = []
    var goals: [PlanGoal] = []
    var entries: [MoneyEntry] = []
    var accounts: [MoneyAccount] = []
    var debts: [MoneyDebt]? = nil
    var fixedPayments: [FixedPayment]? = nil
    var transfers: [MoneyTransfer]? = nil
    var availableOpeningBalance: Double? = nil
    var budgets: [BudgetPlan] = []
    var categories: [MoneyCategory] = [
        .init(name: "Vivienda", symbol: "house.fill", tint: "#B995FF", kind: .expense),
        .init(name: "Comida", symbol: "fork.knife", tint: "#FFB88C", kind: .expense),
        .init(name: "Transporte", symbol: "car.fill", tint: "#7FCBD7", kind: .expense),
        .init(name: "Salud", symbol: "heart.fill", tint: "#F59EB7", kind: .expense),
        .init(name: "Ocio", symbol: "sparkles", tint: "#E2CE83", kind: .expense),
        .init(name: "Otros gastos", symbol: "square.grid.2x2.fill", tint: "#A9B6C9", kind: .expense),
        .init(name: "Sueldo", symbol: "briefcase.fill", tint: "#8ED6B4", kind: .income),
        .init(name: "Otros ingresos", symbol: "plus.circle.fill", tint: "#A8C4FF", kind: .income),
        .init(name: "Deudas", symbol: "creditcard.fill", tint: "#BDA6FF", kind: .expense, isDebtPayment: true)
    ]
    var currencyCode = "MXN"
    var name = "Planificador Personal"
    var appearance = "dark"
    var weekStartsOn = 5
    var simulatedIncome: Double? = nil
    var simulatedIncomeMode: String? = nil
    var simulatedIncomeScope: String? = nil
    var mainAccountName: String? = nil
}

struct RunningBalanceStep {
    let balanceAfter: Double
    let delta: Double
}

enum FinanceMath {
    static func debtBalance(_ debt: MoneyDebt, in data: PlannerData) -> Double {
        debt.openingBalance + data.entries.filter { $0.debtID == debt.id }.reduce(0) {
            $0 + ($1.debtAction == .charge ? $1.amount : $1.debtAction == .payment ? -$1.amount : 0)
        }
    }

    static func balance(accountID: UUID?, in data: PlannerData) -> Double {
        let opening: Double
        if let accountID {
            opening = data.accounts.first(where: { $0.id == accountID })?.openingBalance ?? 0
        } else {
            opening = data.availableOpeningBalance ?? 0
        }
        let entries = data.entries.filter { $0.accountID == accountID && $0.debtAction != .charge }.reduce(0.0) {
            $0 + ($1.kind == .income ? $1.amount : -$1.amount)
        }
        let transfers = (data.transfers ?? []).reduce(0.0) { value, transfer in
            value + (transfer.toAccountID == accountID ? transfer.amount : 0)
                - (transfer.fromAccountID == accountID ? transfer.amount : 0)
        }
        return opening + entries + transfers
    }

    static func total(in data: PlannerData) -> Double {
        balance(accountID: nil, in: data) + data.accounts.reduce(0) { $0 + balance(accountID: $1.id, in: data) }
    }

    static func monthDistance(from start: Date, to end: Date, calendar: Calendar = .current) -> Int {
        let startMonths = calendar.component(.year, from: start) * 12 + calendar.component(.month, from: start)
        let endMonths = calendar.component(.year, from: end) * 12 + calendar.component(.month, from: end)
        return endMonths - startMonths
    }

    static func savingMonths(for payment: FixedPayment, now: Date = .now, calendar: Calendar = .current) -> Int {
        max(1, monthDistance(from: payment.cycleStart ?? now, to: payment.nextDue, calendar: calendar))
    }

    static func monthlyEquivalent(for payment: FixedPayment, now: Date = .now, calendar: Calendar = .current) -> Double {
        guard payment.isActive, payment.amount.isFinite, payment.amount > 0 else { return 0 }
        switch payment.frequency {
        case .weekly:
            return payment.amount * 4
        case .biweekly:
            return payment.amount * 2
        case .monthly:
            return payment.amount
        case .bimonthly, .quarterly, .semiannual, .yearly, .once:
            return payment.amount / Double(savingMonths(for: payment, now: now, calendar: calendar))
        }
    }

    static func nextCycleMonthlyEquivalent(for payment: FixedPayment) -> Double? {
        guard let months = payment.frequency.standardMonths, months > 1, payment.amount.isFinite, payment.amount > 0 else { return nil }
        return payment.amount / Double(months)
    }

    static func totalMonthlyFixed(in data: PlannerData, scope: FixedPaymentScope? = nil, now: Date = .now) -> Double {
        (data.fixedPayments ?? []).filter { $0.isActive && (scope == nil || $0.effectiveScope == scope) }.reduce(0) { $0 + monthlyEquivalent(for: $1, now: now) }
    }

    static func monthKey(for date: Date = .now, calendar: Calendar = .current) -> String {
        String(format: "%04d-%02d", calendar.component(.year, from: date), calendar.component(.month, from: date))
    }

    static func completedChecks(for payment: FixedPayment, in date: Date = .now, calendar: Calendar = .current) -> Int {
        let key = monthKey(for: date, calendar: calendar)
        let raw = payment.monthlyChecks?[key] ?? 0
        return min(max(raw, 0), payment.frequency.monthlyTargetChecks)
    }

    static func unitCheckAmount(for payment: FixedPayment, now: Date = .now, calendar: Calendar = .current) -> Double {
        let target = max(1, payment.frequency.monthlyTargetChecks)
        return monthlyEquivalent(for: payment, now: now, calendar: calendar) / Double(target)
    }

    static func paidMonthlyFixed(for payment: FixedPayment, now: Date = .now, calendar: Calendar = .current) -> Double {
        guard payment.isActive else { return 0 }
        return Double(completedChecks(for: payment, in: now, calendar: calendar)) * unitCheckAmount(for: payment, now: now, calendar: calendar)
    }

    static func remainingMonthlyFixed(for payment: FixedPayment, now: Date = .now, calendar: Calendar = .current) -> Double {
        guard payment.isActive else { return 0 }
        return max(0, monthlyEquivalent(for: payment, now: now, calendar: calendar) - paidMonthlyFixed(for: payment, now: now, calendar: calendar))
    }

    static func totalPaidMonthlyFixed(in data: PlannerData, scope: FixedPaymentScope? = nil, now: Date = .now) -> Double {
        (data.fixedPayments ?? []).filter { $0.isActive && (scope == nil || $0.effectiveScope == scope) }.reduce(0) { $0 + paidMonthlyFixed(for: $1, now: now) }
    }

    static func totalRemainingMonthlyFixed(in data: PlannerData, scope: FixedPaymentScope? = nil, now: Date = .now) -> Double {
        (data.fixedPayments ?? []).filter { $0.isActive && (scope == nil || $0.effectiveScope == scope) }.reduce(0) { $0 + remainingMonthlyFixed(for: $1, now: now) }
    }

    static func mainAccountRunningBalances(in data: PlannerData) -> [String: RunningBalanceStep] {
        enum StepItem {
            case entry(MoneyEntry)
            case transfer(MoneyTransfer)
            var id: String {
                switch self {
                case .entry(let e): "entry-\(e.id)"
                case .transfer(let t): "transfer-\(t.id)"
                }
            }
            var date: Date {
                switch self {
                case .entry(let e): e.date
                case .transfer(let t): t.date
                }
            }
        }
        let allItems = (data.entries.map(StepItem.entry) + (data.transfers ?? []).map(StepItem.transfer))
            .sorted { lhs, rhs in
                if lhs.date == rhs.date { return lhs.id < rhs.id }
                return lhs.date < rhs.date
            }
        var running = data.availableOpeningBalance ?? 0
        var result: [String: RunningBalanceStep] = [:]
        result.reserveCapacity(allItems.count)
        for item in allItems {
            let delta: Double
            switch item {
            case .entry(let entry):
                if entry.accountID == nil && entry.debtAction != .charge {
                    delta = entry.kind == .income ? entry.amount : -entry.amount
                } else {
                    delta = 0
                }
            case .transfer(let transfer):
                delta = (transfer.toAccountID == nil ? transfer.amount : 0)
                    - (transfer.fromAccountID == nil ? transfer.amount : 0)
            }
            running += delta
            result[item.id] = RunningBalanceStep(balanceAfter: running, delta: delta)
        }
        return result
    }
}

struct WidgetSnapshot: Codable {
    struct Item: Codable {
        var title: String
        var date: Date
        var type: String
        var done: Bool
    }
    var name: String
    var generated: Date
    var items: [Item]
    var pendingCount: Int
}
