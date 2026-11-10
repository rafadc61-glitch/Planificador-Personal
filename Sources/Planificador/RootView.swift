import SwiftUI

private enum Page: String, CaseIterable, Identifiable {
    case dashboard = "Inicio", agenda = "Agenda", week = "Semana", goals = "Metas", money = "Finanzas", settings = "Ajustes"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .dashboard: "square.grid.2x2.fill"
        case .agenda: "calendar.day.timeline.left"
        case .week: "calendar"
        case .goals: "scope"
        case .money: "chart.pie.fill"
        case .settings: "slider.horizontal.3"
        }
    }
}

enum Editor: Identifiable {
    case event(PlanEvent), task(PlanTask), goal(PlanGoal), entry(MoneyEntry)
    case debt(MoneyDebt), fixedPayment(FixedPayment)
    case category(MoneyCategory), account(MoneyAccount), budget(BudgetPlan), transfer(MoneyTransfer), availableBalance
    var id: String {
        switch self {
        case .event(let x): "event-\(x.id)"
        case .task(let x): "task-\(x.id)"
        case .goal(let x): "goal-\(x.id)"
        case .entry(let x): "entry-\(x.id)"
        case .category(let x): "category-\(x.id)"
        case .account(let x): "account-\(x.id)"
        case .budget(let x): "budget-\(x.id)"
        case .transfer(let x): "transfer-\(x.id)"
        case .debt(let x): "debt-\(x.id)"
        case .fixedPayment(let x): "fixed-\(x.id)"
        case .availableBalance: "available-balance"
        }
    }
}

struct RootView: View {
    @ObservedObject var store: PlannerStore
    @AppStorage("sidebarVisible") private var isSidebarVisible = true
    @State private var page: Page = .dashboard
    @State private var editor: Editor?
    @State private var selectedDay = Date.now
    @State private var selectedWeek = Date.now
    @State private var selectedDashboardTag: String?

    private var todayTasks: [PlanTask] { store.data.tasks.filter { Calendar.current.isDateInToday($0.due) }.sorted { $0.due < $1.due } }
    private var weekTasks: [PlanTask] {
        let start = weekDay(0)
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? .now
        return store.data.tasks.filter { $0.due >= start && $0.due < end && !Calendar.current.isDateInToday($0.due) }.sorted { $0.due < $1.due }
    }
    private var monthTasks: [PlanTask] {
        store.data.tasks.filter { Calendar.current.isDate($0.due, equalTo: .now, toGranularity: .month) &&
            !Calendar.current.isDateInToday($0.due) && !weekTasks.contains($0) }.sorted { $0.due < $1.due }
    }

    var body: some View {
        HStack(spacing: 0) {
            if isSidebarVisible {
                sidebar
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            VStack(spacing: 0) {
                if !isSidebarVisible {
                    collapsedTopBar
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        switch page {
                        case .dashboard: dashboard
                        case .agenda: agenda
                        case .week: week
                        case .goals: goals
                        case .money: FinanceView(store: store, editor: $editor)
                        case .settings: settings
                        }
                    }
                    .frame(maxWidth: isSidebarVisible ? 1220 : 1380, alignment: .leading)
                    .padding(.horizontal, 36)
                    .padding(.top, isSidebarVisible ? 36 : 24)
                    .padding(.bottom, 50)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Palette.background)
        .preferredColorScheme(store.data.appearance == "light" ? .light : .dark)
        .sheet(item: $editor) { item in
            switch item {
            case .event(let x): EventEditor(event: x, suggestedTags: store.knownTags) { store.save($0); editor = nil }
            case .task(let x): TaskEditor(task: x, suggestedTags: store.knownTags) { store.save($0); editor = nil }
            case .goal(let x): GoalEditor(goal: x, suggestedTags: store.knownTags) { store.save($0); editor = nil }
            case .entry(let x): MoneyEntrySheet(store: store, entry: x) { editor = nil }
            case .debt(let x): DebtEditor(debt: x, currentBalance: store.debtBalance(x)) { store.save($0); editor = nil }
            case .fixedPayment(let x): FixedPaymentSheet(store: store, payment: x) { editor = nil }
            case .category(let x): CategoryEditor(category: x) { store.save($0); editor = nil }
            case .account(let x): AccountEditor(account: x, currentBalance: store.data.accounts.contains(where: { $0.id == x.id }) ? store.accountBalance(x) : x.openingBalance) {
                store.save($0); editor = nil
            }
            case .budget(let x): BudgetSheet(store: store, budget: x) { editor = nil }
            case .transfer(let x): TransferEditor(transfer: x, accounts: store.data.accounts,
                                                  mainAccountName: store.mainAccountName,
                                                  availableBalance: store.mainAccountBalance, accountBalances: accountBalances,
                                                  currencyCode: store.data.currencyCode) { store.save($0); editor = nil }
            case .availableBalance: AvailableBalanceEditor(mainAccountName: store.mainAccountName,
                                                             mainBalance: store.mainAccountBalance,
                                                             cashBalance: store.efectivoBalance,
                                                             currencyCode: store.data.currencyCode) { name, mainBal, cashBal in
                store.updateAvailableSetup(mainName: name, desiredMainBalance: mainBal, desiredCashBalance: cashBal)
                editor = nil
            }
            }
        }
    }
    private var accountBalances: [UUID: Double] {
        Dictionary(uniqueKeysWithValues: store.data.accounts.map { ($0.id, store.accountBalance($0)) })
    }

    private func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.22)) {
            isSidebarVisible.toggle()
        }
    }

    private var sandwichButton: some View {
        Button(action: toggleSidebar) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.text)
                .frame(width: 34, height: 34)
                .background(Palette.raised, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line))
        }
        .buttonStyle(.plain)
        .keyboardShortcut("\\", modifiers: .command)
        .help(isSidebarVisible ? "Ocultar barra lateral (⌘\\)" : "Mostrar barra lateral (⌘\\)")
    }

    private var collapsedTopBar: some View {
        HStack(spacing: 10) {
            sandwichButton
            HStack(spacing: 4) {
                ForEach(Page.allCases) { item in
                    Button { page = item } label: {
                        HStack(spacing: 6) {
                            Image(systemName: item.symbol).font(.system(size: 11))
                            Text(item.rawValue).font(.system(size: 12, weight: page == item ? .semibold : .medium))
                        }
                        .foregroundStyle(page == item ? Palette.text : Palette.muted)
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .background(page == item ? Palette.raised : .clear, in: Capsule())
                    }.buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .padding(.leading, 84)
        .padding(.trailing, 36)
        .padding(.vertical, 10)
        .background(Palette.sidebar.opacity(0.85))
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Palette.background)
                    .frame(width: 40, height: 40)
                    .background(Palette.lavender, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("PLANIFICADOR").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1.2).lineLimit(1)
                    Text("PERSONAL").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1.2).lineLimit(1)
                }.foregroundStyle(Palette.text)
                Spacer(minLength: 4)
                sandwichButton
            }
            .padding(.bottom, 36)
            Text("TU ESPACIO").font(.system(size: 10, weight: .bold)).tracking(1.8).foregroundStyle(Palette.muted).padding(.bottom, 14)
            ForEach(Page.allCases) { item in
                Button { page = item } label: {
                    HStack(spacing: 14) {
                        Image(systemName: item.symbol).frame(width: 18)
                        Text(item.rawValue)
                        Spacer()
                    }
                    .font(.system(size: 14, weight: page == item ? .semibold : .medium))
                    .foregroundStyle(page == item ? Palette.text : Palette.muted)
                    .padding(.horizontal, 14).frame(height: 44)
                    .background(page == item ? Palette.raised : .clear, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).padding(.bottom, 5)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                Text("Un día a la vez, a tu manera.").font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: 16))
        }
        .padding(22).padding(.top, 24)
        .frame(width: 248)
        .background(Palette.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(Palette.line).frame(width: 1) }
    }

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                SectionTitle(title: "Tu día, en orden.", subtitle: Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).year()).capitalized)
                Spacer()
                actionButton("Nueva tarea", symbol: "plus") { newTask() }
            }
            HStack(spacing: 16) {
                statCard("Tareas de hoy", value: "\(todayTasks.filter { !$0.isDone }.count)", symbol: "checkmark.circle.fill", tint: Palette.lavender)
                statCard("Compromisos", value: "\(store.data.events.filter { Calendar.current.isDateInToday($0.start) && !$0.isClosed }.count)", symbol: "calendar", tint: Palette.peach)
                statCard("Pendientes vencidos", value: "\(store.activities.filter(\.isOverdue).count)", symbol: "clock.badge.exclamationmark", tint: Palette.peach)
                statCard("Balance del mes", value: store.amount(store.monthTotal(.income) - store.monthTotal(.expense)), symbol: "wallet.pass.fill", tint: Palette.lavender)
            }
            tagOverview
            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 18) {
                    taskSection("Hoy", subtitle: "Lo que importa ahora", tasks: filteredTasks(todayTasks))
                    taskSection("Esta semana", subtitle: "Próximos pasos", tasks: filteredTasks(weekTasks))
                    taskSection("Este mes", subtitle: "Mirada general", tasks: filteredTasks(monthTasks))
                }.frame(maxWidth: .infinity)
                VStack(spacing: 18) {
                    upcomingCard
                    goalsSummary
                    closureInsights
                    budgetSummary
                }.frame(width: 330)
            }
        }
    }

    private func statCard(_ label: String, value: String, symbol: String, tint: Color) -> some View {
        Surface(padding: 17) {
            VStack(alignment: .leading, spacing: 13) {
                IconBadge(symbol: symbol, color: tint)
                Text(value).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(Palette.text).lineLimit(1).minimumScaleFactor(0.7)
                Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
            }
        }
    }

    private func matchesDashboardTag(_ tags: [String]) -> Bool {
        guard let selectedDashboardTag else { return true }
        if selectedDashboardTag.isEmpty { return tags.isEmpty }
        return tags.contains { $0.caseInsensitiveCompare(selectedDashboardTag) == .orderedSame }
    }
    private func filteredTasks(_ tasks: [PlanTask]) -> [PlanTask] {
        guard selectedDashboardTag != nil else { return tasks }
        return tasks.filter { !$0.isDone && matchesDashboardTag($0.tags ?? []) }
    }

    private var tagOverview: some View {
        let pending = store.activities.filter { !$0.isClosed }
        let labels = ActivityTags.clean(pending.flatMap(\.tags)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let keys = (pending.contains { $0.tags.isEmpty } ? [""] : []) + labels
        return Surface {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pendientes por etiqueta")
                            .font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(Palette.text)
                        Text("Identifica de qué área viene cada pendiente.")
                            .font(.caption).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    if let selectedDashboardTag {
                        Button("Ver todo") { self.selectedDashboardTag = nil }
                            .buttonStyle(.plain).font(.caption).foregroundStyle(Palette.lavender)
                        Text(selectedDashboardTag.isEmpty ? "Sin etiqueta" : selectedDashboardTag)
                            .font(.caption).foregroundStyle(Palette.muted)
                    }
                }
                if keys.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "tag").foregroundStyle(Palette.lavender)
                        Text("Pon etiquetas en tus tareas, compromisos o metas para verlas aquí.")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    }.padding(.vertical, 12)
                } else {
                    LazyVGrid(columns: [.init(.adaptive(minimum: 190), spacing: 11)], spacing: 11) {
                        ForEach(keys, id: \.self) { tag in
                            let items = pending.filter { tag.isEmpty ? $0.tags.isEmpty : $0.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } }
                            Button { selectedDashboardTag = selectedDashboardTag == tag ? nil : tag } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Image(systemName: tag.isEmpty ? "tray.fill" : "tag.fill")
                                            .foregroundStyle(tag.isEmpty ? Palette.muted : Palette.tagColor(tag))
                                        Text(tag.isEmpty ? "Sin etiqueta" : tag)
                                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                                        Spacer(minLength: 0)
                                        Text("\(items.count)").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(Palette.text)
                                    }
                                    if let first = items.sorted(by: { $0.deadline < $1.deadline }).first {
                                        Text("\(first.isOverdue ? "Vencido" : "Siguiente"): \(first.title)").font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
                                    }
                                    let late = items.filter(\.isOverdue).count
                                    if late > 0 {
                                        Text("\(late) vencido\(late == 1 ? "" : "s")")
                                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.peach)
                                    } else {
                                        Text("Al corriente").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.mint)
                                    }
                                }
                                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Palette.raised.opacity(selectedDashboardTag == tag ? 1 : 0.55), in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(selectedDashboardTag == tag ? Palette.lavender : Palette.line))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var closureInsights: some View {
        let classified = store.activities.compactMap(\.timing)
        return Surface {
            VStack(alignment: .leading, spacing: 13) {
                Text("Puntualidad de cierres")
                    .font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(Palette.text)
                Text("Comparada con cada fecha límite.").font(.caption).foregroundStyle(Palette.muted)
                if classified.isEmpty {
                    EmptyState(symbol: "checkmark.seal", title: "Aún sin cierres", detail: "Al completar una actividad verás si fue antes, a tiempo o con atraso.")
                } else {
                    timingCount("Antes de tiempo", count: classified.filter { $0 == .early }.count, color: Palette.mint)
                    timingCount("A tiempo", count: classified.filter { $0 == .onTime }.count, color: Palette.lavender)
                    timingCount("Con atraso", count: classified.filter { $0 == .late }.count, color: Palette.peach)
                }
            }
        }
    }
    private func timingCount(_ title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 9) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.system(size: 12)).foregroundStyle(Palette.text)
            Spacer()
            Text("\(count)").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(color)
        }
    }

    private func taskSection(_ title: String, subtitle: String, tasks: [PlanTask]) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(Palette.text)
                        Text(subtitle).font(.caption).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Button { newTask() } label: { Image(systemName: "plus").font(.headline) }.buttonStyle(.plain).foregroundStyle(Palette.lavender)
                }
                if tasks.isEmpty { EmptyState(symbol: "checkmark.circle", title: "Todo despejado", detail: "Añade una tarea cuando tengas algo pendiente.") }
                else { ForEach(tasks) { taskRow($0) } }
            }
        }
    }

    private func taskRow(_ task: PlanTask) -> some View {
        HStack(spacing: 13) {
            Button {
                var changed = task
                changed.isDone.toggle()
                changed.completedAt = changed.isDone ? .now : nil
                store.save(changed)
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20)).foregroundStyle(task.isDone ? Palette.mint : Palette.muted)
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title).font(.system(size: 13, weight: .medium)).foregroundStyle(task.isDone ? Palette.muted : Palette.text).strikethrough(task.isDone)
                Text(task.due.formatted(.dateTime.weekday(.abbreviated).day().hour().minute()))
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                if let timing = ClosureTiming.classify(closed: task.completedAt, deadline: task.due, includesTime: true), task.isDone {
                    Text("Cerrada: \(timing.rawValue.lowercased())")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(timing == .late ? Palette.peach : Palette.mint)
                } else if !task.isDone && task.due < .now {
                    Text("Vencida").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.peach)
                }
                if let tags = task.tags, !tags.isEmpty {
                    HStack(spacing: 5) { ForEach(tags.prefix(3), id: \.self) { TagChip(name: $0) } }
                }
            }
            Spacer()
            Button { editor = .task(task) } label: { Image(systemName: "pencil") }.buttonStyle(.plain).foregroundStyle(Palette.muted)
            Button { store.delete(task) } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(Palette.muted)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Palette.line.frame(height: 1) }
    }

    private var upcomingCard: some View {
        Surface {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Próximos eventos").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(Palette.text)
                    Spacer()
                    Button { newEvent() } label: { Image(systemName: "plus") }.buttonStyle(.plain).foregroundStyle(Palette.lavender)
                }
                let events = store.data.events.filter { $0.end >= .now && !$0.isClosed && matchesDashboardTag($0.tags ?? []) }.sorted { $0.start < $1.start }.prefix(3)
                if events.isEmpty { EmptyState(symbol: "calendar.badge.plus", title: "Agenda libre", detail: "Crea un compromiso y ponle fecha.") }
                else { ForEach(events) { eventRow($0) } }
            }
        }
    }

    private var goalsSummary: some View {
        Surface {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Tus metas").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(Palette.text)
                    Spacer()
                    Button { newGoal() } label: { Image(systemName: "plus") }.buttonStyle(.plain).foregroundStyle(Palette.lavender)
                }
                let visibleGoals = store.data.goals.filter { !$0.isClosed && matchesDashboardTag($0.tags ?? []) }
                if visibleGoals.isEmpty { EmptyState(symbol: "scope", title: "Sin metas pendientes", detail: "Crea una meta o cambia el filtro de etiquetas.") }
                else {
                    ForEach(visibleGoals.prefix(2)) { goal in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Text(goal.title).font(.subheadline).foregroundStyle(Palette.text); Spacer(); Text(goal.progress, format: .percent.precision(.fractionLength(0))).foregroundStyle(Palette.lavender) }
                            ProgressView(value: goal.progress).tint(Palette.lavender)
                            if let tags = goal.tags, !tags.isEmpty {
                                HStack(spacing: 5) { ForEach(tags.prefix(2), id: \.self) { TagChip(name: $0) } }
                            }
                        }
                    }
                }
            }
        }
    }

    private var budgetSummary: some View {
        Surface {
            VStack(alignment: .leading, spacing: 13) {
                Text("Presupuesto").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(Palette.text)
                if store.data.budgets.isEmpty { EmptyState(symbol: "chart.pie", title: "Sin presupuesto", detail: "Define límites semanales o mensuales.") }
                else {
                    ForEach(store.data.budgets.prefix(2)) { budget in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack { Text(budget.name).foregroundStyle(Palette.text); Spacer(); Text(store.amount(store.budgetSpent(budget))).foregroundStyle(Palette.muted) }
                            ProgressView(value: min(store.budgetSpent(budget) / max(budget.limit, 1), 1)).tint(Palette.peach)
                            Text("de \(store.amount(budget.limit)) · \(budget.period.rawValue)").font(.caption).foregroundStyle(Palette.muted)
                        }
                    }
                }
            }
        }
    }

    private var agenda: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { SectionTitle(title: "Agenda", subtitle: "Tus compromisos y entregas, en un solo lugar."); Spacer(); actionButton("Nuevo evento", symbol: "plus") { newEvent() } }
            Surface {
                HStack { DatePicker("Día", selection: $selectedDay, displayedComponents: .date).datePickerStyle(.compact); Spacer(); Text(selectedDay.shortDay.capitalized).foregroundStyle(Palette.muted) }
            }
            let events = store.data.events.filter { Calendar.current.isDate($0.start, inSameDayAs: selectedDay) }.sorted { $0.start < $1.start }
            Surface {
                VStack(alignment: .leading, spacing: 15) {
                    Text("Compromisos").font(.title3.bold()).foregroundStyle(Palette.text)
                    if events.isEmpty { EmptyState(symbol: "calendar", title: "Sin eventos este día", detail: "Tu tiempo está listo para planearse.") }
                    else { ForEach(events) { eventRow($0) } }
                }
            }
            taskSection("Tareas del día", subtitle: "Pendientes y recordatorios", tasks: store.data.tasks.filter { Calendar.current.isDate($0.due, inSameDayAs: selectedDay) }.sorted { $0.due < $1.due })
        }
    }

    private func eventRow(_ event: PlanEvent) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3).fill(event.kind == .trabajo ? Palette.lavender : event.kind == .bienestar ? Palette.mint : Palette.peach).frame(width: 4, height: 42)
            Button {
                var changed = event
                changed.isDone = !event.isClosed
                changed.completedAt = changed.isClosed ? .now : nil
                store.save(changed)
            } label: {
                Image(systemName: event.isClosed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18)).foregroundStyle(event.isClosed ? Palette.mint : Palette.muted)
            }.buttonStyle(.plain).help(event.isClosed ? "Reabrir compromiso" : "Cerrar compromiso")
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                Text("\(event.start.hourText) – \(event.end.hourText) · \(event.kind.rawValue)").font(.caption).foregroundStyle(Palette.muted)
                if let timing = ClosureTiming.classify(closed: event.completedAt, deadline: event.end, includesTime: true), event.isClosed {
                    Text("Cerrado: \(timing.rawValue.lowercased())").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(timing == .late ? Palette.peach : Palette.mint)
                }
                if let tags = event.tags, !tags.isEmpty {
                    HStack(spacing: 5) { ForEach(tags.prefix(2), id: \.self) { TagChip(name: $0) } }
                }
            }
            Spacer()
            Button { editor = .event(event) } label: { Image(systemName: "pencil") }.buttonStyle(.plain).foregroundStyle(Palette.muted)
            Button { store.delete(event) } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(Palette.muted)
        }
        .padding(.vertical, 7)
    }

    private var week: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { SectionTitle(title: "Tu semana", subtitle: "Una vista clara para diseñar tus días."); Spacer(); actionButton("Nuevo evento", symbol: "plus") { newEvent() } }
            HStack(spacing: 14) {
                Button { selectedWeek = Calendar.current.date(byAdding: .day, value: -7, to: selectedWeek) ?? selectedWeek } label: { Image(systemName: "chevron.left") }
                Text("\(weekDay(0, around: selectedWeek).formatted(date: .abbreviated, time: .omitted)) – \(weekDay(6, around: selectedWeek).formatted(date: .abbreviated, time: .omitted))").font(.subheadline.bold()).foregroundStyle(Palette.text)
                Button { selectedWeek = Calendar.current.date(byAdding: .day, value: 7, to: selectedWeek) ?? selectedWeek } label: { Image(systemName: "chevron.right") }
                Spacer()
                Button("Hoy") { selectedWeek = .now }
            }.buttonStyle(.plain).foregroundStyle(Palette.lavender)
            HStack(alignment: .top, spacing: 10) {
                ForEach(0..<7, id: \.self) { offset in
                    let day = weekDay(offset, around: selectedWeek)
                    Surface(padding: 12) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.muted)
                            Text(day.formatted(.dateTime.day())).font(.system(size: 27, weight: .bold, design: .rounded)).foregroundStyle(Calendar.current.isDateInToday(day) ? Palette.lavender : Palette.text)
                            Rectangle().fill(Palette.line).frame(height: 1)
                            ForEach(store.data.events.filter { Calendar.current.isDate($0.start, inSameDayAs: day) }.sorted { $0.start < $1.start }) { event in
                                Button { editor = .event(event) } label: {
                                    VStack(alignment: .leading, spacing: 4) { Text(event.start.hourText).font(.caption2); Text(event.title).font(.system(size: 11, weight: .semibold)).lineLimit(2) }
                                        .foregroundStyle(Palette.text).frame(maxWidth: .infinity, alignment: .leading).padding(8).background(Palette.lavender.opacity(0.17), in: RoundedRectangle(cornerRadius: 9))
                                }.buttonStyle(.plain)
                            }
                            ForEach(store.data.tasks.filter { Calendar.current.isDate($0.due, inSameDayAs: day) }) { task in
                                Button { editor = .task(task) } label: { Label(task.title, systemImage: task.isDone ? "checkmark.circle.fill" : "circle").font(.system(size: 11)).lineLimit(2).foregroundStyle(Palette.muted) }.buttonStyle(.plain)
                            }
                            Spacer(minLength: 80)
                        }
                    }
                }
            }
        }
    }

    private func weekDay(_ offset: Int, around date: Date = .now) -> Date {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        let delta = (weekday - store.data.weekStartsOn + 7) % 7
        let start = calendar.date(byAdding: .day, value: -delta, to: calendar.startOfDay(for: date)) ?? date
        return calendar.date(byAdding: .day, value: offset, to: start) ?? date
    }

    private var goals: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { SectionTitle(title: "Metas e hitos", subtitle: "Avanza paso a paso, con fechas y notas."); Spacer(); actionButton("Nueva meta", symbol: "plus") { newGoal() } }
            if store.data.goals.isEmpty { Surface { EmptyState(symbol: "scope", title: "Tu primera meta empieza aquí", detail: "Crea una meta y añade los hitos que te llevarán a ella.") } }
            else {
                LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 16) {
                    ForEach(store.data.goals) { goal in
                        Surface {
                            VStack(alignment: .leading, spacing: 15) {
                                HStack { IconBadge(symbol: "scope", color: Palette.lavender); Spacer(); Button { editor = .goal(goal) } label: { Image(systemName: "pencil") }.buttonStyle(.plain); Button { store.delete(goal) } label: { Image(systemName: "trash") }.buttonStyle(.plain) }.foregroundStyle(Palette.muted)
                                Text(goal.title).font(.title3.bold()).foregroundStyle(Palette.text)
                                if let tags = goal.tags, !tags.isEmpty {
                                    HStack(spacing: 5) { ForEach(tags.prefix(3), id: \.self) { TagChip(name: $0) } }
                                }
                                Text(goal.notes.isEmpty ? "Sin notas" : goal.notes).font(.caption).foregroundStyle(Palette.muted).lineLimit(2)
                                Text("Fecha objetivo: \(goal.targetDate.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(Palette.muted)
                                if let timing = ClosureTiming.classify(closed: goal.completedAt, deadline: goal.targetDate, includesTime: false), goal.isClosed {
                                    Text("Cerrada: \(timing.rawValue.lowercased())")
                                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(timing == .late ? Palette.peach : Palette.mint)
                                }
                                ProgressView(value: goal.progress).tint(Palette.lavender)
                                Text("\(goal.milestones.filter(\.isDone).count) de \(goal.milestones.count) hitos · \(Int(goal.progress * 100)) %").font(.caption).foregroundStyle(Palette.muted)
                                ForEach(goal.milestones) { milestone in
                                    Button {
                                        var changed = goal
                                        if let index = changed.milestones.firstIndex(where: { $0.id == milestone.id }) {
                                            changed.milestones[index].isDone.toggle()
                                            changed.milestones[index].completedAt = changed.milestones[index].isDone ? .now : nil
                                        }
                                        store.save(changed)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 5) {
                                            HStack { Label(milestone.title, systemImage: milestone.isDone ? "checkmark.circle.fill" : "circle"); Spacer(); Text(milestone.dueDate.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(Palette.muted) }
                                                .foregroundStyle(milestone.isDone ? Palette.mint : Palette.text).font(.subheadline)
                                            if let tags = milestone.tags, !tags.isEmpty {
                                                HStack(spacing: 5) { ForEach(tags.prefix(2), id: \.self) { TagChip(name: $0) } }
                                            }
                                            if let timing = ClosureTiming.classify(closed: milestone.completedAt, deadline: milestone.dueDate, includesTime: false), milestone.isDone {
                                                Text(timing.rawValue).font(.system(size: 10, weight: .semibold)).foregroundStyle(timing == .late ? Palette.peach : Palette.mint)
                                            }
                                        }
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionTitle(title: "A tu manera", subtitle: "Ajusta el planificador a tu ritmo.")
            Surface {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Apariencia y preferencias").font(.title3.bold()).foregroundStyle(Palette.text)
                    HStack { Text("Nombre de tu espacio"); Spacer(); TextField("Nombre", text: $store.data.name).textFieldStyle(.roundedBorder).frame(width: 250) }
                    HStack { Text("Apariencia"); Spacer(); Picker("", selection: $store.data.appearance) { Text("Oscuro").tag("dark"); Text("Claro").tag("light") }.labelsHidden().frame(width: 250) }
                    HStack { Text("Inicio de semana"); Spacer(); Picker("", selection: $store.data.weekStartsOn) { ForEach(1...7, id: \.self) { day in Text(weekdayName(day)).tag(day) } }.labelsHidden().frame(width: 250) }
                    HStack { Text("Moneda"); Spacer(); TextField("MXN", text: $store.data.currencyCode).textFieldStyle(.roundedBorder).frame(width: 250) }
                }.foregroundStyle(Palette.text)
            }
            Surface {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Conexiones y avisos").font(.title3.bold()).foregroundStyle(Palette.text)
                    HStack { VStack(alignment: .leading) { Text("Notificaciones"); Text("Recibe avisos de tareas y eventos.").font(.caption).foregroundStyle(Palette.muted) }; Spacer(); Text(store.notificationStatus).foregroundStyle(Palette.muted); Button("Activar") { store.requestNotifications() } }
                    HStack { VStack(alignment: .leading) { Text("Calendario de macOS"); Text("Usa tu calendario iCloud si está configurado en este Mac.").font(.caption).foregroundStyle(Palette.muted) }; Spacer(); Text(store.calendarStatus).foregroundStyle(Palette.muted); Button("Conectar") { Task { _ = await store.requestCalendarAccess() } } }
                }.foregroundStyle(Palette.text)
            }
            Text("Los datos se guardan en este Mac. Los compromisos que marques para Calendario se añaden al calendario predeterminado de macOS.")
                .font(.caption).foregroundStyle(Palette.muted)
        }
    }

    private func weekdayName(_ day: Int) -> String { Calendar.current.weekdaySymbols[day - 1].capitalized }
    private func actionButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: symbol).font(.system(size: 12, weight: .semibold)).padding(.horizontal, 15).padding(.vertical, 11).foregroundStyle(Palette.background).background(Palette.lavender, in: Capsule()) }.buttonStyle(.plain)
    }
    private func newTask() { editor = .task(.init(title: "", due: .now)) }
    private func newEvent() { editor = .event(.init(title: "", start: .now, end: .now.addingTimeInterval(3600))) }
    private func newGoal() { editor = .goal(.init(title: "", targetDate: .now.addingTimeInterval(30 * 86400))) }
}


// Observe the store inside the sheet so newly created categories, debts and boxes are immediately available.
private struct MoneyEntrySheet: View {
    @ObservedObject var store: PlannerStore
    let entry: MoneyEntry
    let close: () -> Void
    var body: some View {
        EntryEditor(entry: entry, categories: store.data.categories, debts: store.data.debts ?? [], accounts: store.data.accounts,
                    mainAccountName: store.mainAccountName,
                    availableBalance: store.mainAccountBalance,
                    accountBalances: Dictionary(uniqueKeysWithValues: store.data.accounts.map { ($0.id, store.accountBalance($0)) }),
                    currencyCode: store.data.currencyCode,
                    onCreateCategory: { store.save($0) }) { store.save($0); close() }
    }
}

private struct FixedPaymentSheet: View {
    @ObservedObject var store: PlannerStore
    let payment: FixedPayment
    let close: () -> Void
    var body: some View {
        FixedPaymentEditor(
            payment: payment,
            categories: store.data.categories,
            suggestedTags: store.knownFixedPaymentTags,
            currencyCode: store.data.currencyCode,
            onCreateCategory: { store.save($0) }
        ) { store.save($0); close() }
    }
}

private struct BudgetSheet: View {
    @ObservedObject var store: PlannerStore
    let budget: BudgetPlan
    let close: () -> Void
    var body: some View {
        BudgetEditor(
            budget: budget,
            categories: store.data.categories,
            currencyCode: store.data.currencyCode,
            monthlyFixedTotal: store.monthlyFixedTotal,
            monthlyFixedRemaining: store.monthlyFixedRemaining,
            simulatedIncome: store.data.simulatedIncome,
            onCreateCategory: { store.save($0) }
        ) { store.save($0); close() }
    }
}
