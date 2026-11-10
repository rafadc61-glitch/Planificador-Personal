import SwiftUI
import Charts

private struct MonthlyFlow: Identifiable {
    let id: String
    let bucketIndex: Int
    let month: Date
    let label: String
    let fullPeriodLabel: String
    let kind: MoneyKind
    let amount: Double
    let entries: [MoneyEntry]
}

private struct CategorySpend: Identifiable {
    let category: MoneyCategory?
    let amount: Double
    let entries: [MoneyEntry]
    let id: UUID
}

private enum DashboardChartPeriod: String, CaseIterable, Identifiable {
    case currentMonth = "Mes actual"
    case previousMonth = "Mes anterior"
    case last6Months = "Últimos 6 meses"
    case currentYear = "Año en curso"
    case previousYear = "Año anterior"
    case custom = "Personalizado"
    var id: String { rawValue }
}

private enum FinanceHistoryItem: Identifiable {
    case entry(MoneyEntry), transfer(MoneyTransfer)
    var id: String {
        switch self { case .entry(let item): "entry-\(item.id)"; case .transfer(let item): "transfer-\(item.id)" }
    }
    var date: Date {
        switch self { case .entry(let item): item.date; case .transfer(let item): item.date }
    }
}

private enum MovementDatePreset: String, CaseIterable, Identifiable {
    case all = "Todo"
    case today = "Hoy"
    case week = "Esta semana"
    case month = "Por mes"
    case custom = "Rango de fechas"
    var id: String { rawValue }
}

private enum MovementTypeFilter: String, CaseIterable, Identifiable {
    case all = "Todos"
    case expense = "Gastos"
    case income = "Ingresos"
    case transfer = "Transferencias"
    var id: String { rawValue }
}

struct FinanceView: View {
    @ObservedObject var store: PlannerStore
    @Binding var editor: Editor?
    @State private var tab = "Dashboard"
    @State private var catalog: String? = nil
    @State private var selectedAccount: UUID? = nil
    @State private var selectedDebt: UUID? = nil
    @State private var selectedMonth = Date.now
    @State private var showAllHistory = false
    @State private var showArchivedCategories = false

    // Filtros de Movimientos
    @State private var movementDatePreset: MovementDatePreset = .all
    @State private var movementFilterMonth: Date = .now
    @State private var movementStartDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var movementEndDate: Date = .now
    @State private var movementTypeFilter: MovementTypeFilter = .all
    @State private var selectedCategoryFilters: Set<UUID> = []
    @State private var movementSearchText: String = ""
    @State private var hoveredCategoryID: UUID? = nil
    @State private var hoveredFlowID: String? = nil

    // Filtros de gráficas en Dashboard
    @State private var cashFlowPeriod: DashboardChartPeriod = .last6Months
    @State private var cashFlowStartDate: Date = Calendar.current.date(byAdding: .month, value: -2, to: .now) ?? .now
    @State private var cashFlowEndDate: Date = .now
    @State private var categoryPeriod: DashboardChartPeriod = .currentMonth
    @State private var categoryStartDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var categoryEndDate: Date = .now
    @State private var heatmapPeriod: DashboardChartPeriod = .currentMonth
    @State private var heatmapStartDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var heatmapEndDate: Date = .now
    @State private var heatmapMonth: Date = .now
    @State private var hoveredHeatmapDay: Date? = nil
    @State private var hoveredHeatmapWeekday: Int? = nil

    // Selección múltiple y filtros de etiquetas en Pagos fijos
    @State private var selectedFixedPaymentIDs: Set<UUID> = []
    @State private var fixedPaymentScopeFilter: FixedPaymentScope? = nil
    @State private var fixedPaymentTagFilter: String? = nil

    private var monthEntries: [MoneyEntry] { store.monthEntries(selectedMonth) }
    private var income: Double { monthEntries.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount } }
    private var expenses: Double { monthEntries.filter { $0.countsAsExpense }.reduce(0) { $0 + $1.amount } }
    private var accountBalances: [UUID: Double] {
        Dictionary(uniqueKeysWithValues: store.data.accounts.map { ($0.id, store.accountBalance($0)) })
    }
    private var mainAccountRunningBalances: [String: RunningBalanceStep] {
        FinanceMath.mainAccountRunningBalances(in: store.data)
    }
    private var hasActiveMovementFilters: Bool {
        movementDatePreset != .all || movementTypeFilter != .all || !selectedCategoryFilters.isEmpty || !movementSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private func resetMovementFilters() {
        movementDatePreset = .all
        movementFilterMonth = .now
        movementTypeFilter = .all
        selectedCategoryFilters.removeAll()
        movementSearchText = ""
    }
    private func matchesMovementDate(_ date: Date) -> Bool {
        let calendar = Calendar.current
        switch movementDatePreset {
        case .all:
            return true
        case .today:
            return calendar.isDateInToday(date)
        case .week:
            let weekday = calendar.component(.weekday, from: .now)
            let delta = (weekday - store.data.weekStartsOn + 7) % 7
            let start = calendar.date(byAdding: .day, value: -delta, to: calendar.startOfDay(for: .now)) ?? .now
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? .now
            return date >= start && date < end
        case .month:
            return calendar.isDate(date, equalTo: movementFilterMonth, toGranularity: .month)
        case .custom:
            let lower = calendar.startOfDay(for: min(movementStartDate, movementEndDate))
            let upperDay = calendar.startOfDay(for: max(movementStartDate, movementEndDate))
            let upper = calendar.date(byAdding: .day, value: 1, to: upperDay) ?? upperDay
            return date >= lower && date < upper
        }
    }
    private var history: [FinanceHistoryItem] {
        let query = movementSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return (store.data.entries.map(FinanceHistoryItem.entry) + (store.data.transfers ?? []).map(FinanceHistoryItem.transfer))
            .filter { item in
                if tab == "Cajas y deudas" {
                    if let selectedDebt {
                        if case .entry(let e) = item { return e.debtID == selectedDebt }
                        return false
                    }
                    if let selectedAccount {
                        switch item {
                        case .entry(let e): return e.accountID == selectedAccount && e.debtAction != .charge
                        case .transfer(let t): return t.fromAccountID == selectedAccount || t.toAccountID == selectedAccount
                        }
                    }
                    return true
                }
                guard tab == "Movimientos" && catalog == nil else { return true }
                guard matchesMovementDate(item.date) else { return false }

                switch movementTypeFilter {
                case .all: break
                case .expense:
                    guard case .entry(let e) = item, e.kind == .expense else { return false }
                case .income:
                    guard case .entry(let e) = item, e.kind == .income else { return false }
                case .transfer:
                    guard case .transfer = item else { return false }
                }

                if !selectedCategoryFilters.isEmpty {
                    guard case .entry(let e) = item, selectedCategoryFilters.contains(e.categoryID) else { return false }
                }

                if !query.isEmpty {
                    switch item {
                    case .entry(let e):
                        let catName = store.category(e.categoryID)?.name ?? ""
                        let matches = e.title.localizedCaseInsensitiveContains(query)
                            || e.notes.localizedCaseInsensitiveContains(query)
                            || catName.localizedCaseInsensitiveContains(query)
                        if !matches { return false }
                    case .transfer(let t):
                        let from = sourceName(t.fromAccountID)
                        let to = sourceName(t.toAccountID)
                        let matches = "transferencia".localizedCaseInsensitiveContains(query)
                            || t.notes.localizedCaseInsensitiveContains(query)
                            || from.localizedCaseInsensitiveContains(query)
                            || to.localizedCaseInsensitiveContains(query)
                        if !matches { return false }
                    }
                }
                return true
            }.sorted { $0.date > $1.date }
    }
    private func chartDateInterval(for period: DashboardChartPeriod, customStart: Date, customEnd: Date, now: Date = .now) -> (start: Date, endExclusive: Date, months: [Date]) {
        let calendar = Calendar.current
        let currentMonthStart = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)

        switch period {
        case .currentMonth:
            let end = calendar.date(byAdding: .month, value: 1, to: currentMonthStart) ?? now
            return (currentMonthStart, end, [currentMonthStart])
        case .previousMonth:
            let start = calendar.date(byAdding: .month, value: -1, to: currentMonthStart) ?? currentMonthStart
            return (start, currentMonthStart, [start])
        case .last6Months:
            let months = (-5...0).compactMap { calendar.date(byAdding: .month, value: $0, to: currentMonthStart) }
            let start = months.first ?? currentMonthStart
            let end = calendar.date(byAdding: .month, value: 1, to: currentMonthStart) ?? now
            return (start, end, months)
        case .currentYear:
            let year = calendar.component(.year, from: now)
            let currentM = calendar.component(.month, from: now)
            let months = (1...max(1, currentM)).compactMap { m in
                calendar.date(from: DateComponents(year: year, month: m, day: 1))
            }
            let start = months.first ?? currentMonthStart
            let end = calendar.date(byAdding: .month, value: 1, to: months.last ?? currentMonthStart) ?? now
            return (start, end, months)
        case .previousYear:
            let prevYear = calendar.component(.year, from: now) - 1
            let months = (1...12).compactMap { m in
                calendar.date(from: DateComponents(year: prevYear, month: m, day: 1))
            }
            let start = months.first ?? currentMonthStart
            let end = calendar.date(from: DateComponents(year: prevYear + 1, month: 1, day: 1)) ?? now
            return (start, end, months)
        case .custom:
            let lower = calendar.startOfDay(for: min(customStart, customEnd))
            let upperDay = calendar.startOfDay(for: max(customStart, customEnd))
            let upper = calendar.date(byAdding: .day, value: 1, to: upperDay) ?? upperDay
            var months: [Date] = []
            if let firstMonth = calendar.dateInterval(of: .month, for: lower)?.start {
                var cursor = firstMonth
                while cursor < upper && months.count < 24 {
                    months.append(cursor)
                    guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
                    cursor = next
                }
            }
            if months.isEmpty { months = [currentMonthStart] }
            return (lower, upper, months)
        }
    }

    private var monthFlows: [MonthlyFlow] {
        let calendar = Calendar.current
        let interval = chartDateInterval(for: cashFlowPeriod, customStart: cashFlowStartDate, customEnd: cashFlowEndDate)
        let multiYear = Set(interval.months.map { calendar.component(.year, from: $0) }).count > 1

        return interval.months.enumerated().flatMap { idx, monthStart -> [MonthlyFlow] in
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
            let effectiveStart = max(monthStart, interval.start)
            let effectiveEnd = min(monthEnd, interval.endExclusive)
            let label = multiYear
                ? monthStart.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
                : monthStart.formatted(.dateTime.month(.abbreviated))
            let fullLabel = monthStart.formatted(.dateTime.month(.wide).year()).capitalized
            let entries = store.data.entries.filter { $0.date >= effectiveStart && $0.date < effectiveEnd }
            return MoneyKind.allCases.map { kind in
                let kindEntries = entries.filter { $0.kind == kind && $0.debtAction != .payment }
                return MonthlyFlow(
                    id: "\(idx)-\(kind.rawValue)",
                    bucketIndex: idx,
                    month: monthStart,
                    label: label,
                    fullPeriodLabel: fullLabel,
                    kind: kind,
                    amount: kindEntries.reduce(0) { $0 + $1.amount },
                    entries: kindEntries
                )
            }
        }
    }

    private var categoryFilteredEntries: [MoneyEntry] {
        let interval = chartDateInterval(for: categoryPeriod, customStart: categoryStartDate, customEnd: categoryEndDate)
        return store.data.entries.filter { $0.countsAsExpense && $0.date >= interval.start && $0.date < interval.endExclusive }
    }

    private var categorySpending: [CategorySpend] {
        let grouped = Dictionary(grouping: categoryFilteredEntries, by: \.categoryID)
        return grouped.map { id, entries in
            CategorySpend(
                category: store.category(id),
                amount: entries.reduce(0) { $0 + $1.amount },
                entries: entries.sorted { $0.amount > $1.amount },
                id: id
            )
        }.sorted { $0.amount > $1.amount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack(alignment: .top, spacing: 12) {
                SectionTitle(title: "Tu dinero, claro.", subtitle: "Dinero, crédito y próximos pagos con claridad.")
                Spacer()
                primaryButton("Transferir", symbol: "arrow.left.arrow.right", color: Palette.raised, textColor: Palette.text) { newTransfer() }
                    .disabled(store.data.accounts.isEmpty)
                primaryButton("Movimiento", symbol: "plus", color: Palette.lavender, textColor: Palette.background) { newEntry() }
            }
            HStack(spacing: 7) {
                ForEach(["Dashboard", "Movimientos", "Cajas y deudas"], id: \.self) { name in
                    Button { tab = name; catalog = nil; selectedAccount = nil; selectedDebt = nil } label: {
                        Text(name).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(tab == name ? Palette.background : Palette.muted)
                            .padding(.horizontal, 23).padding(.vertical, 12)
                            .background(tab == name ? Palette.lavender : .clear, in: Capsule())
                    }.buttonStyle(.plain)
                }
                Spacer()
            }.padding(6).background(Palette.surface, in: Capsule())
            switch tab {
            case "Movimientos": movementsPage
            case "Cajas y deudas": walletsPage
            default: dashboardPage
            }
        }
    }

    private var dashboardPage: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack(spacing: 14) {
                wealthCard.frame(maxWidth: .infinity)
                VStack(spacing: 14) {
                    balanceCard(
                        "Disponible",
                        subtitle: "\(store.mainAccountName): \(store.amount(store.mainAccountBalance)) · Efectivo: \(store.amount(store.efectivoBalance))",
                        amount: store.availableBalance,
                        symbol: "wallet.pass.fill",
                        color: Palette.lavender
                    ) {
                        editor = .availableBalance
                    }
                    balanceCard(
                        "En cajas",
                        subtitle: "Sin contar Efectivo (ya incluido arriba)",
                        amount: store.boxesTotal,
                        symbol: "shippingbox.fill",
                        color: Palette.mint
                    ) {
                        newAccount()
                    }
                }.frame(width: 285)
            }
            if store.data.availableOpeningBalance == nil {
                Button { editor = .availableBalance } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle.fill").foregroundStyle(Palette.lavender)
                        Text("Fija cuánto dinero tienes disponible hoy para que el patrimonio refleje tu saldo real.")
                            .font(.system(size: 12)).foregroundStyle(Palette.text)
                        Spacer()
                        Text("Configurar").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.lavender)
                        Image(systemName: "arrow.right").foregroundStyle(Palette.lavender)
                    }
                    .padding(15).background(Palette.lavender.opacity(0.11), in: RoundedRectangle(cornerRadius: 13))
                }.buttonStyle(.plain)
            }
            HStack {
                Text("PANORAMA DEL MES").font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(Palette.muted)
                Spacer()
                Button { changeMonth(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain)
                Text(selectedMonth.formatted(.dateTime.month(.wide).year()).capitalized)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                    .frame(minWidth: 160)
                Button { changeMonth(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain)
                Button("Hoy") { selectedMonth = .now }.buttonStyle(.plain).font(.caption).foregroundStyle(Palette.lavender)
            }.foregroundStyle(Palette.lavender).padding(.top, 5)
            HStack(spacing: 14) {
                compactStat("Ingresos", value: income, symbol: "arrow.down.left", color: Palette.mint)
                compactStat("Gastos", value: expenses, symbol: "arrow.up.right", color: Palette.peach)
                compactStat("Balance del mes", value: income - expenses, symbol: "equal", color: Palette.lavender)
            }
            Text("Los gastos incluyen compras a crédito. Los abonos a deudas se muestran por separado para evitar duplicarlos.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
            HStack(alignment: .top, spacing: 15) {
                cashFlowCard.frame(maxWidth: .infinity)
                distributionCard.frame(width: 330)
            }
            HStack(alignment: .top, spacing: 15) {
                categoryCard.frame(maxWidth: .infinity)
                budgetCard.frame(maxWidth: .infinity)
            }
            expenseHeatmapCard
            HStack(spacing: 14) {
                compactStat("Deuda pendiente", value: store.totalDebt, symbol: "creditcard.fill", color: Palette.peach)
                compactStat("Dinero menos deudas", value: store.totalMoney - store.totalDebt, symbol: "scale.3d", color: Palette.lavender)
                compactStat("Abonos del mes", value: monthEntries.filter { $0.debtAction == .payment }.reduce(0) { $0 + $1.amount }, symbol: "arrow.down.circle", color: Palette.mint)
            }
            upcomingCard
        }
    }


    private var movementsPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                primaryButton("Pagos fijos", symbol: "calendar.badge.clock", color: catalog == "Pagos fijos" ? Palette.lavender : Palette.raised,
                              textColor: catalog == "Pagos fijos" ? Palette.background : Palette.text) { catalog = catalog == "Pagos fijos" ? nil : "Pagos fijos" }
                primaryButton("Categorías", symbol: "square.grid.2x2", color: catalog == "Categorías" ? Palette.lavender : Palette.raised,
                              textColor: catalog == "Categorías" ? Palette.background : Palette.text) { catalog = catalog == "Categorías" ? nil : "Categorías" }
                Spacer()
                if store.monthlyFixedTotal > 0 {
                    pill("Gasto fijo mensual: \(store.amount(store.monthlyFixedTotal))", symbol: "sparkles", color: Palette.mint)
                } else {
                    Text("Tu historial, sin perder el detalle.").font(.caption).foregroundStyle(Palette.muted)
                }
            }
            if catalog == "Categorías" {
                categoriesCard
            } else if catalog == "Pagos fijos" {
                fixedPaymentsCard
            } else {
                movementsFilterCard
                historyCard
            }
        }
    }

    private var walletsPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            if selectedAccount != nil || selectedDebt != nil {
                Button { selectedAccount = nil; selectedDebt = nil } label: { Label("Todas las fichas", systemImage: "arrow.left") }
                    .buttonStyle(.plain).foregroundStyle(Palette.lavender)
                if let debt = (store.data.debts ?? []).first(where: { $0.id == selectedDebt }) {
                    debtDetail(debt)
                } else if let account = store.data.accounts.first(where: { $0.id == selectedAccount }) {
                    HStack {
                        compactStat(account.name, value: store.accountBalance(account), symbol: account.symbol, color: Palette.mint)
                        primaryButton("Editar caja", symbol: "pencil", color: Palette.raised, textColor: Palette.text) { editor = .account(account) }
                        Button("Eliminar") { store.delete(account); selectedAccount = nil }.buttonStyle(.plain).foregroundStyle(Palette.muted).disabled(!store.canDeleteAccount(account))
                    }
                }
                historyCard
            } else {
                HStack {
                    SectionTitle(title: "Tus espacios", subtitle: "Abre una ficha para consultar su saldo e historial.")
                    Spacer()
                    primaryButton("Nueva caja", symbol: "plus", color: Palette.raised, textColor: Palette.text) { newAccount() }
                    primaryButton("Nueva deuda", symbol: "creditcard", color: Palette.lavender, textColor: Palette.background) { editor = .debt(.init(name: "")) }
                }
                Text("CUENTA PRINCIPAL Y CAJAS").font(.system(size: 11, weight: .bold)).tracking(1.5).foregroundStyle(Palette.mint)
                LazyVGrid(columns: [.init(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                    walletTile(
                        store.mainAccountName,
                        subtitle: "Cuenta principal · Suma al disponible · Editar",
                        amount: store.mainAccountBalance,
                        symbol: "creditcard.fill",
                        color: Palette.lavender
                    ) { editor = .availableBalance }
                    ForEach(store.data.accounts) { account in
                        let isCash = store.isEfectivoAccount(account)
                        walletTile(
                            account.name,
                            subtitle: isCash ? "Caja Efectivo · Suma al disponible" : "Caja · ver historial",
                            amount: store.accountBalance(account),
                            symbol: account.symbol,
                            color: Palette.mint
                        ) { selectedAccount = account.id }
                    }
                }
                Text("TARJETAS Y DEUDAS").font(.system(size: 11, weight: .bold)).tracking(1.5).foregroundStyle(Palette.peach).padding(.top, 8)
                if (store.data.debts ?? []).isEmpty { EmptyState(symbol: "creditcard", title: "Cada deuda con nombre", detail: "Añade tus TDC, préstamos y otros compromisos.") }
                LazyVGrid(columns: [.init(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                    ForEach(store.data.debts ?? []) { debt in
                        debtTile(debt) { selectedDebt = debt.id }
                    }
                }
            }
        }
    }

    private func walletTile(_ name: String, subtitle: String, amount: Double, symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 17) {
                HStack { IconBadge(symbol: symbol, color: color); Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(color) }
                Text(name).font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(Palette.text)
                Text(store.amount(amount)).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
                Text(subtitle).font(.caption).foregroundStyle(Palette.muted)
            }.padding(23).frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [Palette.raised, Palette.surface], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 21))
                .overlay(RoundedRectangle(cornerRadius: 21).stroke(color.opacity(0.25)))
        }.buttonStyle(.plain)
    }

    private func debtTile(_ debt: MoneyDebt, action: @escaping () -> Void) -> some View {
        let balance = store.debtBalance(debt)
        return Button(action: action) {
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 8) {
                    IconBadge(symbol: debt.kind.symbol, color: Palette.peach)
                    if let payDate = debt.paymentDate {
                        Text("Pago: \(payDate.formatted(.dateTime.day().month(.abbreviated)))")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.lavender)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Palette.lavender.opacity(0.13), in: Capsule())
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right").foregroundStyle(Palette.peach)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(debt.name)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                    Text(debt.kind.rawValue)
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                }

                if debt.kind == .creditCard, let limit = debt.creditLimit, limit > 0 {
                    let available = max(limit - balance, 0)
                    let usedRatio = min(max(balance / limit, 0), 1)
                    let barColor: Color = usedRatio >= 0.85 ? Palette.peach : usedRatio >= 0.55 ? Palette.lavender : Palette.mint

                    HStack(alignment: .bottom, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("MONTO DISPONIBLE")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .tracking(1)
                                .foregroundStyle(Palette.muted)
                            Text(store.amount(available))
                                .font(.system(size: 23, weight: .bold, design: .rounded))
                                .foregroundStyle(Palette.mint)
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                        }
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("USADO")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .tracking(1)
                                .foregroundStyle(Palette.muted)
                            Text(store.amount(balance))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(Palette.peach)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        GeometryReader { geo in
                            Capsule()
                                .fill(Palette.background.opacity(0.65))
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(barColor)
                                        .frame(width: max(geo.size.width * usedRatio, usedRatio > 0 ? 6 : 0))
                                }
                        }
                        .frame(height: 7)

                        HStack {
                            Text("Límite: \(store.amount(limit))")
                            Spacer()
                            Text("\(Int((usedRatio * 100).rounded()))% ocupado")
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.muted)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(balance < 0 ? "SALDO A FAVOR" : "DEUDA PENDIENTE")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(Palette.muted)
                        Text(store.amount(balance))
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                            .foregroundStyle(Palette.peach)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                    if debt.kind == .creditCard {
                        Text("Edita la tarjeta para definir su límite y ver el disponible.")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.lavender)
                            .lineLimit(1)
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, minHeight: 205, alignment: .leading)
            .background(LinearGradient(colors: [Palette.raised, Palette.surface], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 21))
            .overlay(RoundedRectangle(cornerRadius: 21).stroke(Palette.peach.opacity(0.25)))
        }
        .buttonStyle(.plain)
    }

    private func debtDetail(_ debt: MoneyDebt) -> some View {
        let balance = store.debtBalance(debt)
        return Surface {
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    IconBadge(symbol: debt.kind.symbol, color: Palette.peach)
                    SectionTitle(title: debt.name, subtitle: debt.kind.rawValue)
                    Spacer()
                    Button("Editar") { editor = .debt(debt) }.buttonStyle(.plain).foregroundStyle(Palette.lavender)
                    Button("Eliminar") { store.delete(debt); selectedDebt = nil }.buttonStyle(.plain).foregroundStyle(Palette.muted)
                        .disabled(store.data.entries.contains { $0.debtID == debt.id })
                }
                if let limit = debt.creditLimit, limit > 0 {
                    let available = max(limit - balance, 0)
                    let usedRatio = min(max(balance / limit, 0), 1)
                    HStack(spacing: 14) {
                        debtMetricBox(title: "Monto disponible", value: store.amount(available), color: Palette.mint)
                        debtMetricBox(title: balance < 0 ? "Saldo a favor" : "Deuda pendiente", value: store.amount(balance), color: Palette.peach)
                        debtMetricBox(title: "Límite de crédito", value: store.amount(limit), color: Palette.lavender)
                    }
                    ProgressView(value: usedRatio).tint(usedRatio >= 0.85 ? Palette.peach : Palette.mint)
                } else {
                    Text(store.amount(balance)).font(.system(size: 36, weight: .bold, design: .rounded)).foregroundStyle(Palette.peach)
                    Text(balance < 0 ? "Saldo a favor" : "Deuda pendiente").font(.caption).foregroundStyle(Palette.muted)
                }
                if let date = debt.paymentDate { Label("Fecha de pago: \(date.formatted(date: .long, time: .omitted))", systemImage: "calendar").font(.caption).foregroundStyle(Palette.lavender) }
                if !debt.notes.isEmpty { Text(debt.notes).font(.caption).foregroundStyle(Palette.muted) }
                HStack(spacing: 12) {
                    primaryButton("Abonar", symbol: "arrow.down.circle", color: Palette.mint, textColor: Palette.background) { debtEntry(debt, action: .payment) }
                    primaryButton("Añadir cargo", symbol: "plus", color: Palette.raised, textColor: Palette.text) { debtEntry(debt, action: .charge) }
                }
            }
        }
    }

    private func debtMetricBox(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(Palette.muted)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.22)))
    }

    private var upcomingCard: some View {
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionTitle(title: "Pagos a la vista", subtitle: "Próximas fechas y vencimientos pendientes.")
                    Spacer()
                    if store.monthlyFixedTotal > 0 {
                        pill("Apartar \(store.amount(store.monthlyFixedTotal)) / mes", symbol: "sparkles", color: Palette.mint)
                    }
                    Button("Ver catálogo") { tab = "Movimientos"; catalog = "Pagos fijos" }.buttonStyle(.plain).foregroundStyle(Palette.lavender)
                }
                let payments = (store.data.fixedPayments ?? []).filter(\.isActive).sorted { $0.nextDue < $1.nextDue }
                if payments.isEmpty { Text("Añade tus servicios y suscripciones desde Movimientos → Pagos fijos.").font(.caption).foregroundStyle(Palette.muted) }
                ForEach(Array(payments.prefix(4))) { payment in fixedPaymentRow(payment, full: false) }
                ForEach((store.data.debts ?? []).filter { $0.paymentDate != nil }.sorted { $0.paymentDate! < $1.paymentDate! }) { debt in
                    HStack {
                        IconBadge(symbol: debt.kind.symbol, color: Palette.peach)
                        Text(debt.name).foregroundStyle(Palette.text)
                        Spacer()
                        Text(debt.paymentDate!.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(Palette.muted)
                        Button("Ver deuda") { tab = "Cajas y deudas"; selectedDebt = debt.id }.buttonStyle(.plain).foregroundStyle(Palette.lavender)
                    }.font(.system(size: 12))
                }
            }
        }
    }

    private var fixedPaymentsCard: some View {
        let allPayments = (store.data.fixedPayments ?? []).sorted { $0.nextDue < $1.nextDue }
        let activePayments = allPayments.filter(\.isActive)
        let totalMonthly = store.monthlyFixedTotal
        let biweeklyTotal = store.biweeklyFixedTotal
        let weeklyTotal = store.weeklyFixedTotal
        let paidMonthly = store.monthlyFixedPaid
        let remainingMonthly = store.monthlyFixedRemaining
        let remainingWeekly = store.weeklyFixedRemaining
        let currentMonthName = Date.now.formatted(.dateTime.month(.wide)).capitalized
        let progress = totalMonthly > 0 ? min(max(paidMonthly / totalMonthly, 0), 1) : 0

        let personalMonthly = store.monthlyFixedTotal(for: .personal)
        let personalBiweekly = store.biweeklyFixedTotal(for: .personal)
        let personalWeekly = store.weeklyFixedTotal(for: .personal)
        let personalPaid = store.monthlyFixedPaid(for: .personal)
        let personalRemaining = store.monthlyFixedRemaining(for: .personal)

        let coupleMonthly = store.monthlyFixedTotal(for: .couple)
        let coupleBiweekly = store.biweeklyFixedTotal(for: .couple)
        let coupleWeekly = store.weeklyFixedTotal(for: .couple)
        let couplePaid = store.monthlyFixedPaid(for: .couple)
        let coupleRemaining = store.monthlyFixedRemaining(for: .couple)

        let filteredPayments = allPayments.filter { payment in
            if let scopeFilter = fixedPaymentScopeFilter, payment.effectiveScope != scopeFilter { return false }
            if let tagFilter = fixedPaymentTagFilter {
                guard (payment.tags ?? []).contains(where: { $0.caseInsensitiveCompare(tagFilter) == .orderedSame }) else { return false }
            }
            return true
        }

        return VStack(alignment: .leading, spacing: 18) {
            // Resumen mensual, quincenal, semanal y avance del mes en curso
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        Image(systemName: "sparkles").foregroundStyle(Palette.mint)
                        Text("GASTO Y APARTADO MENSUAL FIJO")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.5)
                            .foregroundStyle(Palette.muted)
                        Spacer()
                        pill("\(activePayments.count) activos en \(currentMonthName)", symbol: "checkmark.circle.fill", color: Palette.mint)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 18) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(store.amount(totalMonthly))
                                .font(.system(size: 33, weight: .bold, design: .rounded))
                                .foregroundStyle(Palette.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                            Text("/ mes")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Palette.mint)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("APARTADO QUINCENAL")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .tracking(1)
                                .foregroundStyle(Palette.muted)
                            Text("\(store.amount(biweeklyTotal)) / qna")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(Palette.mint)
                        }
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("APARTADO SEMANAL")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .tracking(1)
                                .foregroundStyle(Palette.muted)
                            Text("\(store.amount(weeklyTotal)) / sem")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(Palette.lavender)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: progress)
                            .tint(Palette.mint)
                        HStack {
                            Text("Cubierto este mes: \(store.amount(paidMonthly))")
                                .foregroundStyle(Palette.mint)
                            Spacer()
                            Text("Falta pagar en \(currentMonthName): \(store.amount(remainingMonthly))")
                                .foregroundStyle(remainingMonthly > 0 ? Palette.peach : Palette.mint)
                        }
                        .font(.system(size: 11, weight: .semibold))
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, minHeight: 164, alignment: .leading)
                .background(LinearGradient(colors: [Palette.raised, Palette.surface], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.mint.opacity(0.28)))

                VStack(spacing: 12) {
                    compactStat("Apartar por quincena (\(store.amount(weeklyTotal))/sem)", value: biweeklyTotal, symbol: "calendar.day.timeline.left", color: Palette.lavender)
                    compactStat("Falta este mes (\(store.amount(remainingWeekly))/sem)", value: remainingMonthly, symbol: "clock.badge.checkmark", color: Palette.peach)
                }
                .frame(width: 295)
            }

            // Desglose de Apartado: Gastos Personales vs Gastos en Pareja
            HStack(spacing: 14) {
                fixedScopeSummaryCard(
                    title: "Apartado Gastos Personales",
                    symbol: FixedPaymentScope.personal.symbol,
                    color: Palette.lavender,
                    monthly: personalMonthly,
                    biweekly: personalBiweekly,
                    weekly: personalWeekly,
                    paid: personalPaid,
                    remaining: personalRemaining,
                    count: activePayments.filter { $0.effectiveScope == .personal }.count,
                    isSelected: fixedPaymentScopeFilter == .personal
                ) {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        fixedPaymentScopeFilter = (fixedPaymentScopeFilter == .personal) ? nil : .personal
                    }
                }

                fixedScopeSummaryCard(
                    title: "Apartado Gastos en Pareja",
                    symbol: FixedPaymentScope.couple.symbol,
                    color: Palette.peach,
                    monthly: coupleMonthly,
                    biweekly: coupleBiweekly,
                    weekly: coupleWeekly,
                    paid: couplePaid,
                    remaining: coupleRemaining,
                    count: activePayments.filter { $0.effectiveScope == .couple }.count,
                    isSelected: fixedPaymentScopeFilter == .couple
                ) {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        fixedPaymentScopeFilter = (fixedPaymentScopeFilter == .couple) ? nil : .couple
                    }
                }
            }

            // Emulador / Simulador de Ingreso
            incomeSimulatorCard(totalMonthly: totalMonthly, remainingMonthly: remainingMonthly, weeklyTotal: weeklyTotal)

            Surface {
                let selectedPayments = allPayments.filter { selectedFixedPaymentIDs.contains($0.id) }
                let selectedChargeTotal = selectedPayments.reduce(0.0) { $0 + $1.amount }
                let selectedMonthlyTotal = selectedPayments.reduce(0.0) { $0 + store.monthlyFixedAmount($1) }
                let selectedRemainingTotal = selectedPayments.reduce(0.0) { $0 + FinanceMath.remainingMonthlyFixed(for: $1) }

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        SectionTitle(
                            title: "Tus pagos fijos",
                            subtitle: "Haz clic en la etiqueta Personal / En pareja de cada fila para cambiarla rápido, o selecciona varios con la casilla izquierda para sumarlos."
                        )
                        Spacer()
                        if !filteredPayments.isEmpty {
                            let allFilteredSelected = filteredPayments.allSatisfy { selectedFixedPaymentIDs.contains($0.id) }
                            Button(allFilteredSelected ? "Deseleccionar visibles" : "Seleccionar visibles") {
                                if allFilteredSelected {
                                    for p in filteredPayments { selectedFixedPaymentIDs.remove(p.id) }
                                } else {
                                    for p in filteredPayments { selectedFixedPaymentIDs.insert(p.id) }
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.lavender)
                            .padding(.horizontal, 11).padding(.vertical, 8)
                            .background(Palette.raised, in: Capsule())

                            Button("Seleccionar pendientes") {
                                selectedFixedPaymentIDs = Set(filteredPayments.filter { $0.isActive && FinanceMath.remainingMonthlyFixed(for: $0) > 0 }.map(\.id))
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.peach)
                            .padding(.horizontal, 11).padding(.vertical, 8)
                            .background(Palette.raised, in: Capsule())
                        }
                        if paidMonthly > 0 {
                            Button("Reiniciar checks del mes") {
                                for p in allPayments { store.setMonthlyCheckCount(0, for: p, advanceDueDate: false) }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.muted)
                            .padding(.horizontal, 11).padding(.vertical, 8)
                            .background(Palette.raised, in: Capsule())
                        }
                        primaryButton("Nuevo pago fijo", symbol: "plus", color: Palette.lavender, textColor: Palette.background) {
                            var newPayment = FixedPayment(name: "")
                            if let scopeFilter = fixedPaymentScopeFilter { newPayment.scope = scopeFilter }
                            editor = .fixedPayment(newPayment)
                        }
                    }

                    // Barra de filtros por etiquetas (Personal / En pareja / Etiquetas adicionales)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            let allActive = fixedPaymentScopeFilter == nil && fixedPaymentTagFilter == nil
                            Button {
                                fixedPaymentScopeFilter = nil
                                fixedPaymentTagFilter = nil
                            } label: {
                                Text("Todos (\(allPayments.count))")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(allActive ? Palette.background : Palette.text)
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(allActive ? Palette.lavender : Palette.raised, in: Capsule())
                            }.buttonStyle(.plain)

                            ForEach(FixedPaymentScope.allCases) { scope in
                                let isSelected = fixedPaymentScopeFilter == scope
                                let tint = scope == .couple ? Palette.peach : Palette.lavender
                                let count = allPayments.filter { $0.effectiveScope == scope }.count
                                Button {
                                    fixedPaymentScopeFilter = isSelected ? nil : scope
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: scope.symbol).font(.system(size: 10))
                                        Text("\(scope.rawValue) (\(count))")
                                    }
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(isSelected ? Palette.background : tint)
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(isSelected ? tint : tint.opacity(0.13), in: Capsule())
                                    .overlay(Capsule().stroke(isSelected ? tint : tint.opacity(0.35)))
                                }.buttonStyle(.plain)
                            }

                            if !store.knownFixedPaymentTags.isEmpty {
                                Divider().frame(height: 18)
                                ForEach(store.knownFixedPaymentTags, id: \.self) { tag in
                                    let isTagSelected = fixedPaymentTagFilter?.caseInsensitiveCompare(tag) == .orderedSame
                                    let tagColor = Palette.tagColor(tag)
                                    Button {
                                        fixedPaymentTagFilter = isTagSelected ? nil : tag
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: "tag.fill").font(.system(size: 9))
                                            Text(tag)
                                        }
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(isTagSelected ? Palette.background : tagColor)
                                        .padding(.horizontal, 11).padding(.vertical, 6)
                                        .background(isTagSelected ? tagColor : tagColor.opacity(0.13), in: Capsule())
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    // Barra de suma automática de pagos fijos seleccionados
                    if !selectedPayments.isEmpty {
                        HStack(spacing: 16) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.forwardslash.minus")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Palette.background)
                                    .frame(width: 30, height: 30)
                                    .background(Palette.lavender, in: RoundedRectangle(cornerRadius: 9))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("SUMA DE SELECCIONADOS")
                                        .font(.system(size: 9, weight: .bold, design: .rounded))
                                        .tracking(1)
                                        .foregroundStyle(Palette.muted)
                                    Text("\(selectedPayments.count) pago\(selectedPayments.count == 1 ? "" : "s") elegido\(selectedPayments.count == 1 ? "" : "s")")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(Palette.text)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("SUMA DE COBROS")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .tracking(0.8)
                                    .foregroundStyle(Palette.muted)
                                Text(store.amount(selectedChargeTotal))
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(Palette.lavender)
                            }
                            Divider().frame(height: 28)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("EQUIVALENTE MENSUAL")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .tracking(0.8)
                                    .foregroundStyle(Palette.muted)
                                Text(store.amount(selectedMonthlyTotal))
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(Palette.mint)
                            }
                            Divider().frame(height: 28)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("FALTA POR PAGAR MES")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .tracking(0.8)
                                    .foregroundStyle(Palette.muted)
                                Text(store.amount(selectedRemainingTotal))
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(selectedRemainingTotal > 0 ? Palette.peach : Palette.mint)
                            }
                            Button("Limpiar") {
                                selectedFixedPaymentIDs.removeAll()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.muted)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Palette.background, in: Capsule())
                        }
                        .padding(14)
                        .background(Palette.lavender.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
                        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Palette.lavender.opacity(0.45)))
                    }

                    if filteredPayments.isEmpty {
                        EmptyState(
                            symbol: "calendar.badge.clock",
                            title: allPayments.isEmpty ? "Que no se te pase" : "Sin pagos fijos en este filtro",
                            detail: allPayments.isEmpty
                                ? "Guarda el importe y la próxima fecha de cada servicio para calcular cuánto apartar al mes."
                                : "Cambia la etiqueta seleccionada o asigna pagos a esta categoría."
                        )
                    } else {
                        ForEach(filteredPayments) { payment in fixedPaymentRow(payment, full: true) }
                    }
                }
            }
        }
    }

    private func fixedScopeSummaryCard(
        title: String,
        symbol: String,
        color: Color,
        monthly: Double,
        biweekly: Double,
        weekly: Double,
        paid: Double,
        remaining: Double,
        count: Int,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let ratio = monthly > 0 ? min(max(paid / monthly, 0), 1) : 0
        return Button(action: action) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 8) {
                    IconBadge(symbol: symbol, color: color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(Palette.muted)
                        Text("\(count) activo\(count == 1 ? "" : "s") · clic para filtrar")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(color)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("QUINCENAL · SEMANAL")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(Palette.muted)
                        Text("\(store.amount(biweekly))/qna · \(store.amount(weekly))/sem")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(color)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(store.amount(monthly))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("/ mes")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(color)
                    Spacer()
                }

                ProgressView(value: ratio)
                    .tint(color)

                HStack {
                    Text("Cubierto: \(store.amount(paid))")
                        .foregroundStyle(Palette.mint)
                    Spacer()
                    Text("Falta: \(store.amount(remaining))")
                        .foregroundStyle(remaining > 0 ? Palette.peach : Palette.mint)
                }
                .font(.system(size: 10, weight: .semibold))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(isSelected ? color : color.opacity(0.28), lineWidth: isSelected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    private func incomeSimulatorCard(totalMonthly: Double, remainingMonthly: Double, weeklyTotal: Double) -> some View {
        let mode = store.data.simulatedIncomeMode ?? "remaining"
        let scopeKey = store.data.simulatedIncomeScope ?? "all"
        let activeScope: FixedPaymentScope? = scopeKey == "personal" ? .personal : scopeKey == "couple" ? .couple : nil
        let scopedMonthly = store.monthlyFixedTotal(for: activeScope)
        let scopedRemaining = store.monthlyFixedRemaining(for: activeScope)
        let scopedBiweekly = store.biweeklyFixedTotal(for: activeScope)
        let scopedWeekly = store.weeklyFixedTotal(for: activeScope)

        let simIncome = store.data.simulatedIncome ?? 0
        let targetDeduction: Double = mode == "total" ? scopedMonthly : mode == "biweekly" ? scopedBiweekly : mode == "weekly" ? scopedWeekly : scopedRemaining
        let scopeSuffix: String = activeScope == .personal ? " (Personales)" : activeScope == .couple ? " (En pareja)" : " (Todos)"
        let deductionLabel: String = (mode == "total" ? "Total fijos del mes" : mode == "biweekly" ? "Apartado fijo quincenal" : mode == "weekly" ? "Apartado fijo semanal" : "Falta pagar este mes") + scopeSuffix
        let freeAmount = simIncome - targetDeduction
        let usedRatio = simIncome > 0 ? min(max(targetDeduction / simIncome, 0), 1) : 0

        return Surface(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    IconBadge(symbol: "slider.horizontal.below.square.and.square.filled", color: Palette.lavender)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Simulador de ingreso y liquidez")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(Palette.text)
                        Text("Filtra por todos tus gastos fijos, solo gastos personales o solo gastos en pareja para ver cuánto te queda libre.")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        simulatorModePill(title: "Vs. Falta del mes", key: "remaining", current: mode)
                        simulatorModePill(title: "Vs. Total fijo mensual", key: "total", current: mode)
                        simulatorModePill(title: "Vs. Apartado quincenal", key: "biweekly", current: mode)
                        simulatorModePill(title: "Vs. Apartado semanal", key: "weekly", current: mode)
                    }
                }

                // Filtro de etiqueta en el simulador: Todos / Gastos personales / Gastos en pareja
                HStack(spacing: 8) {
                    Text("FILTRAR GASTOS FIJOS EN SIMULADOR:")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(Palette.muted)
                    simulatorScopePill(
                        title: "Todos (\(store.amount(store.monthlyFixedTotal))/mes)",
                        symbol: "square.stack.3d.up.fill",
                        key: "all",
                        current: scopeKey,
                        color: Palette.mint
                    )
                    simulatorScopePill(
                        title: "Gastos personales (\(store.amount(store.monthlyFixedTotal(for: .personal)))/mes)",
                        symbol: FixedPaymentScope.personal.symbol,
                        key: "personal",
                        current: scopeKey,
                        color: Palette.lavender
                    )
                    simulatorScopePill(
                        title: "Gastos en pareja (\(store.amount(store.monthlyFixedTotal(for: .couple)))/mes)",
                        symbol: FixedPaymentScope.couple.symbol,
                        key: "couple",
                        current: scopeKey,
                        color: Palette.peach
                    )
                    Spacer()
                }

                HStack(alignment: .center, spacing: 16) {
                    // Input de ingreso simulado
                    VStack(alignment: .leading, spacing: 5) {
                        Text("TU INGRESO ESTIMADO (\(store.data.currencyCode))")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(Palette.muted)
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text("$").font(.system(size: 20, weight: .bold, design: .rounded))
                            MoneyField(
                                value: Binding(
                                    get: { store.data.simulatedIncome ?? 0 },
                                    set: { store.data.simulatedIncome = $0 > 0 ? $0 : nil }
                                ),
                                allowsNegative: false
                            )
                            .textFieldStyle(.plain)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(Palette.mint)
                    }
                    .padding(13)
                    .frame(width: 230, alignment: .leading)
                    .background(Palette.background, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.mint.opacity(0.35)))

                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Palette.muted)

                    // Pagos fijos a descontar
                    VStack(alignment: .leading, spacing: 5) {
                        Text(deductionLabel.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                        Text(store.amount(targetDeduction))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Palette.peach)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(13)
                    .frame(width: 210, alignment: .leading)
                    .background(Palette.raised.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line))

                    Image(systemName: "equal")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Palette.muted)

                    // Resultado libre
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(freeAmount >= 0 ? "TE QUEDA LIBRE" : "TE FALTA CUBRIR")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .tracking(1)
                                .foregroundStyle(Palette.muted)
                            Spacer()
                            if simIncome > 0 {
                                Text("\(Int(((1 - usedRatio) * 100).rounded()))% libre")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(freeAmount >= 0 ? Palette.mint : Palette.peach)
                            }
                        }
                        HStack(alignment: .firstTextBaseline) {
                            Text(store.amount(freeAmount))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(freeAmount >= 0 ? Palette.mint : Palette.peach)
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                            Spacer()
                            if freeAmount > 0 {
                                Button {
                                    editor = .budget(.init(
                                        name: mode == "weekly" ? "Presupuesto semanal libre" : "Presupuesto mensual libre",
                                        limit: freeAmount,
                                        period: mode == "weekly" ? .week : .month
                                    ))
                                } label: {
                                    Label("Crear presupuesto", systemImage: "plus.circle.fill")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Palette.background)
                                        .padding(.horizontal, 11).padding(.vertical, 6)
                                        .background(Palette.lavender, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background((freeAmount >= 0 ? Palette.mint : Palette.peach).opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke((freeAmount >= 0 ? Palette.mint : Palette.peach).opacity(0.35)))
                }
            }
        }
    }

    private func simulatorModePill(title: String, key: String, current: String) -> some View {
        let selected = current == key
        return Button {
            store.data.simulatedIncomeMode = key
        } label: {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(selected ? Palette.background : Palette.text)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(selected ? Palette.lavender : Palette.raised, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func simulatorScopePill(title: String, symbol: String, key: String, current: String, color: Color) -> some View {
        let selected = current == key
        return Button {
            store.data.simulatedIncomeScope = key
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 9, weight: .bold))
                Text(title).font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(selected ? Palette.background : color)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(selected ? color : color.opacity(0.13), in: Capsule())
            .overlay(Capsule().stroke(selected ? color : color.opacity(0.35)))
        }
        .buttonStyle(.plain)
    }

    private func fixedPaymentRow(_ payment: FixedPayment, full: Bool) -> some View {
        let monthlyAmount = store.monthlyFixedAmount(payment)
        let months = FinanceMath.savingMonths(for: payment)
        let isOverdue = payment.nextDue < Calendar.current.startOfDay(for: .now) && payment.isActive
        let cat = payment.categoryID.flatMap { store.category($0) }
        let targetChecks = payment.frequency.monthlyTargetChecks
        let doneChecks = FinanceMath.completedChecks(for: payment)
        let remainingThisMonth = FinanceMath.remainingMonthlyFixed(for: payment)
        let isCompletedThisMonth = payment.isActive && doneChecks >= targetChecks
        let scope = payment.effectiveScope
        let scopeColor = scope == .couple ? Palette.peach : Palette.lavender

        let isSelectedForSum = selectedFixedPaymentIDs.contains(payment.id)

        return HStack(spacing: 12) {
            if full {
                Button {
                    if isSelectedForSum {
                        selectedFixedPaymentIDs.remove(payment.id)
                    } else {
                        selectedFixedPaymentIDs.insert(payment.id)
                    }
                } label: {
                    Image(systemName: isSelectedForSum ? "checkmark.square.fill" : "square")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isSelectedForSum ? Palette.lavender : Palette.muted.opacity(0.75))
                }
                .buttonStyle(.plain)
                .help("Seleccionar para sumar")
            }

            // Check rápido cuando es de 1 pago al mes (avanza automáticamente al siguiente cobro)
            if full && payment.isActive && targetChecks == 1 {
                Button {
                    store.setMonthlyCheckCount(doneChecks >= 1 ? 0 : 1, for: payment, advanceDueDate: true)
                } label: {
                    Image(systemName: doneChecks >= 1 ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 21))
                        .foregroundStyle(doneChecks >= 1 ? Palette.mint : Palette.muted)
                }
                .buttonStyle(.plain)
                .help(doneChecks >= 1 ? "Desmarcar pago y regresar fecha" : "Marcar como cubierto y pasar a la siguiente fecha")
            }

            if let cat {
                CategoryBadge(category: cat)
            } else {
                IconBadge(symbol: payment.frequency.symbol, color: Palette.lavender)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(payment.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(payment.isActive ? (isCompletedThisMonth ? Palette.muted : Palette.text) : Palette.muted)
                        .strikethrough(isCompletedThisMonth)

                    // Etiqueta Personal / En pareja (con clic rápido para alternar)
                    Button {
                        guard full else { return }
                        var updated = payment
                        updated.scope = (scope == .personal) ? .couple : .personal
                        store.save(updated)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: scope.symbol).font(.system(size: 8, weight: .bold))
                            Text(scope.rawValue).font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(scopeColor)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(scopeColor.opacity(0.14), in: Capsule())
                        .overlay(Capsule().stroke(scopeColor.opacity(0.35)))
                    }
                    .buttonStyle(.plain)
                    .help(full ? "Clic para cambiar entre Personal y En pareja" : scope.rawValue)

                    if let tags = payment.tags, !tags.isEmpty {
                        ForEach(tags.prefix(2), id: \.self) { tag in
                            TagChip(name: tag)
                        }
                    }

                    if !payment.isActive {
                        Text("Pausado")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Palette.muted)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Palette.raised, in: Capsule())
                    } else if isCompletedThisMonth {
                        Text("Cubierto este mes")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Palette.mint)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Palette.mint.opacity(0.14), in: Capsule())
                    }
                }
                HStack(spacing: 6) {
                    Text("\(payment.nextDue.formatted(date: .abbreviated, time: .omitted)) · \(payment.frequency.rawValue)")
                        .font(.caption)
                        .foregroundStyle(isOverdue && !isCompletedThisMonth ? Palette.peach : Palette.muted)
                    if let last = store.data.entries.filter({ $0.fixedPaymentID == payment.id }).max(by: { $0.date < $1.date }) {
                        Text("· Último: \(last.date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(Palette.mint)
                    }
                }
            }

            Spacer(minLength: 8)

            // Controles de checks múltiples para pagos semanales (4) o quincenales (2)
            if full && payment.isActive {
                if targetChecks > 1 {
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 5) {
                            ForEach(1...targetChecks, id: \.self) { step in
                                let checked = step <= doneChecks
                                Button {
                                    let newCount = (doneChecks == step) ? (step - 1) : step
                                    store.setMonthlyCheckCount(newCount, for: payment)
                                } label: {
                                    Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 16))
                                        .foregroundStyle(checked ? Palette.mint : Palette.muted)
                                }
                                .buttonStyle(.plain)
                                .help("Pago \(step) de \(targetChecks) del mes")
                            }
                        }
                        Text("Pagos: \(doneChecks) de \(targetChecks) · Falta \(store.amount(remainingThisMonth))")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(remainingThisMonth == 0 ? Palette.mint : Palette.peach)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Palette.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 11))
                }
            }

            // Desglose de cobro vs apartado mensual
            VStack(alignment: .trailing, spacing: 3) {
                if payment.isActive {
                    HStack(spacing: 5) {
                        Text("\(store.amount(monthlyAmount)) / mes")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(isCompletedThisMonth ? Palette.muted : Palette.mint)
                    }
                } else {
                    Text(store.amount(payment.amount))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                }

                if payment.frequency == .monthly {
                    Text("Semanal: \(store.amount(monthlyAmount / 4))")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.muted)
                } else if payment.frequency == .weekly {
                    Text("Cobro \(store.amount(payment.amount)) × 4 sem.")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.muted)
                } else if payment.frequency == .biweekly {
                    Text("Cobro \(store.amount(payment.amount)) × 2 qnas.")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.muted)
                } else {
                    let base = "Cobro \(store.amount(payment.amount)) ÷ \(months) \(months == 1 ? "mes" : "meses")"
                    if let std = payment.frequency.standardMonths,
                       let nextMonthly = FinanceMath.nextCycleMonthlyEquivalent(for: payment),
                       months != std {
                        Text("\(base) · luego \(store.amount(nextMonthly))/mes")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.muted)
                    } else {
                        Text(base)
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.muted)
                    }
                }
            }

            Button { fixedEntry(payment) } label: {
                Text("Registrar pago")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.mint)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Palette.mint.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)

            if full {
                if payment.frequency != .once {
                    Button { advance(payment) } label: {
                        Label("Siguiente cobro", systemImage: "forward.end.fill")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 9).padding(.vertical, 6)
                            .background(Palette.raised, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.lavender)
                    .help("Avanzar al siguiente periodo (recalcula el ciclo completo)")
                }
                Button {
                    var toggled = payment
                    toggled.isActive.toggle()
                    store.save(toggled)
                } label: {
                    Image(systemName: payment.isActive ? "pause.circle" : "play.circle")
                }
                .buttonStyle(.plain)
                .help(payment.isActive ? "Pausar pago fijo" : "Reactivar pago fijo")

                Button { editor = .fixedPayment(payment) } label: { Image(systemName: "pencil") }.buttonStyle(.plain)
                Button { store.delete(payment) } label: { Image(systemName: "trash") }.buttonStyle(.plain)
            }
        }
        .foregroundStyle(Palette.muted)
        .padding(.vertical, 10)
        .padding(.horizontal, isSelectedForSum && full ? 8 : 0)
        .background(isSelectedForSum && full ? Palette.lavender.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .bottom) { Palette.line.frame(height: 1) }
    }

    private func advance(_ payment: FixedPayment) {
        var next = payment
        next.cycleStart = payment.nextDue
        next.nextDue = payment.frequency.nextDueDate(from: payment.nextDue)
        store.save(next)
    }
    private func fixedEntry(_ payment: FixedPayment) {
        let categoryID = store.data.categories.first(where: { $0.id == payment.categoryID && !$0.isArchived })?.id
            ?? store.data.categories.first(where: { $0.kind == .expense && !$0.isArchived })?.id ?? UUID()
        var entry = MoneyEntry(title: payment.name, amount: payment.amount, date: .now, kind: .expense, categoryID: categoryID)
        entry.fixedPaymentID = payment.id
        entry.notes = payment.notes
        editor = .entry(entry)
    }
    private func debtEntry(_ debt: MoneyDebt, action: DebtAction) {
        var entry = MoneyEntry(title: action == .payment ? "Abono a \(debt.name)" : "Cargo a \(debt.name)", amount: 0, date: .now, kind: .expense,
                               categoryID: action == .payment ? store.debtCategoryID() : store.data.categories.first(where: { $0.kind == .expense && !$0.isArchived })?.id ?? store.debtCategoryID())
        entry.debtID = debt.id; entry.debtAction = action
        editor = .entry(entry)
    }
    private func entryContext(_ entry: MoneyEntry) -> String {
        let category = store.category(entry.categoryID)?.name ?? "Sin categoría"
        let debt = (store.data.debts ?? []).first { $0.id == entry.debtID }?.name ?? "Deuda"
        if entry.debtAction == .charge { return "\(category) · Crédito: \(debt)" }
        if entry.debtAction == .payment { return "Abono: \(debt) · Desde \(sourceName(entry.accountID))" }
        return "\(category) · \(sourceName(entry.accountID))"
    }
    private var wealthCard: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Image(systemName: "sparkle").foregroundStyle(Palette.lavender)
                Text("DINERO TOTAL").font(.system(size: 10, weight: .bold)).tracking(1.7).foregroundStyle(Palette.muted)
                Spacer()
                Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 22)).foregroundStyle(Palette.lavender.opacity(0.65))
            }
            Text(store.amount(store.totalMoney))
                .font(.system(size: 37, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.text).lineLimit(1).minimumScaleFactor(0.65)
            Text("Disponible (\(store.mainAccountName) + Efectivo) + saldo del resto de tus cajas")
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
            HStack(spacing: 8) {
                pill("\(store.data.accounts.count) cajas", symbol: "square.stack.fill", color: Palette.mint)
                pill("Disponible = \(store.mainAccountName) + Efectivo", symbol: "wallet.pass.fill", color: Palette.lavender)
            }
        }
        .padding(23).frame(maxWidth: .infinity, minHeight: 230, alignment: .leading)
        .background(LinearGradient(colors: [Palette.raised, Palette.surface, Palette.background], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Palette.lavender.opacity(0.28)))
    }

    private func balanceCard(_ title: String, subtitle: String? = nil, amount: Double, symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                IconBadge(symbol: symbol, color: color)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.muted)
                    Text(store.amount(amount)).font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.text).lineLimit(1).minimumScaleFactor(0.7)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: title == "Disponible" ? "pencil" : "plus")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            .padding(16).frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.line))
        }.buttonStyle(.plain)
    }

    private func compactStat(_ title: String, value: Double, symbol: String, color: Color) -> some View {
        Surface(padding: 17) {
            HStack(spacing: 12) {
                IconBadge(symbol: symbol, color: color)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 11)).foregroundStyle(Palette.muted)
                    Text(store.amount(value)).font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.text).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
        }
    }

    private func chartPeriodSelector(
        selection: Binding<DashboardChartPeriod>,
        startDate: Binding<Date>,
        endDate: Binding<Date>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(DashboardChartPeriod.allCases) { period in
                        let isSelected = selection.wrappedValue == period
                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                selection.wrappedValue = period
                            }
                        } label: {
                            Text(period.rawValue)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(isSelected ? Palette.background : Palette.text)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(isSelected ? Palette.lavender : Palette.raised, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if selection.wrappedValue == .custom {
                HStack(spacing: 10) {
                    HStack(spacing: 5) {
                        Text("Desde").font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.muted)
                        DatePicker("", selection: startDate, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                    }
                    Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(Palette.muted)
                    HStack(spacing: 5) {
                        Text("Hasta").font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.muted)
                        DatePicker("", selection: endDate, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                    }
                    Spacer()
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Palette.raised.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func flowAtHover(location: CGPoint, plotRect: CGRect, flows: [MonthlyFlow]) -> String? {
        guard plotRect.width > 0, plotRect.height > 0, plotRect.contains(location) else { return nil }
        let bucketCount = (flows.map(\.bucketIndex).max() ?? -1) + 1
        guard bucketCount > 0 else { return nil }
        let relX = location.x - plotRect.minX
        let bucketWidth = plotRect.width / CGFloat(bucketCount)
        let bucketIdx = min(max(Int(relX / bucketWidth), 0), bucketCount - 1)
        let localFraction = (relX - CGFloat(bucketIdx) * bucketWidth) / bucketWidth

        let bucketFlows = flows.filter { $0.bucketIndex == bucketIdx }
        let expenseFlow = bucketFlows.first { $0.kind == .expense }
        let incomeFlow = bucketFlows.first { $0.kind == .income }

        // En SwiftUI Charts MoneyKind.allCases tiene [.expense, .income], así que Gasto va a la izquierda e Ingreso a la derecha
        let preferred = localFraction < 0.5 ? expenseFlow : incomeFlow
        let fallback = localFraction < 0.5 ? incomeFlow : expenseFlow
        if let p = preferred, p.amount > 0 { return p.id }
        if let f = fallback, f.amount > 0 { return f.id }
        return preferred?.id
    }

    private func flowBreakdownDialog(_ flow: MonthlyFlow) -> some View {
        let barColor = flow.kind == .income ? Palette.mint : Palette.peach
        let groupedByCat = Dictionary(grouping: flow.entries, by: \.categoryID)
            .map { catID, items in
                (category: store.category(catID), amount: items.reduce(0.0) { $0 + $1.amount }, count: items.count)
            }
            .sorted { $0.amount > $1.amount }
        let topEntries = flow.entries.sorted { $0.amount > $1.amount }.prefix(3)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(barColor).frame(width: 9, height: 9)
                Text("\(flow.kind == .income ? "Ingresos" : "Gastos") · \(flow.fullPeriodLabel)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.text)
                Spacer()
                Text(store.amount(flow.amount))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(barColor)
            }

            if flow.entries.isEmpty {
                Text("Sin movimientos registrados en esta barra.")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.muted)
            } else {
                Divider()
                Text("¿DE QUÉ SE COMPONE ESTE TOTAL?")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(Palette.muted)

                ForEach(Array(groupedByCat.prefix(4).enumerated()), id: \.offset) { _, item in
                    let pct = flow.amount > 0 ? Int(((item.amount / flow.amount) * 100).rounded()) : 0
                    let cColor = Color(hex: item.category?.tint ?? "#BDA6FF")
                    HStack(spacing: 6) {
                        if let emoji = item.category?.emoji, !emoji.isEmpty {
                            Text(emoji).font(.system(size: 11))
                        } else {
                            Circle().fill(cColor).frame(width: 7, height: 7)
                        }
                        Text(item.category?.name ?? "Sin categoría")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.text)
                            .lineLimit(1)
                        Text("(\(item.count))")
                            .font(.system(size: 9))
                            .foregroundStyle(Palette.muted)
                        Spacer()
                        Text("\(pct)%")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(cColor)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(cColor.opacity(0.15), in: Capsule())
                        Text(store.amount(item.amount))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(Palette.text)
                    }
                }

                if !topEntries.isEmpty {
                    Divider()
                    Text("PRINCIPALES MOVIMIENTOS")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(Palette.muted)
                    ForEach(topEntries) { entry in
                        HStack(spacing: 6) {
                            Text("• \(entry.title)")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.muted)
                                .lineLimit(1)
                            Spacer()
                            Text(store.amount(entry.amount))
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(Palette.text)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.background.opacity(0.97), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(barColor, lineWidth: 1.5))
        .shadow(color: barColor.opacity(0.28), radius: 12, y: 4)
    }

    private var cashFlowCard: some View {
        let flows = monthFlows
        let totalPeriodIncome = flows.filter { $0.kind == .income }.reduce(0.0) { $0 + $1.amount }
        let totalPeriodExpense = flows.filter { $0.kind == .expense }.reduce(0.0) { $0 + $1.amount }
        let hoveredFlow = flows.first { $0.id == hoveredFlowID }
        let maxAmount = flows.map(\.amount).max() ?? 0
        let bucketCount = (flows.map(\.bucketIndex).max() ?? 0) + 1

        return Surface {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Ingresos y gastos").font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(Palette.text)
                        Text("Pasa el cursor sobre cualquier barra para iluminarla y ver de qué se compone su total")
                            .font(.caption).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        pill("+\(store.amount(totalPeriodIncome))", symbol: "arrow.down.left", color: Palette.mint)
                        pill("−\(store.amount(totalPeriodExpense))", symbol: "arrow.up.right", color: Palette.peach)
                    }
                }

                chartPeriodSelector(
                    selection: $cashFlowPeriod,
                    startDate: $cashFlowStartDate,
                    endDate: $cashFlowEndDate
                )

                HStack(spacing: 14) {
                    legend("Gastos", color: Palette.peach)
                    legend("Ingresos", color: Palette.mint)
                    Spacer()
                    if hoveredFlow != nil {
                        Text("Mostrando desglose de la barra seleccionada")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.lavender)
                    }
                }

                if flows.allSatisfy({ $0.amount == 0 }) {
                    EmptyState(symbol: "chart.bar.xaxis", title: "Sin movimientos en este periodo", detail: "Prueba cambiando el filtro de tiempo o registra un ingreso o gasto.")
                        .frame(height: 220)
                } else {
                    cashFlowChartView(flows: flows, hoveredFlow: hoveredFlow, maxAmount: maxAmount, bucketCount: bucketCount)

                    // Cuadro de diálogo flotante con el desglose de la barra iluminada
                    if let hoveredFlow {
                        flowBreakdownDialog(hoveredFlow)
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }
                }
            }
        }
    }

    private func cashFlowBarAnnotation(flow: MonthlyFlow, isHovered: Bool, barColor: Color, bucketCount: Int) -> some View {
        let fontSize: CGFloat = bucketCount > 6 ? 8 : 9.5
        let hPad: CGFloat = isHovered ? 5 : 2
        let vPad: CGFloat = isHovered ? 2 : 0
        let bgColor: Color = isHovered ? barColor.opacity(0.18) : .clear
        return Text(store.amount(flow.amount))
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .foregroundStyle(isHovered ? barColor : Palette.text)
            .padding(.horizontal, hPad)
            .padding(.vertical, vPad)
            .background(bgColor, in: Capsule())
            .lineLimit(1)
            .minimumScaleFactor(0.65)
    }

    private func cashFlowChartView(flows: [MonthlyFlow], hoveredFlow: MonthlyFlow?, maxAmount: Double, bucketCount: Int) -> some View {
        let upperY: Double = maxAmount > 0 ? maxAmount * 1.24 : 100
        let glowColor: Color = {
            guard let hoveredFlow else { return .clear }
            return (hoveredFlow.kind == .income ? Palette.mint : Palette.peach).opacity(0.45)
        }()

        return Chart(flows) { flow in
            let isHovered = hoveredFlowID == flow.id
            let dimmed = hoveredFlowID != nil && !isHovered
            let barColor = flow.kind == .income ? Palette.mint : Palette.peach

            BarMark(x: .value("Mes", flow.label), y: .value("Monto", flow.amount))
                .foregroundStyle(barColor)
                .opacity(dimmed ? 0.30 : 1.0)
                .position(by: .value("Tipo", flow.kind.rawValue))
                .cornerRadius(6)
                .annotation(position: .top, alignment: .center, spacing: 4) {
                    if flow.amount > 0 {
                        cashFlowBarAnnotation(flow: flow, isHovered: isHovered, barColor: barColor, bucketCount: bucketCount)
                    }
                }
        }
        .chartLegend(.hidden)
        .chartYScale(domain: 0...upperY)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Palette.line)
                AxisValueLabel()
            }
        }
        .frame(height: 240)
        .shadow(color: glowColor, radius: 11)
        .overlay {
            GeometryReader { geo in
                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        let fullRect = geo.frame(in: .local)
                        let plotRect = CGRect(
                            x: fullRect.minX + 44,
                            y: fullRect.minY,
                            width: max(1, fullRect.width - 48),
                            height: max(1, fullRect.height - 24)
                        )
                        switch phase {
                        case .active(let location):
                            withAnimation(.easeOut(duration: 0.14)) {
                                hoveredFlowID = flowAtHover(location: location, plotRect: plotRect, flows: flows)
                            }
                        case .ended:
                            withAnimation(.easeOut(duration: 0.14)) {
                                hoveredFlowID = nil
                            }
                        }
                    }
            }
        }
    }

    private var distributionCard: some View {
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                Text("Dónde está tu dinero").font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(Palette.text)
                HStack {
                    Text("Disponible total:")
                        .font(.caption).foregroundStyle(Palette.muted)
                    Spacer()
                    Text(store.amount(store.availableBalance))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.lavender)
                }
                distributionRow("\(store.mainAccountName) (Principal)", amount: store.mainAccountBalance, color: Palette.lavender)
                ForEach(store.data.accounts) { account in
                    let isCash = store.isEfectivoAccount(account)
                    distributionRow(
                        isCash ? "\(account.name) (Suma al disponible)" : account.name,
                        amount: store.accountBalance(account),
                        color: isCash ? Palette.lavender : Palette.mint
                    )
                }
                if store.data.accounts.isEmpty {
                    Text("Añade cajas para separar ahorro y gastos.").font(.caption).foregroundStyle(Palette.muted)
                }
            }
        }
    }

    private func distributionRow(_ name: String, amount: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.text).lineLimit(1)
                Spacer()
                Text(store.amount(amount)).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
            }
            GeometryReader { geometry in
                Capsule().fill(Palette.raised)
                    .overlay(alignment: .leading) {
                        Capsule().fill(color)
                            .frame(width: geometry.size.width * min(max(amount, 0) / max(store.totalMoney, 1), 1))
                    }
            }.frame(height: 7)
        }
    }

    private func categoryAtHover(point: CGPoint, size: CGSize, total: Double) -> UUID? {
        guard total > 0 else { return nil }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dx = point.x - center.x
        let dy = point.y - center.y
        let radius = hypot(dx, dy)
        let maxR = min(size.width, size.height) / 2
        guard radius >= maxR * 0.28 && radius <= maxR * 1.04 else { return nil }
        var angle = atan2(dx, -dy)
        if angle < 0 { angle += 2 * .pi }
        let target = (angle / (2 * .pi)) * total
        var running = 0.0
        for item in categorySpending {
            running += item.amount
            if target <= running { return item.id }
        }
        return categorySpending.last?.id
    }

    private var categoryCard: some View {
        let totalSpend = categorySpending.reduce(0.0) { $0 + $1.amount }
        let hoveredItem = categorySpending.first { $0.id == hoveredCategoryID }

        return Surface {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Gastos por categoría").font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(Palette.text)
                        Text("\(categoryPeriod.rawValue) · Pasa el cursor para iluminar y ver el desglose")
                            .font(.caption).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("TOTAL DEL PERIODO")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(Palette.muted)
                        Text(store.amount(totalSpend))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(Palette.peach)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Palette.peach.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                }

                chartPeriodSelector(
                    selection: $categoryPeriod,
                    startDate: $categoryStartDate,
                    endDate: $categoryEndDate
                )

                if categorySpending.isEmpty {
                    EmptyState(symbol: "chart.pie", title: "Sin gastos en este periodo", detail: "Tus categorías aparecerán aquí cuando registres un gasto en las fechas elegidas.")
                        .frame(height: 220)
                } else {
                    HStack(spacing: 16) {
                        ZStack {
                            Chart(categorySpending) { item in
                                let isHovered = hoveredCategoryID == item.id
                                let dimmed = hoveredCategoryID != nil && !isHovered
                                SectorMark(
                                    angle: .value("Gasto", item.amount),
                                    innerRadius: .ratio(isHovered ? 0.54 : 0.60),
                                    outerRadius: .ratio(hoveredCategoryID == nil ? 0.94 : (isHovered ? 1.0 : 0.87)),
                                    angularInset: 2
                                )
                                .foregroundStyle(Color(hex: item.category?.tint ?? "#A9B6C9"))
                                .opacity(dimmed ? 0.32 : 1.0)
                            }
                            .chartLegend(.hidden)
                            .frame(width: 195, height: 195)
                            .shadow(
                                color: hoveredItem.map { Color(hex: $0.category?.tint ?? "#BDA6FF").opacity(0.45) } ?? .clear,
                                radius: 12
                            )
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    withAnimation(.easeOut(duration: 0.14)) {
                                        hoveredCategoryID = categoryAtHover(point: location, size: CGSize(width: 195, height: 195), total: totalSpend)
                                    }
                                case .ended:
                                    withAnimation(.easeOut(duration: 0.14)) {
                                        hoveredCategoryID = nil
                                    }
                                }
                            }

                            // Recuadro flotante al pasar el mouse (o resumen central)
                            if let hoveredItem {
                                let tintColor = Color(hex: hoveredItem.category?.tint ?? "#BDA6FF")
                                let pct = totalSpend > 0 ? (hoveredItem.amount / totalSpend) * 100 : 0
                                VStack(spacing: 4) {
                                    HStack(spacing: 5) {
                                        if let emoji = hoveredItem.category?.emoji, !emoji.isEmpty {
                                            Text(emoji).font(.system(size: 13))
                                        } else {
                                            Circle().fill(tintColor).frame(width: 8, height: 8)
                                        }
                                        Text(hoveredItem.category?.name ?? "Sin categoría")
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                            .foregroundStyle(Palette.text)
                                            .lineLimit(1)
                                    }
                                    Text(store.amount(hoveredItem.amount))
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundStyle(tintColor)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                    Text(String(format: "%.1f%% del total", pct))
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(Palette.muted)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .background(Palette.background.opacity(0.96), in: RoundedRectangle(cornerRadius: 13))
                                .overlay(RoundedRectangle(cornerRadius: 13).stroke(tintColor, lineWidth: 1.5))
                                .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                                .allowsHitTesting(false)
                                .transition(.scale(scale: 0.92).combined(with: .opacity))
                            } else {
                                VStack(spacing: 2) {
                                    Text("TOTAL GASTADO")
                                        .font(.system(size: 8, weight: .bold, design: .rounded))
                                        .tracking(1)
                                        .foregroundStyle(Palette.muted)
                                    Text(store.amount(totalSpend))
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundStyle(Palette.text)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                    Text("100%")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(Palette.peach)
                                }
                                .allowsHitTesting(false)
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(categorySpending.prefix(7)) { item in
                                let isHovered = hoveredCategoryID == item.id
                                let itemColor = Color(hex: item.category?.tint ?? "#A9B6C9")
                                let pct = totalSpend > 0 ? (item.amount / totalSpend) * 100 : 0
                                HStack(spacing: 7) {
                                    if let emoji = item.category?.emoji, !emoji.isEmpty {
                                        Text(emoji).font(.system(size: 12))
                                    } else {
                                        Circle().fill(itemColor).frame(width: 8, height: 8)
                                    }
                                    Text(item.category?.name ?? "Sin categoría")
                                        .font(.system(size: 11, weight: isHovered ? .bold : .medium))
                                        .foregroundStyle(isHovered ? Palette.text : Palette.muted)
                                        .lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text(String(format: "%.1f%%", pct))
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundStyle(itemColor)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(itemColor.opacity(0.14), in: Capsule())
                                    Text(store.amount(item.amount))
                                        .font(.system(size: 11, weight: isHovered ? .bold : .semibold, design: .rounded))
                                        .foregroundStyle(isHovered ? itemColor : Palette.text)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 9).padding(.vertical, 6)
                                .background(isHovered ? itemColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 9))
                                .overlay(RoundedRectangle(cornerRadius: 9).stroke(isHovered ? itemColor.opacity(0.45) : .clear))
                                .onHover { inside in
                                    withAnimation(.easeOut(duration: 0.14)) {
                                        if inside { hoveredCategoryID = item.id }
                                        else if hoveredCategoryID == item.id { hoveredCategoryID = nil }
                                    }
                                }
                            }
                        }
                    }

                    // Desglose flotante de los movimientos de la categoría iluminada
                    if let hoveredItem, !hoveredItem.entries.isEmpty {
                        let tintColor = Color(hex: hoveredItem.category?.tint ?? "#BDA6FF")
                        let pct = totalSpend > 0 ? (hoveredItem.amount / totalSpend) * 100 : 0
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Desglose de \(hoveredItem.category?.name ?? "Sin categoría") (\(String(format: "%.1f%%", pct)) del total)")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(Palette.text)
                                Spacer()
                                Text(store.amount(hoveredItem.amount))
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(tintColor)
                            }
                            ForEach(hoveredItem.entries.prefix(3)) { entry in
                                HStack {
                                    Text("• \(entry.title) (\(entry.date.formatted(date: .abbreviated, time: .omitted)))")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Palette.muted)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(store.amount(entry.amount))
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Palette.text)
                                }
                            }
                        }
                        .padding(10)
                        .background(Palette.background.opacity(0.95), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(tintColor.opacity(0.6)))
                    }
                }
            }
        }
    }

    private var budgetCard: some View {
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Presupuestos").font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(Palette.text)
                    Spacer()
                    Button { newBudget() } label: { Image(systemName: "plus") }.buttonStyle(.plain).foregroundStyle(Palette.lavender)
                }
                if store.data.budgets.isEmpty {
                    EmptyState(symbol: "chart.bar", title: "Diseña tus límites", detail: "Por semana, mes o un periodo propio.")
                        .frame(height: 220)
                } else {
                    ForEach(store.data.budgets) { budget in
                        let spent = store.budgetSpent(budget)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(budget.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text)
                                Spacer()
                                Button { editor = .budget(budget) } label: { Image(systemName: "pencil") }.buttonStyle(.plain)
                                Button { store.delete(budget) } label: { Image(systemName: "trash") }.buttonStyle(.plain)
                            }.foregroundStyle(Palette.muted)
                            ProgressView(value: min(spent / max(budget.limit, 1), 1)).tint(spent > budget.limit ? Palette.peach : Palette.mint)
                            Text("\(store.amount(spent)) de \(store.amount(budget.limit)) · \(budget.period.rawValue)")
                                .font(.caption).foregroundStyle(Palette.muted)
                        }.padding(.vertical, 5)
                    }
                }
            }
        }
    }

    private func heatColor(for amount: Double, maxAmount: Double) -> Color {
        guard amount > 0, maxAmount > 0 else { return Palette.raised.opacity(0.55) }
        let ratio = min(max(amount / maxAmount, 0), 1)
        if ratio < 0.25 {
            return Palette.mint.opacity(0.28 + ratio * 0.6)
        } else if ratio < 0.55 {
            return Palette.lavender.opacity(0.38 + (ratio - 0.25) * 0.8)
        } else if ratio < 0.82 {
            return Color(hex: "#FFB870").opacity(0.55 + (ratio - 0.55) * 0.7)
        } else {
            return Palette.peach.opacity(0.88)
        }
    }

    private var activeHeatmapMonth: Date {
        let calendar = Calendar.current
        switch heatmapPeriod {
        case .currentMonth:
            return calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        case .previousMonth:
            let currentStart = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
            return calendar.date(byAdding: .month, value: -1, to: currentStart) ?? .now
        default:
            return calendar.dateInterval(of: .month, for: heatmapMonth)?.start ?? heatmapMonth
        }
    }

    private var expenseHeatmapCard: some View {
        let calendar = Calendar.current
        let interval = chartDateInterval(for: heatmapPeriod, customStart: heatmapStartDate, customEnd: heatmapEndDate)
        let periodEntries = store.data.entries.filter {
            $0.countsAsExpense && $0.date >= interval.start && $0.date < interval.endExclusive
        }
        let totalPeriodSpend = periodEntries.reduce(0.0) { $0 + $1.amount }

        let monthStart = activeHeatmapMonth
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        let monthEntriesList = store.data.entries.filter {
            $0.countsAsExpense && $0.date >= monthStart && $0.date < monthEnd
        }

        return Surface {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Image(systemName: "flame.fill").foregroundStyle(Palette.peach)
                            Text("Mapa de calor de gastos")
                                .font(.system(size: 19, weight: .bold, design: .rounded))
                                .foregroundStyle(Palette.text)
                        }
                        Text("Descubre en qué días del mes y en qué días de la semana gastas más. Pasa el cursor sobre cualquier día para ver el detalle.")
                            .font(.caption)
                            .foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("GASTO EN EL PERIODO")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(Palette.muted)
                        Text(store.amount(totalPeriodSpend))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(Palette.peach)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Palette.peach.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                }

                chartPeriodSelector(
                    selection: $heatmapPeriod,
                    startDate: $heatmapStartDate,
                    endDate: $heatmapEndDate
                )

                HStack(alignment: .top, spacing: 18) {
                    heatmapCalendarSection(monthStart: monthStart, monthEntries: monthEntriesList)
                        .frame(maxWidth: .infinity)

                    Divider()

                    heatmapWeekdaySection(periodEntries: periodEntries, totalPeriodSpend: totalPeriodSpend)
                        .frame(width: 390)
                }
            }
        }
    }

    private func heatmapCalendarSection(monthStart: Date, monthEntries: [MoneyEntry]) -> some View {
        let calendar = Calendar.current
        let daysRange = calendar.range(of: .day, in: .month, for: monthStart) ?? 1..<31
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingEmpty = (firstWeekday - store.data.weekStartsOn + 7) % 7

        let entriesByDay: [Int: [MoneyEntry]] = Dictionary(grouping: monthEntries) { entry in
            calendar.component(.day, from: entry.date)
        }
        let amountByDay: [Int: Double] = entriesByDay.mapValues { list in
            list.reduce(0.0) { $0 + $1.amount }
        }
        let maxDayAmount = amountByDay.values.max() ?? 0
        let monthTotal = amountByDay.values.reduce(0.0, +)

        let orderedWeekdays: [(index: Int, short: String)] = (0..<7).map { offset in
            let wd = ((store.data.weekStartsOn - 1 + offset) % 7) + 1
            let sym = calendar.veryShortWeekdaySymbols[wd - 1].uppercased()
            return (wd, sym)
        }

        let hoveredDayNumber: Int? = {
            guard let hoveredHeatmapDay, calendar.isDate(hoveredHeatmapDay, equalTo: monthStart, toGranularity: .month) else { return nil }
            return calendar.component(.day, from: hoveredHeatmapDay)
        }()

        return VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("CALENDARIO DÍA POR DÍA")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(Palette.muted)
                Spacer()
                if heatmapPeriod != .currentMonth && heatmapPeriod != .previousMonth {
                    Button {
                        heatmapMonth = calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
                    } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.lavender)
                }
                Text(monthStart.formatted(.dateTime.month(.wide).year()).capitalized)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.text)
                if heatmapPeriod != .currentMonth && heatmapPeriod != .previousMonth {
                    Button {
                        heatmapMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
                    } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.lavender)
                }
            }

            // Encabezados de día de la semana
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(0..<7, id: \.self) { idx in
                    Text(orderedWeekdays[idx].short)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity)
                }
            }

            // Cuadrícula de días del mes
            let totalCells = leadingEmpty + daysRange.count
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(0..<totalCells, id: \.self) { cellIndex in
                    if cellIndex < leadingEmpty {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(Color.clear)
                            .frame(height: 44)
                    } else {
                        let day = (cellIndex - leadingEmpty) + 1
                        let dayAmount = amountByDay[day] ?? 0
                        let dayDate = calendar.date(byAdding: .day, value: day - 1, to: monthStart) ?? monthStart
                        let isHovered = hoveredDayNumber == day
                        let isPeak = maxDayAmount > 0 && abs(dayAmount - maxDayAmount) < 0.01
                        let cellColor = heatColor(for: dayAmount, maxAmount: maxDayAmount)

                        VStack(spacing: 2) {
                            HStack(spacing: 2) {
                                Text("\(day)")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(dayAmount > 0 ? Palette.text : Palette.muted)
                                if isPeak {
                                    Image(systemName: "flame.fill")
                                        .font(.system(size: 7))
                                        .foregroundStyle(Palette.text)
                                }
                            }
                            if dayAmount > 0 {
                                Text(dayAmount >= 1000 ? String(format: "$%.1fk", dayAmount / 1000) : String(format: "$%.0f", dayAmount))
                                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                                    .foregroundStyle(Palette.text)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.65)
                            } else {
                                Text("—")
                                    .font(.system(size: 8))
                                    .foregroundStyle(Palette.muted.opacity(0.45))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(cellColor, in: RoundedRectangle(cornerRadius: 9))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(isHovered ? Palette.text : (isPeak ? Palette.peach : Palette.line.opacity(0.5)), lineWidth: isHovered ? 2 : 1)
                        )
                        .scaleEffect(isHovered ? 1.05 : 1.0)
                        .onHover { inside in
                            withAnimation(.easeOut(duration: 0.14)) {
                                if inside { hoveredHeatmapDay = dayDate }
                                else if hoveredDayNumber == day { hoveredHeatmapDay = nil }
                            }
                        }
                    }
                }
            }

            // Escala de intensidad
            HStack(spacing: 8) {
                Text("Intensidad:")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                heatLegendItem(label: "Sin gasto", color: Palette.raised.opacity(0.55))
                heatLegendItem(label: "Bajo", color: Palette.mint.opacity(0.45))
                heatLegendItem(label: "Medio", color: Palette.lavender.opacity(0.6))
                heatLegendItem(label: "Alto", color: Color(hex: "#FFB870").opacity(0.75))
                heatLegendItem(label: "Pico máximo", color: Palette.peach.opacity(0.9))
                Spacer()
            }

            // Cuadro flotante al pasar el mouse sobre un día del calendario
            if let day = hoveredDayNumber,
               let dayDate = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                let list = (entriesByDay[day] ?? []).sorted { $0.amount > $1.amount }
                let dayTotal = amountByDay[day] ?? 0
                let pct = monthTotal > 0 ? (dayTotal / monthTotal) * 100 : 0

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(dayDate.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Palette.text)
                        Spacer()
                        if dayTotal > 0 {
                            Text(String(format: "%.1f%% del mes", pct))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Palette.peach)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Palette.peach.opacity(0.14), in: Capsule())
                        }
                        Text(store.amount(dayTotal))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(dayTotal > 0 ? Palette.peach : Palette.muted)
                    }
                    if list.isEmpty {
                        Text("No registraste gastos en este día.")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.muted)
                    } else {
                        ForEach(list.prefix(4)) { entry in
                            let catName = store.category(entry.categoryID)?.name ?? "Sin categoría"
                            HStack {
                                Text("• \(entry.title) (\(catName))")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Palette.muted)
                                    .lineLimit(1)
                                Spacer()
                                Text(store.amount(entry.amount))
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Palette.text)
                            }
                        }
                    }
                }
                .padding(11)
                .background(Palette.background.opacity(0.96), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.peach.opacity(0.55)))
            }
        }
    }

    private func heatLegendItem(label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 11, height: 11)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(Palette.muted)
        }
    }

    private func heatmapWeekdaySection(periodEntries: [MoneyEntry], totalPeriodSpend: Double) -> some View {
        let calendar = Calendar.current
        let groupedByWeekday = Dictionary(grouping: periodEntries) { entry in
            calendar.component(.weekday, from: entry.date)
        }
        let orderedWeekdays: [Int] = (0..<7).map { offset in
            ((store.data.weekStartsOn - 1 + offset) % 7) + 1
        }
        let maxWeekdaySpend = orderedWeekdays.map { wd in
            (groupedByWeekday[wd] ?? []).reduce(0.0) { $0 + $1.amount }
        }.max() ?? 0

        let peakWeekday: (name: String, amount: Double)? = {
            guard maxWeekdaySpend > 0 else { return nil }
            guard let best = orderedWeekdays.max(by: { a, b in
                let sumA = (groupedByWeekday[a] ?? []).reduce(0.0) { $0 + $1.amount }
                let sumB = (groupedByWeekday[b] ?? []).reduce(0.0) { $0 + $1.amount }
                return sumA < sumB
            }) else { return nil }
            let sum = (groupedByWeekday[best] ?? []).reduce(0.0) { $0 + $1.amount }
            return (calendar.weekdaySymbols[best - 1].capitalized, sum)
        }()

        let groupedByExactDay = Dictionary(grouping: periodEntries) { entry in
            calendar.startOfDay(for: entry.date)
        }
        let peakDateRecord: (date: Date, amount: Double)? = {
            guard let best = groupedByExactDay.max(by: { a, b in
                a.value.reduce(0.0) { $0 + $1.amount } < b.value.reduce(0.0) { $0 + $1.amount }
            }) else { return nil }
            return (best.key, best.value.reduce(0.0) { $0 + $1.amount })
        }()

        return VStack(alignment: .leading, spacing: 11) {
            Text("GASTO POR DÍA DE LA SEMANA")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(Palette.muted)

            // Tarjetas resumen del día pico
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DÍA QUE MÁS GASTAS")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(Palette.muted)
                    Text(peakWeekday?.name ?? "Sin datos")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.peach)
                    if let peakWeekday {
                        Text(store.amount(peakWeekday.amount))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.text)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.raised.opacity(0.65), in: RoundedRectangle(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 2) {
                    Text("FECHA RÉCORD")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(Palette.muted)
                    Text(peakDateRecord.map { $0.date.formatted(date: .abbreviated, time: .omitted) } ?? "Sin datos")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.lavender)
                    if let peakDateRecord {
                        Text(store.amount(peakDateRecord.amount))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.text)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.raised.opacity(0.65), in: RoundedRectangle(cornerRadius: 11))
            }

            VStack(spacing: 7) {
                ForEach(orderedWeekdays, id: \.self) { wd in
                    let entries = groupedByWeekday[wd] ?? []
                    let amount = entries.reduce(0.0) { $0 + $1.amount }
                    let pct = totalPeriodSpend > 0 ? (amount / totalPeriodSpend) * 100 : 0
                    let ratio = maxWeekdaySpend > 0 ? min(max(amount / maxWeekdaySpend, 0), 1) : 0
                    let barColor = heatColor(for: amount, maxAmount: maxWeekdaySpend)
                    let isHovered = hoveredHeatmapWeekday == wd
                    let dayName = calendar.weekdaySymbols[wd - 1].capitalized

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(dayName)
                                .font(.system(size: 11, weight: isHovered ? .bold : .semibold))
                                .foregroundStyle(isHovered ? Palette.text : Palette.muted)
                                .frame(width: 78, alignment: .leading)

                            GeometryReader { geo in
                                Capsule()
                                    .fill(Palette.raised)
                                    .overlay(alignment: .leading) {
                                        Capsule()
                                            .fill(barColor)
                                            .frame(width: max(geo.size.width * ratio, amount > 0 ? 6 : 0))
                                    }
                            }
                            .frame(height: 9)

                            Text(String(format: "%.0f%%", pct))
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                .foregroundStyle(amount > 0 ? Palette.peach : Palette.muted)
                                .frame(width: 34, alignment: .trailing)

                            Text(store.amount(amount))
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .foregroundStyle(Palette.text)
                                .frame(width: 82, alignment: .trailing)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(isHovered ? Palette.raised.opacity(0.85) : .clear, in: RoundedRectangle(cornerRadius: 9))
                    .onHover { inside in
                        withAnimation(.easeOut(duration: 0.14)) {
                            if inside { hoveredHeatmapWeekday = wd }
                            else if hoveredHeatmapWeekday == wd { hoveredHeatmapWeekday = nil }
                        }
                    }
                }
            }

            if let wd = hoveredHeatmapWeekday {
                let entries = (groupedByWeekday[wd] ?? []).sorted { $0.amount > $1.amount }
                let dayName = calendar.weekdaySymbols[wd - 1].capitalized
                let amount = entries.reduce(0.0) { $0 + $1.amount }
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("\(dayName) (\(entries.count) mov.)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Palette.text)
                        Spacer()
                        Text(store.amount(amount))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Palette.peach)
                    }
                    ForEach(entries.prefix(3)) { entry in
                        HStack {
                            Text("• \(entry.title)")
                                .font(.system(size: 9.5))
                                .foregroundStyle(Palette.muted)
                                .lineLimit(1)
                            Spacer()
                            Text(store.amount(entry.amount))
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(Palette.text)
                        }
                    }
                }
                .padding(9)
                .background(Palette.background.opacity(0.95), in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Palette.line))
            }
        }
    }

    private var filterableCategories: [MoneyCategory] {
        let usedIDs = Set(store.data.entries.map(\.categoryID))
        return store.data.categories.filter { cat in
            guard !cat.isArchived || usedIDs.contains(cat.id) || selectedCategoryFilters.contains(cat.id) else { return false }
            switch movementTypeFilter {
            case .all: return true
            case .expense: return cat.kind == .expense
            case .income: return cat.kind == .income
            case .transfer: return false
            }
        }
    }

    private var movementsFilterCard: some View {
        let filteredEntries: [MoneyEntry] = history.compactMap { if case .entry(let e) = $0 { return e }; return nil }
        let filteredIncome = filteredEntries.filter { $0.kind == .income }.reduce(0.0) { $0 + $1.amount }
        let filteredExpense = filteredEntries.filter { $0.kind == .expense }.reduce(0.0) { $0 + $1.amount }

        return Surface(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Label("Filtrar movimientos", systemImage: "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.text)
                    Spacer()
                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted)
                        TextField("Buscar concepto o nota…", text: $movementSearchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                        if !movementSearchText.isEmpty {
                            Button { movementSearchText = "" } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(Palette.muted)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 11).padding(.vertical, 7)
                    .frame(width: 220)
                    .background(Palette.raised, in: Capsule())
                    .overlay(Capsule().stroke(Palette.line))

                    if hasActiveMovementFilters {
                        Button("Limpiar filtros") { resetMovementFilters() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.lavender)
                    }
                }

                // Filtro de fechas
                VStack(alignment: .leading, spacing: 8) {
                    Text("PERIODO / FECHAS")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(Palette.muted)
                    HStack(spacing: 7) {
                        ForEach(MovementDatePreset.allCases) { preset in
                            let selected = movementDatePreset == preset
                            Button { movementDatePreset = preset } label: {
                                Text(preset.rawValue)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(selected ? Palette.background : Palette.text)
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(selected ? Palette.lavender : Palette.raised, in: Capsule())
                            }.buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                    }

                    if movementDatePreset == .month {
                        HStack(spacing: 10) {
                            Image(systemName: "calendar").foregroundStyle(Palette.lavender)
                            Button {
                                movementFilterMonth = Calendar.current.date(byAdding: .month, value: -1, to: movementFilterMonth) ?? movementFilterMonth
                            } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain).foregroundStyle(Palette.lavender)

                            Text(movementFilterMonth.formatted(.dateTime.month(.wide).year()).capitalized)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Palette.text)
                                .frame(minWidth: 140)

                            Button {
                                movementFilterMonth = Calendar.current.date(byAdding: .month, value: 1, to: movementFilterMonth) ?? movementFilterMonth
                            } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain).foregroundStyle(Palette.lavender)

                            Button("Mes actual") { movementFilterMonth = .now }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Palette.lavender)
                            Spacer()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Palette.raised.opacity(0.65), in: RoundedRectangle(cornerRadius: 11))
                    } else if movementDatePreset == .custom {
                        HStack(spacing: 14) {
                            HStack(spacing: 7) {
                                Text("Desde").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
                                DatePicker("", selection: $movementStartDate, displayedComponents: .date)
                                    .labelsHidden()
                                    .datePickerStyle(.compact)
                            }
                            Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(Palette.muted)
                            HStack(spacing: 7) {
                                Text("Hasta").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
                                DatePicker("", selection: $movementEndDate, displayedComponents: .date)
                                    .labelsHidden()
                                    .datePickerStyle(.compact)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Palette.raised.opacity(0.65), in: RoundedRectangle(cornerRadius: 11))
                    }
                }

                // Filtro de tipo y categorías
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("TIPO Y CATEGORÍAS")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .tracking(1.1)
                            .foregroundStyle(Palette.muted)
                        Spacer()
                        HStack(spacing: 6) {
                            ForEach(MovementTypeFilter.allCases) { kind in
                                let selected = movementTypeFilter == kind
                                Button {
                                    movementTypeFilter = kind
                                    if kind == .transfer { selectedCategoryFilters.removeAll() }
                                } label: {
                                    Text(kind.rawValue)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(selected ? Palette.background : Palette.muted)
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(selected ? Palette.lavender : Palette.raised, in: Capsule())
                                }.buttonStyle(.plain)
                            }
                        }
                    }

                    if movementTypeFilter != .transfer {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 7) {
                                Button { selectedCategoryFilters.removeAll() } label: {
                                    Text("Todas")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(selectedCategoryFilters.isEmpty ? Palette.background : Palette.text)
                                        .padding(.horizontal, 12).padding(.vertical, 7)
                                        .background(selectedCategoryFilters.isEmpty ? Palette.lavender : Palette.raised, in: Capsule())
                                        .overlay(Capsule().stroke(selectedCategoryFilters.isEmpty ? Palette.lavender : Palette.line))
                                }.buttonStyle(.plain)

                                ForEach(filterableCategories) { category in
                                    let isSelected = selectedCategoryFilters.contains(category.id)
                                    let catColor = Color(hex: category.tint)
                                    Button {
                                        if isSelected { selectedCategoryFilters.remove(category.id) }
                                        else { selectedCategoryFilters.insert(category.id) }
                                    } label: {
                                        HStack(spacing: 6) {
                                            if let emoji = category.emoji, !emoji.isEmpty {
                                                Text(emoji).font(.system(size: 12))
                                            } else {
                                                Image(systemName: category.symbol)
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .foregroundStyle(isSelected ? Palette.background : catColor)
                                            }
                                            Text(category.name)
                                                .font(.system(size: 11, weight: .semibold))
                                                .lineLimit(1)
                                        }
                                        .foregroundStyle(isSelected ? Palette.background : Palette.text)
                                        .padding(.horizontal, 11).padding(.vertical, 7)
                                        .background(isSelected ? catColor : Palette.raised, in: Capsule())
                                        .overlay(Capsule().stroke(isSelected ? catColor : Palette.line))
                                    }.buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 1)
                        }
                    }
                }

                // Barra de totales filtrados
                HStack(spacing: 14) {
                    Text("\(history.count) movimiento\(history.count == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.text)
                    Spacer()
                    if filteredIncome > 0 {
                        Text("Ingresos: +\(store.amount(filteredIncome))")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.mint)
                    }
                    if filteredExpense > 0 {
                        Text("Gastos: −\(store.amount(filteredExpense))")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.peach)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private var historyCard: some View {
        let limitCount = (tab == "Movimientos" && hasActiveMovementFilters) ? 30 : 10
        let balances = mainAccountRunningBalances
        return Surface {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Actividad financiera").font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(Palette.text)
                        Text("Disponible total: \(store.amount(store.availableBalance)) (\(store.mainAccountName): \(store.amount(store.mainAccountBalance)) + Efectivo: \(store.amount(store.efectivoBalance)))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.lavender)
                    }
                    Spacer()
                    Button { newEntry() } label: { Image(systemName: "plus") }.buttonStyle(.plain).foregroundStyle(Palette.lavender)
                }
                if history.isEmpty {
                    if tab == "Movimientos" && hasActiveMovementFilters {
                        EmptyState(symbol: "magnifyingglass", title: "Sin resultados para este filtro", detail: "Prueba cambiando el rango de fechas o las categorías seleccionadas.")
                    } else {
                        EmptyState(symbol: "list.bullet.rectangle", title: "Aún no hay movimientos", detail: "Registra un ingreso, gasto o transferencia.")
                    }
                } else {
                    HStack(spacing: 11) {
                        Text("MOVIMIENTO / CONCEPTO")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("IMPORTE")
                            .frame(width: 115, alignment: .trailing)
                        Text("SALDO \(store.mainAccountName.uppercased())")
                            .frame(width: 175, alignment: .trailing)
                            .lineLimit(1)
                        Spacer().frame(width: 44)
                    }
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 4)
                    .padding(.bottom, 2)
                    .overlay(alignment: .bottom) { Palette.line.frame(height: 1) }

                    ForEach(Array(history.prefix(showAllHistory ? history.count : limitCount))) { item in
                        historyRow(item, step: balances[item.id])
                    }
                    if history.count > limitCount {
                        Button(showAllHistory ? "Mostrar menos" : "Ver todos los movimientos (\(history.count))") { showAllHistory.toggle() }
                            .buttonStyle(.plain).font(.caption).foregroundStyle(Palette.lavender)
                    }
                }
            }
        }
    }

    private func historyRow(_ item: FinanceHistoryItem, step: RunningBalanceStep?) -> some View {
        let balanceAfter = step?.balanceAfter ?? store.mainAccountBalance
        let delta = step?.delta ?? 0

        return HStack(spacing: 11) {
            switch item {
            case .entry(let entry):
                if let category = store.category(entry.categoryID) { CategoryBadge(category: category) }
                else { IconBadge(symbol: "circle.fill", color: Palette.muted) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text)
                    Text("\(entryContext(entry)) · \(entry.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
                }
                Spacer()
                Text("\(entry.kind == .expense ? "−" : "+")\(store.amount(entry.amount))")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(entry.kind == .expense ? Palette.peach : Palette.mint)
                    .frame(width: 115, alignment: .trailing)

                runningBalanceCell(balanceAfter: balanceAfter, delta: delta)

                HStack(spacing: 8) {
                    Button { editor = .entry(entry) } label: { Image(systemName: "pencil") }.buttonStyle(.plain)
                    Button { store.delete(entry) } label: { Image(systemName: "trash") }.buttonStyle(.plain)
                }
                .frame(width: 44, alignment: .trailing)

            case .transfer(let transfer):
                IconBadge(symbol: "arrow.left.arrow.right", color: Palette.lavender)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Transferencia").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text)
                    Text("\(sourceName(transfer.fromAccountID)) → \(sourceName(transfer.toAccountID)) · \(transfer.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
                }
                Spacer()
                Text(store.amount(transfer.amount))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.lavender)
                    .frame(width: 115, alignment: .trailing)

                runningBalanceCell(balanceAfter: balanceAfter, delta: delta)

                HStack(spacing: 8) {
                    Button { editor = .transfer(transfer) } label: { Image(systemName: "pencil") }.buttonStyle(.plain)
                    Button { store.delete(transfer) } label: { Image(systemName: "trash") }.buttonStyle(.plain)
                }
                .frame(width: 44, alignment: .trailing)
            }
        }
        .foregroundStyle(Palette.muted)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Palette.line.frame(height: 1) }
    }

    private func runningBalanceCell(balanceAfter: Double, delta: Double) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(store.amount(balanceAfter))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(balanceAfter < 0 ? Palette.peach : Palette.text)
                .lineLimit(1)
            if abs(delta) > 0.001 {
                Text(delta > 0 ? "Sumó +\(store.amount(delta))" : "Quedó tras −\(store.amount(abs(delta)))")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(delta > 0 ? Palette.mint : Palette.muted)
                    .lineLimit(1)
            } else {
                Text("Sin cambio en principal")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.muted.opacity(0.75))
                    .lineLimit(1)
            }
        }
        .frame(width: 165, alignment: .trailing)
    }

    private var categoriesCard: some View {
        Surface {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text("Categorías").font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(Palette.text)
                    Spacer()
                    Button { newCategory() } label: { Image(systemName: "plus") }.buttonStyle(.plain).foregroundStyle(Palette.lavender)
                }
                ForEach(store.data.categories.filter { !$0.isArchived }) { category in
                    HStack(spacing: 10) {
                        CategoryBadge(category: category)
                        Text(category.name).font(.system(size: 12)).foregroundStyle(Palette.text).lineLimit(1)
                        Spacer()
                        Button { editor = .category(category) } label: { Image(systemName: "pencil") }.buttonStyle(.plain)
                        Button { store.delete(category) } label: { Image(systemName: "archivebox") }.buttonStyle(.plain).help("Archivar sin perder historial")
                    }.foregroundStyle(Palette.muted)
                }
                if store.data.categories.contains(where: { $0.isArchived }) {
                    Button { showArchivedCategories.toggle() } label: {
                        Label(showArchivedCategories ? "Ocultar archivadas" : "Ver archivadas", systemImage: "archivebox")
                            .font(.caption).foregroundStyle(Palette.lavender)
                    }.buttonStyle(.plain)
                    if showArchivedCategories {
                        ForEach(store.data.categories.filter(\.isArchived)) { category in
                            HStack { CategoryBadge(category: category); Text(category.name).foregroundStyle(Palette.muted); Spacer(); Button("Restaurar") { store.restore(category) }.buttonStyle(.plain).foregroundStyle(Palette.lavender) }
                        }
                    }
                }
            }
        }
    }

    private func sourceName(_ accountID: UUID?) -> String {
        accountID.flatMap { id in store.data.accounts.first(where: { $0.id == id })?.name } ?? store.mainAccountName
    }
    private func changeMonth(_ offset: Int) {
        selectedMonth = Calendar.current.date(byAdding: .month, value: offset, to: selectedMonth) ?? selectedMonth
    }
    private func newEntry() {
        editor = .entry(.init(title: "", amount: 0, date: .now, kind: .expense,
                              categoryID: store.data.categories.first(where: { $0.kind == .expense && !$0.isArchived })?.id ?? UUID()))
    }
    private func newTransfer() {
        editor = .transfer(.init(amount: 0, date: .now, fromAccountID: nil, toAccountID: store.data.accounts.first?.id))
    }
    private func newAccount() { editor = .account(.init(name: "", openingBalance: 0)) }
    private func newCategory() { editor = .category(.init(name: "", symbol: "circle.fill", tint: "#BDA6FF", kind: .expense)) }
    private func newBudget() { editor = .budget(.init(name: "", limit: 0, period: .week)) }

    private func primaryButton(_ title: String, symbol: String, color: Color, textColor: Color,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(textColor).padding(.horizontal, 16).padding(.vertical, 11)
                .background(color, in: Capsule())
        }.buttonStyle(.plain)
    }
    private func pill(_ title: String, symbol: String, color: Color) -> some View {
        Label(title, systemImage: symbol).font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color).padding(.horizontal, 10).padding(.vertical, 7)
            .background(color.opacity(0.12), in: Capsule())
    }
    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 6) { Circle().fill(color).frame(width: 7, height: 7); Text(title).font(.caption).foregroundStyle(Palette.muted) }
    }
}
