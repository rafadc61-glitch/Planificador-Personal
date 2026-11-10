import Foundation
import Combine
import UserNotifications
import EventKit
import WidgetKit

@MainActor
final class PlannerStore: ObservableObject {
    static let widgetSuite = "group.com.planificador.personal"
    @Published var data: PlannerData { didSet { persist() } }
    @Published var notificationStatus = "Sin activar"
    @Published var calendarStatus = "Sin conectar"

    private let fileURL: URL
    private let sharesWidget: Bool
    private let eventStore = EKEventStore()

    init(dataURL: URL? = nil, sharesWidget: Bool = true) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Planificador", isDirectory: true)
        fileURL = dataURL ?? support.appendingPathComponent("planner.json")
        self.sharesWidget = sharesWidget
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let bytes = try? Data(contentsOf: fileURL), var decoded = try? JSONDecoder().decode(PlannerData.self, from: bytes) {
            var didMigrate = false
            if !decoded.categories.contains(where: { $0.isDebtPayment == true || $0.name.localizedCaseInsensitiveContains("deuda") }) {
                decoded.categories.append(.init(name: "Deudas", symbol: "creditcard.fill", tint: "#BDA6FF", kind: .expense, isDebtPayment: true))
                didMigrate = true
            }
            if (decoded.mainAccountName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                decoded.mainAccountName = "T. Débito Santander"
                didMigrate = true
            }
            if !decoded.accounts.contains(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare("Efectivo") == .orderedSame }) {
                decoded.accounts.insert(.init(name: "Efectivo", openingBalance: 0, symbol: "banknote.fill"), at: 0)
                didMigrate = true
            }
            if var payments = decoded.fixedPayments {
                for index in payments.indices where payments[index].cycleStart == nil {
                    payments[index].cycleStart = .now
                    didMigrate = true
                }
                decoded.fixedPayments = payments
            }
            data = decoded
            if didMigrate { persist() }
        } else {
            var initial = PlannerData()
            initial.mainAccountName = "T. Débito Santander"
            initial.accounts.append(.init(name: "Efectivo", openingBalance: 0, symbol: "banknote.fill"))
            data = initial
        }
        publishWidget()
    }

    private func persist() {
        guard let bytes = try? JSONEncoder().encode(data) else { return }
        try? bytes.write(to: fileURL, options: .atomic)
        publishWidget()
    }

    private func publishWidget() {
        guard sharesWidget else { return }
        let upcomingTasks = data.tasks.filter { !$0.isDone }
            .map { WidgetSnapshot.Item(title: $0.title, date: $0.due, type: "task", done: false) }
        let upcomingEvents = data.events.filter { $0.end >= .now }
            .map { WidgetSnapshot.Item(title: $0.title, date: $0.start, type: "event", done: false) }
        let snapshot = WidgetSnapshot(name: data.name, generated: .now,
                                      items: (upcomingTasks + upcomingEvents).sorted { $0.date < $1.date }.prefix(8).map { $0 },
                                      pendingCount: data.tasks.filter { !$0.isDone }.count)
        if let bytes = try? JSONEncoder().encode(snapshot) {
            UserDefaults(suiteName: Self.widgetSuite)?.set(bytes, forKey: "snapshot")
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func save(_ event: PlanEvent) {
        var event = event
        event.tags = ActivityTags.clean(event.tags ?? [])
        if !event.isClosed { event.completedAt = nil }
        let previous = data.events.first { $0.id == event.id }
        if let index = data.events.firstIndex(where: { $0.id == event.id }) { data.events[index] = event }
        else { data.events.append(event) }
        scheduleReminders(id: event.id, title: event.title, date: event.start,
                          offsets: event.isClosed ? [] : event.reminders, replacing: previous?.reminders ?? [])
        if event.addToCalendar { Task { await syncCalendarEvent(id: event.id) } }
        else if let id = previous?.calendarEventID ?? event.calendarEventID {
            removeCalendarEvent(id)
            if let index = data.events.firstIndex(where: { $0.id == event.id }) { data.events[index].calendarEventID = nil }
        }
    }
    func delete(_ event: PlanEvent) {
        data.events.removeAll { $0.id == event.id }
        clearReminders(id: event.id, offsets: event.reminders)
        if let id = event.calendarEventID { removeCalendarEvent(id) }
    }
    func save(_ task: PlanTask) {
        var task = task
        task.tags = ActivityTags.clean(task.tags ?? [])
        if !task.isDone { task.completedAt = nil }
        let previous = data.tasks.first { $0.id == task.id }
        if let index = data.tasks.firstIndex(where: { $0.id == task.id }) { data.tasks[index] = task }
        else { data.tasks.append(task) }
        scheduleReminders(id: task.id, title: task.title, date: task.due,
                          offsets: task.isDone ? [] : task.reminders, replacing: previous?.reminders ?? [])
        if task.isOnCalendar { Task { await syncCalendarTask(id: task.id) } }
        else if let id = previous?.calendarEventID ?? task.calendarEventID {
            removeCalendarEvent(id)
            if let index = data.tasks.firstIndex(where: { $0.id == task.id }) { data.tasks[index].calendarEventID = nil }
        }
    }
    func delete(_ task: PlanTask) {
        data.tasks.removeAll { $0.id == task.id }
        clearReminders(id: task.id, offsets: task.reminders)
        if let id = task.calendarEventID { removeCalendarEvent(id) }
    }
    func save(_ goal: PlanGoal) {
        var goal = goal
        goal.tags = ActivityTags.clean(goal.tags ?? [])
        if !goal.isClosed { goal.completedAt = nil }
        for index in goal.milestones.indices {
            goal.milestones[index].tags = ActivityTags.clean(goal.milestones[index].tags ?? [])
            if !goal.milestones[index].isDone { goal.milestones[index].completedAt = nil }
        }
        if let index = data.goals.firstIndex(where: { $0.id == goal.id }) { data.goals[index] = goal }
        else { data.goals.append(goal) }
    }
    func delete(_ goal: PlanGoal) { data.goals.removeAll { $0.id == goal.id } }
    func save(_ entry: MoneyEntry) {
        guard entry.amount.isFinite, entry.amount > 0,
              data.categories.contains(where: { $0.id == entry.categoryID && $0.kind == entry.kind }),
              entry.debtAction == nil || (entry.kind == .expense && data.debts?.contains(where: { $0.id == entry.debtID }) == true),
              entry.accountID == nil || data.accounts.contains(where: { $0.id == entry.accountID }) else { return }
        let isNew = !data.entries.contains(where: { $0.id == entry.id })
        if let index = data.entries.firstIndex(where: { $0.id == entry.id }) { data.entries[index] = entry }
        else { data.entries.append(entry) }

        if isNew, let fixedID = entry.fixedPaymentID, let payment = data.fixedPayments?.first(where: { $0.id == fixedID }) {
            let done = FinanceMath.completedChecks(for: payment, in: entry.date)
            let target = payment.frequency.monthlyTargetChecks
            if done < target {
                setMonthlyCheckCount(done + 1, for: payment, in: entry.date, advanceDueDate: true)
            } else if payment.frequency != .once {
                var advanced = payment
                advanced.cycleStart = payment.nextDue
                advanced.nextDue = payment.frequency.nextDueDate(from: payment.nextDue)
                save(advanced)
            }
        }
    }
    func delete(_ entry: MoneyEntry) { data.entries.removeAll { $0.id == entry.id } }
    func debtBalance(_ debt: MoneyDebt) -> Double { FinanceMath.debtBalance(debt, in: data) }
    var totalDebt: Double { (data.debts ?? []).reduce(0) { $0 + debtBalance($1) } }
    func save(_ debt: MoneyDebt) {
        guard debt.openingBalance.isFinite, debt.creditLimit == nil || (debt.creditLimit!.isFinite && debt.creditLimit! > 0) else { return }
        var items = data.debts ?? []
        if let i = items.firstIndex(where: { $0.id == debt.id }) { items[i] = debt } else { items.append(debt) }
        data.debts = items
    }
    func delete(_ debt: MoneyDebt) {
        guard !data.entries.contains(where: { $0.debtID == debt.id }) else { return }
        data.debts?.removeAll { $0.id == debt.id }
    }
    func save(_ payment: FixedPayment) {
        guard payment.amount.isFinite, payment.amount > 0 else { return }
        var payment = payment
        if payment.cycleStart == nil { payment.cycleStart = .now }
        if payment.scope == nil { payment.scope = .personal }
        let cleanedTags = ActivityTags.clean(payment.tags ?? [])
        payment.tags = cleanedTags.isEmpty ? nil : cleanedTags
        var items = data.fixedPayments ?? []
        if let i = items.firstIndex(where: { $0.id == payment.id }) { items[i] = payment } else { items.append(payment) }
        data.fixedPayments = items
    }
    func delete(_ payment: FixedPayment) { data.fixedPayments?.removeAll { $0.id == payment.id } }
    func monthlyFixedAmount(_ payment: FixedPayment) -> Double { FinanceMath.monthlyEquivalent(for: payment) }
    var monthlyFixedTotal: Double { FinanceMath.totalMonthlyFixed(in: data) }
    var monthlyFixedPaid: Double { FinanceMath.totalPaidMonthlyFixed(in: data) }
    var monthlyFixedRemaining: Double { FinanceMath.totalRemainingMonthlyFixed(in: data) }
    var biweeklyFixedTotal: Double { monthlyFixedTotal / 2.0 }
    var biweeklyFixedRemaining: Double { monthlyFixedRemaining / 2.0 }
    var weeklyFixedTotal: Double { monthlyFixedTotal / 4.0 }
    var weeklyFixedRemaining: Double { monthlyFixedRemaining / 4.0 }

    func monthlyFixedTotal(for scope: FixedPaymentScope?) -> Double {
        FinanceMath.totalMonthlyFixed(in: data, scope: scope)
    }
    func monthlyFixedPaid(for scope: FixedPaymentScope?) -> Double {
        FinanceMath.totalPaidMonthlyFixed(in: data, scope: scope)
    }
    func monthlyFixedRemaining(for scope: FixedPaymentScope?) -> Double {
        FinanceMath.totalRemainingMonthlyFixed(in: data, scope: scope)
    }
    func biweeklyFixedTotal(for scope: FixedPaymentScope?) -> Double {
        monthlyFixedTotal(for: scope) / 2.0
    }
    func biweeklyFixedRemaining(for scope: FixedPaymentScope?) -> Double {
        monthlyFixedRemaining(for: scope) / 2.0
    }
    func weeklyFixedTotal(for scope: FixedPaymentScope?) -> Double {
        monthlyFixedTotal(for: scope) / 4.0
    }
    func weeklyFixedRemaining(for scope: FixedPaymentScope?) -> Double {
        monthlyFixedRemaining(for: scope) / 4.0
    }
    var knownFixedPaymentTags: [String] {
        ActivityTags.clean((data.fixedPayments ?? []).flatMap { $0.tags ?? [] })
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    func setMonthlyCheckCount(_ count: Int, for payment: FixedPayment, in date: Date = .now, advanceDueDate: Bool = true) {
        var updated = payment
        let previousCount = FinanceMath.completedChecks(for: payment, in: date)
        var map = updated.monthlyChecks ?? [:]
        let key = FinanceMath.monthKey(for: date)
        let clamped = min(max(count, 0), payment.frequency.monthlyTargetChecks)
        if clamped == 0 { map.removeValue(forKey: key) }
        else { map[key] = clamped }
        updated.monthlyChecks = map.isEmpty ? nil : map

        if advanceDueDate && updated.frequency != .once {
            let delta = clamped - previousCount
            if delta > 0 {
                for _ in 0..<delta {
                    updated.cycleStart = updated.nextDue
                    updated.nextDue = updated.frequency.nextDueDate(from: updated.nextDue)
                }
            } else if delta < 0 {
                for _ in 0..<abs(delta) {
                    let prevDue = updated.frequency.previousDueDate(from: updated.nextDue)
                    updated.nextDue = prevDue
                    updated.cycleStart = updated.frequency.previousDueDate(from: prevDue)
                }
            }
        }
        save(updated)
    }
    func debtCategoryID() -> UUID {
        if let category = data.categories.first(where: { $0.kind == .expense && !$0.isArchived && ($0.isDebtPayment == true || $0.name.localizedCaseInsensitiveContains("deuda")) }) { return category.id }
        var category = MoneyCategory(name: "Deudas", symbol: "creditcard.fill", tint: "#BDA6FF", kind: .expense)
        category.isDebtPayment = true
        save(category)
        return category.id
    }
    func save(_ category: MoneyCategory) {
        if let index = data.categories.firstIndex(where: { $0.id == category.id }) { data.categories[index] = category }
        else { data.categories.append(category) }
    }
    func delete(_ category: MoneyCategory) {
        if let index = data.categories.firstIndex(where: { $0.id == category.id }) {
            data.categories[index].archived = true
        }
    }
    func restore(_ category: MoneyCategory) {
        if let index = data.categories.firstIndex(where: { $0.id == category.id }) {
            data.categories[index].archived = false
        }
    }
    func save(_ account: MoneyAccount) {
        guard account.openingBalance.isFinite else { return }
        if let index = data.accounts.firstIndex(where: { $0.id == account.id }) { data.accounts[index] = account }
        else { data.accounts.append(account) }
    }
    func delete(_ account: MoneyAccount) {
        guard canDeleteAccount(account) else { return }
        data.accounts.removeAll { $0.id == account.id }
    }
    func canDeleteAccount(_ account: MoneyAccount) -> Bool {
        !data.entries.contains(where: { $0.accountID == account.id }) &&
        !(data.transfers ?? []).contains(where: { $0.fromAccountID == account.id || $0.toAccountID == account.id })
    }
    func save(_ transfer: MoneyTransfer) {
        guard transfer.amount.isFinite, transfer.amount > 0, transfer.fromAccountID != transfer.toAccountID,
              transfer.fromAccountID == nil || data.accounts.contains(where: { $0.id == transfer.fromAccountID }),
              transfer.toAccountID == nil || data.accounts.contains(where: { $0.id == transfer.toAccountID }) else { return }
        if let index = (data.transfers ?? []).firstIndex(where: { $0.id == transfer.id }) {
            data.transfers?[index] = transfer
        } else {
            if data.transfers == nil { data.transfers = [] }
            data.transfers?.append(transfer)
        }
    }
    func delete(_ transfer: MoneyTransfer) { data.transfers?.removeAll { $0.id == transfer.id } }
    func save(_ budget: BudgetPlan) {
        guard budget.limit.isFinite, budget.limit > 0 else { return }
        if let index = data.budgets.firstIndex(where: { $0.id == budget.id }) { data.budgets[index] = budget }
        else { data.budgets.append(budget) }
    }
    func delete(_ budget: BudgetPlan) { data.budgets.removeAll { $0.id == budget.id } }

    func accountBalance(_ account: MoneyAccount) -> Double {
        FinanceMath.balance(accountID: account.id, in: data)
    }
    var mainAccountName: String {
        let trimmed = (data.mainAccountName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "T. Débito Santander" : trimmed
    }
    func isEfectivoAccount(_ account: MoneyAccount) -> Bool {
        account.name.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare("Efectivo") == .orderedSame
    }
    var efectivoAccount: MoneyAccount? {
        data.accounts.first(where: isEfectivoAccount)
    }
    var mainAccountBalance: Double { FinanceMath.balance(accountID: nil, in: data) }
    var efectivoBalance: Double { efectivoAccount.map(accountBalance) ?? 0 }
    var availableBalance: Double { mainAccountBalance + efectivoBalance }
    var boxesTotal: Double { data.accounts.filter { !isEfectivoAccount($0) }.reduce(0) { $0 + accountBalance($1) } }
    var totalMoney: Double { FinanceMath.total(in: data) }

    func updateAvailableSetup(mainName: String, desiredMainBalance: Double, desiredCashBalance: Double) {
        let cleanedName = mainName.trimmingCharacters(in: .whitespacesAndNewlines)
        data.mainAccountName = cleanedName.isEmpty ? "T. Débito Santander" : cleanedName
        if desiredMainBalance.isFinite {
            data.availableOpeningBalance = (data.availableOpeningBalance ?? 0) + (desiredMainBalance - mainAccountBalance)
        }
        if desiredCashBalance.isFinite {
            if let idx = data.accounts.firstIndex(where: isEfectivoAccount) {
                let currentCash = accountBalance(data.accounts[idx])
                data.accounts[idx].openingBalance += (desiredCashBalance - currentCash)
            } else {
                data.accounts.insert(.init(name: "Efectivo", openingBalance: desiredCashBalance, symbol: "banknote.fill"), at: 0)
            }
        }
    }
    func budgetWindow(_ budget: BudgetPlan, now: Date = .now) -> (Date, Date) {
        let calendar = Calendar.current
        if budget.period == .custom {
            let endExclusive = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: budget.end)) ?? budget.end
            return (calendar.startOfDay(for: budget.start), endExclusive)
        }
        if budget.period == .month {
            let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
            return (start, calendar.date(byAdding: .month, value: 1, to: start) ?? now)
        }
        let weekday = calendar.component(.weekday, from: now)
        let delta = (weekday - data.weekStartsOn + 7) % 7
        let start = calendar.date(byAdding: .day, value: -delta, to: calendar.startOfDay(for: now)) ?? now
        return (start, calendar.date(byAdding: .day, value: 7, to: start) ?? now)
    }
    func budgetSpent(_ budget: BudgetPlan) -> Double {
        let (start, end) = budgetWindow(budget)
        return data.entries.filter { $0.countsAsExpense && $0.date >= start && $0.date < end &&
            (budget.categoryID == nil || $0.categoryID == budget.categoryID) }.reduce(0) { $0 + $1.amount }
    }

    func requestCalendarAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            calendarStatus = granted ? "Conectado" : "Acceso denegado"
            return granted
        } catch {
            calendarStatus = "No disponible"
            return false
        }
    }
    private func syncCalendarEvent(id: UUID) async {
        guard await requestCalendarAccess() else { return }
        guard let plan = data.events.first(where: { $0.id == id && $0.addToCalendar }) else { return }
        let event = plan.calendarEventID.flatMap { eventStore.event(withIdentifier: $0) } ?? EKEvent(eventStore: eventStore)
        event.title = "\(plan.isClosed ? "☑ " : "")\(plan.title)"
        event.notes = plan.notes
        event.startDate = plan.start
        event.endDate = plan.end
        event.calendar = event.calendar ?? eventStore.defaultCalendarForNewEvents
        guard event.calendar != nil else { calendarStatus = "Sin calendario disponible"; return }
        do {
            try eventStore.save(event, span: .thisEvent)
            if let index = data.events.firstIndex(where: { $0.id == plan.id }) {
                data.events[index].calendarEventID = event.eventIdentifier
            }
            calendarStatus = "Conectado"
        } catch { calendarStatus = "Error al guardar" }
    }
    private func syncCalendarTask(id: UUID) async {
        guard await requestCalendarAccess() else { return }
        guard let plan = data.tasks.first(where: { $0.id == id && $0.isOnCalendar }) else { return }
        let event = plan.calendarEventID.flatMap { eventStore.event(withIdentifier: $0) } ?? EKEvent(eventStore: eventStore)
        event.title = "\(plan.isDone ? "☑" : "☐") \(plan.title)"
        event.notes = plan.notes
        event.startDate = plan.due
        event.endDate = plan.due.addingTimeInterval(30 * 60)
        event.calendar = event.calendar ?? eventStore.defaultCalendarForNewEvents
        guard event.calendar != nil else { calendarStatus = "Sin calendario disponible"; return }
        do {
            try eventStore.save(event, span: .thisEvent)
            if let index = data.tasks.firstIndex(where: { $0.id == id }) {
                data.tasks[index].calendarEventID = event.eventIdentifier
            }
            calendarStatus = "Conectado"
        } catch { calendarStatus = "Error al guardar" }
    }
    private func removeCalendarEvent(_ id: String) {
        guard let event = eventStore.event(withIdentifier: id) else { return }
        try? eventStore.remove(event, span: .thisEvent)
    }

    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] granted, _ in
            Task { @MainActor in self?.notificationStatus = granted ? "Activadas" : "Desactivadas" }
        }
    }
    private func clearReminders(id: UUID, offsets: [Int]) {
        let identifiers = [id.uuidString] + offsets.map { "\(id.uuidString)-\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
    private func scheduleReminders(id: UUID, title: String, date: Date,
                                   offsets: [Int], replacing previous: [Int]) {
        let center = UNUserNotificationCenter.current()
        clearReminders(id: id, offsets: previous + offsets)
        guard !offsets.isEmpty else { return }
        center.getNotificationSettings { [weak self] settings in
            if settings.authorizationStatus == .notDetermined {
                Task { @MainActor in self?.requestNotifications() }
            }
        }
        for minutes in Set(offsets.filter { $0 >= 0 }) {
            let triggerDate = date.addingTimeInterval(Double(-minutes * 60))
            guard triggerDate > .now else { continue }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = minutes == 0 ? "Es el momento." : "Tienes un recordatorio próximo."
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year,.month,.day,.hour,.minute], from: triggerDate), repeats: false)
            center.add(UNNotificationRequest(identifier: "\(id.uuidString)-\(minutes)", content: content, trigger: trigger))
        }
    }

    func amount(_ value: Double) -> String {
        let code = data.currencyCode.trimmingCharacters(in: .whitespaces).uppercased()
        return value.formatted(.currency(code: code.count == 3 ? code : "MXN"))
    }
    func category(_ id: UUID) -> MoneyCategory? { data.categories.first { $0.id == id } }
    func monthEntries(_ date: Date = .now) -> [MoneyEntry] { data.entries.filter { Calendar.current.isDate($0.date, equalTo: date, toGranularity: .month) } }
    func monthTotal(_ kind: MoneyKind) -> Double { monthEntries().filter { $0.kind == kind && $0.debtAction != .payment }.reduce(0) { $0 + $1.amount } }

    var activities: [ActivityRecord] {
        let tasks = data.tasks.map {
            ActivityRecord(id: $0.id, title: $0.title, kind: .task, deadline: $0.due,
                           includesTime: true, isClosed: $0.isDone, completedAt: $0.completedAt, tags: $0.tags ?? [])
        }
        let events = data.events.map {
            ActivityRecord(id: $0.id, title: $0.title, kind: .event, deadline: $0.end,
                           includesTime: true, isClosed: $0.isClosed, completedAt: $0.completedAt, tags: $0.tags ?? [])
        }
        let goals = data.goals.map {
            ActivityRecord(id: $0.id, title: $0.title, kind: .goal, deadline: $0.targetDate,
                           includesTime: false, isClosed: $0.isClosed, completedAt: $0.completedAt, tags: $0.tags ?? [])
        }
        let milestones = data.goals.flatMap { goal in
            goal.milestones.map {
                ActivityRecord(id: $0.id, title: $0.title, kind: .milestone, deadline: $0.dueDate,
                               includesTime: false, isClosed: $0.isDone || goal.isClosed,
                               completedAt: $0.completedAt, tags: ($0.tags?.isEmpty == false ? $0.tags! : goal.tags) ?? [])
            }
        }
        return tasks + events + goals + milestones
    }
    var knownTags: [String] {
        ActivityTags.clean(activities.flatMap(\.tags)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
