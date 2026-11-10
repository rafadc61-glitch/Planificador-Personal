import SwiftUI

private struct EditorFrame<Content: View>: View {
    let title: String
    let canSave: Bool
    let save: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 15) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Palette.background)
                    .frame(width: 52, height: 52)
                    .background(Palette.lavender, in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 5) {
                    Text("PLANIFICADOR PERSONAL")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.6).foregroundStyle(Palette.lavender)
                    Text(title).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(Palette.text)
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 30, height: 30)
                        .background(Palette.raised, in: Circle())
                }.buttonStyle(.plain)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Palette.surface, Palette.background], startPoint: .topLeading, endPoint: .bottomTrailing))
            ScrollView {
                content
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.line))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
            HStack(spacing: 12) {
                Text("Los cambios se guardan al confirmar.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                Spacer()
                Button("Cancelar") { dismiss() }
                    .buttonStyle(.plain).foregroundStyle(Palette.muted).padding(.horizontal, 14)
                Button(action: save) {
                    Label("Guardar", systemImage: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.background)
                        .padding(.horizontal, 19).padding(.vertical, 11)
                        .background(canSave ? Palette.lavender : Palette.muted.opacity(0.35), in: Capsule())
                }.buttonStyle(.plain).disabled(!canSave)
            }
            .padding(.horizontal, 24).padding(.vertical, 17)
            .background(Palette.sidebar)
        }
        .frame(width: 620, height: 680)
        .background(Palette.background)
        .tint(Palette.lavender)
    }
    private var symbol: String {
        switch title {
        case "Compromiso": "calendar.badge.plus"
        case "Tarea o recordatorio": "checklist"
        case "Meta": "scope"
        case "Movimiento": "arrow.left.arrow.right"
        case "Transferencia": "arrow.left.arrow.right.circle.fill"
        case "Saldo disponible": "wallet.pass.fill"
        case "Deuda": "creditcard.fill"
        case "Pago fijo": "calendar.badge.clock"
        case "Categoría": "square.grid.2x2.fill"
        case "Cuenta o caja de ahorro": "building.columns.fill"
        default: "chart.pie.fill"
        }
    }
    private var subtitle: String {
        switch title {
        case "Compromiso": "Un espacio para lo que tiene fecha y hora."
        case "Tarea o recordatorio": "Organiza lo pendiente a tu ritmo."
        case "Meta": "Convierte una idea en pasos concretos."
        case "Movimiento": "Lleva tus finanzas con claridad."
        case "Transferencia": "Mueve dinero sin cambiar tu patrimonio total."
        case "Deuda": "Tarjetas, préstamos y compromisos bajo control."
        case "Pago fijo": "Cada servicio y su próxima fecha de pago."
        case "Saldo disponible": "Actualiza el dinero que tienes hoy fuera de las cajas."
        case "Categoría": "Haz que tus gastos se vean como tú quieras."
        case "Cuenta o caja de ahorro": "Cada peso en el lugar que elegiste."
        default: "Define un límite a tu medida."
        }
    }
}

private enum ReminderUnit: String, CaseIterable, Identifiable {
    case minutes = "minutos", hours = "horas", days = "días", weeks = "semanas"
    var id: String { rawValue }
    var multiplier: Int {
        switch self { case .minutes: 1; case .hours: 60; case .days: 1440; case .weeks: 10080 }
    }
}

private struct ReminderDraft: Identifiable {
    var id = UUID()
    var value: Int
    var unit: ReminderUnit
    var minutes: Int { max(0, min(value, 525600 / unit.multiplier)) * unit.multiplier }
    var isValid: Bool { value >= 0 && value <= 525600 / unit.multiplier }
    init(value: Int, unit: ReminderUnit) { self.value = value; self.unit = unit }
    init(minutes: Int) {
        if minutes > 0 && minutes % 10080 == 0 { value = minutes / 10080; unit = .weeks }
        else if minutes > 0 && minutes % 1440 == 0 { value = minutes / 1440; unit = .days }
        else if minutes > 0 && minutes % 60 == 0 { value = minutes / 60; unit = .hours }
        else { value = minutes; unit = .minutes }
    }
}

private struct ReminderEditor: View {
    @Binding var reminders: [ReminderDraft]
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("Avisos personalizados", systemImage: "bell.badge.fill")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
                Spacer()
                Text("\(reminders.count) activos")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.lavender)
            }
            Text("Añade tantos avisos como necesites. Puedes escribir, por ejemplo, 2 días antes.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
            ForEach($reminders) { $reminder in
                HStack(spacing: 9) {
                    Image(systemName: "bell.fill").foregroundStyle(Palette.lavender).frame(width: 22)
                    Text("Avisarme").font(.system(size: 12)).foregroundStyle(Palette.text)
                    MoneyField(placeholder: "0", value: Binding(get: { Double(reminder.value) }, set: { reminder.value = Int($0) }), allowsNegative: false, allowsDecimals: false)
                        .textFieldStyle(.plain).multilineTextAlignment(.center)
                        .frame(width: 54).padding(.vertical, 9)
                        .background(Palette.raised, in: RoundedRectangle(cornerRadius: 9))
                    Picker("", selection: $reminder.unit) {
                        ForEach(ReminderUnit.allCases) { unit in Text(unit.rawValue).tag(unit) }
                    }.labelsHidden().frame(width: 110)
                    Text("antes").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    Spacer()
                    Button { reminders.removeAll { $0.id == reminder.id } } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(Palette.raised.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
            }
            HStack(spacing: 8) {
                reminderPreset("+ 15 min", value: 15, unit: .minutes)
                reminderPreset("+ 1 hora", value: 1, unit: .hours)
                reminderPreset("+ 1 día", value: 1, unit: .days)
                reminderPreset("+ 2 días", value: 2, unit: .days)
                Button { reminders.append(.init(value: 1, unit: .days)) } label: {
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.lavender).padding(8)
                        .background(Palette.raised, in: Circle())
                }.buttonStyle(.plain).help("Añadir aviso editable")
            }
            if reminders.contains(where: { !$0.isValid }) {
                Text("Cada aviso puede anticiparse hasta un año.")
                    .font(.caption).foregroundStyle(Palette.peach)
            }
        }
        .padding(16)
        .background(Palette.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Palette.line))
    }
    private func reminderPreset(_ title: String, value: Int, unit: ReminderUnit) -> some View {
        Button { reminders.append(.init(value: value, unit: unit)) } label: {
            Text(title).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.lavender).padding(.horizontal, 9).padding(.vertical, 7)
                .background(Palette.lavender.opacity(0.11), in: Capsule())
        }.buttonStyle(.plain)
    }
}

private struct ActivityTagEditor: View {
    @Binding var tags: [String]?
    let suggestions: [String]
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Etiquetas", systemImage: "tag.fill")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
            Text("Úsalas para agrupar tus pendientes en el dashboard.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
            if !(tags ?? []).isEmpty {
                LazyVGrid(columns: [.init(.adaptive(minimum: 112), spacing: 7)], alignment: .leading, spacing: 7) {
                    ForEach(tags ?? [], id: \.self) { name in
                        Button { tags = (tags ?? []).filter { $0 != name } } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "tag.fill").font(.system(size: 10))
                                Text(name).lineLimit(1)
                                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.tagColor(name))
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(Palette.tagColor(name).opacity(0.13), in: Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("Ej. Trabajo, Salud, Cliente A", text: $draft)
                    .textFieldStyle(.plain).onSubmit(addTag)
                    .padding(10).background(Palette.raised, in: RoundedRectangle(cornerRadius: 10))
                Button(action: addTag) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.background)
                        .frame(width: 32, height: 32)
                        .background(Palette.lavender, in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain).disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            let unused = suggestions.filter { suggestion in
                !(tags ?? []).contains { $0.caseInsensitiveCompare(suggestion) == .orderedSame }
            }
            if !unused.isEmpty {
                Text("USADAS ANTES").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(Palette.muted)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(unused.prefix(8), id: \.self) { name in
                            Button { tags = ActivityTags.clean((tags ?? []) + [name]) } label: { TagChip(name: name) }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Palette.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Palette.line))
    }

    private func addTag() {
        tags = ActivityTags.clean((tags ?? []) + draft.split(separator: ",").map(String.init))
        draft = ""
    }
}

private struct ClosureEditor: View {
    @Binding var isClosed: Bool
    @Binding var completedAt: Date?
    let deadline: Date
    let includesTime: Bool
    let noun: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(Palette.mint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Cierre y puntualidad").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
                    Text("Compara el cierre con la fecha límite.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Text("Cerrar").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
                Toggle("", isOn: $isClosed).labelsHidden()
            }
            if isClosed {
                if completedAt != nil {
                    field("Fecha de cierre") {
                        DatePicker("", selection: Binding(get: { completedAt ?? .now }, set: { completedAt = $0 }),
                                   in: ...Date.now, displayedComponents: includesTime ? [.date, .hourAndMinute] : .date)
                            .labelsHidden()
                    }
                    if let timing = ClosureTiming.classify(closed: completedAt, deadline: deadline, includesTime: includesTime) {
                        HStack(spacing: 8) {
                            Label(timing.rawValue, systemImage: timing == .late ? "clock.badge.exclamationmark" : "checkmark.circle.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(timing == .late ? Palette.peach : Palette.mint)
                            if let difference = ClosureTiming.differenceText(closed: completedAt, deadline: deadline, includesTime: includesTime) {
                                Text("· \(difference)").font(.system(size: 11)).foregroundStyle(Palette.muted)
                            }
                        }
                    }
                } else {
                    HStack {
                        Text("\(noun) sin fecha de cierre registrada.").font(.caption).foregroundStyle(Palette.muted)
                        Spacer()
                        Button("Registrar ahora") { completedAt = .now }
                            .buttonStyle(.plain).foregroundStyle(Palette.lavender)
                    }
                }
            }
        }
        .padding(16)
        .background(Palette.mint.opacity(0.07), in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Palette.mint.opacity(0.17)))
        .onChange(of: isClosed) { oldValue, newValue in
            if newValue && !oldValue && completedAt == nil { completedAt = .now }
            if !newValue { completedAt = nil }
        }
    }
}

struct EventEditor: View {
    @State private var event: PlanEvent
    @State private var reminders: [ReminderDraft]
    let suggestedTags: [String]
    let onSave: (PlanEvent) -> Void
    init(event: PlanEvent, suggestedTags: [String] = [], onSave: @escaping (PlanEvent) -> Void) {
        _event = State(initialValue: event)
        _reminders = State(initialValue: event.reminders.map(ReminderDraft.init(minutes:)))
        self.suggestedTags = suggestedTags
        self.onSave = onSave
    }
    var body: some View {
        EditorFrame(title: "Compromiso", canSave: !event.title.trimmingCharacters(in: .whitespaces).isEmpty && event.end > event.start && reminders.allSatisfy(\.isValid), save: {
            var saved = event
            saved.reminderOffsets = Array(Set(reminders.map(\.minutes))).sorted()
            saved.reminderMinutes = nil
            onSave(saved)
        }) {
            VStack(alignment: .leading, spacing: 20) {
                field("Título") { TextField("¿Qué tienes planeado?", text: $event.title) }
                HStack(spacing: 12) {
                    field("Empieza") { DatePicker("", selection: $event.start, displayedComponents: [.date, .hourAndMinute]).labelsHidden() }
                    field("Termina") { DatePicker("", selection: $event.end, displayedComponents: [.date, .hourAndMinute]).labelsHidden() }
                }
                field("Tipo") { Picker("", selection: $event.kind) { ForEach(EventKind.allCases) { kind in Label(kind.rawValue, systemImage: kind.symbol).tag(kind) } }.labelsHidden() }
                ActivityTagEditor(tags: $event.tags, suggestions: suggestedTags)
                ReminderEditor(reminders: $reminders)
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.plus").foregroundStyle(Palette.mint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Añadir al Calendario").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                        Text("Usa el calendario predeterminado de macOS o iCloud.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Toggle("", isOn: $event.addToCalendar).labelsHidden()
                }.padding(14).background(Palette.mint.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
                ClosureEditor(isClosed: Binding(get: { event.isClosed }, set: { event.isDone = $0 }),
                              completedAt: $event.completedAt, deadline: event.end, includesTime: true, noun: "Compromiso")
                field("Notas") { TextEditor(text: $event.notes).scrollContentBackground(.hidden).frame(height: 80) }
            }
        }
    }
}

struct TaskEditor: View {
    @State private var task: PlanTask
    @State private var reminders: [ReminderDraft]
    let suggestedTags: [String]
    let onSave: (PlanTask) -> Void
    init(task: PlanTask, suggestedTags: [String] = [], onSave: @escaping (PlanTask) -> Void) {
        _task = State(initialValue: task)
        _reminders = State(initialValue: task.reminders.map(ReminderDraft.init(minutes:)))
        self.suggestedTags = suggestedTags
        self.onSave = onSave
    }
    var body: some View {
        EditorFrame(title: "Tarea o recordatorio", canSave: !task.title.trimmingCharacters(in: .whitespaces).isEmpty && reminders.allSatisfy(\.isValid), save: {
            var saved = task
            saved.reminderOffsets = Array(Set(reminders.map(\.minutes))).sorted()
            saved.reminderMinutes = nil
            onSave(saved)
        }) {
            VStack(alignment: .leading, spacing: 20) {
                field("Título") { TextField("¿Qué necesitas hacer?", text: $task.title) }
                field("Fecha y hora") { DatePicker("", selection: $task.due, displayedComponents: [.date, .hourAndMinute]).labelsHidden() }
                ActivityTagEditor(tags: $task.tags, suggestions: suggestedTags)
                ReminderEditor(reminders: $reminders)
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.plus").foregroundStyle(Palette.mint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Añadir al Calendario").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                        Text("La tarea ocupará 30 minutos desde la hora elegida.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(get: { task.isOnCalendar }, set: { task.addToCalendar = $0 })).labelsHidden()
                }.padding(14).background(Palette.mint.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
                ClosureEditor(isClosed: $task.isDone, completedAt: $task.completedAt,
                              deadline: task.due, includesTime: true, noun: "Tarea")
                field("Notas") { TextEditor(text: $task.notes).scrollContentBackground(.hidden).frame(height: 100) }
            }
        }
    }
}

struct GoalEditor: View {
    @State private var goal: PlanGoal
    let suggestedTags: [String]
    let onSave: (PlanGoal) -> Void
    init(goal: PlanGoal, suggestedTags: [String] = [], onSave: @escaping (PlanGoal) -> Void) {
        _goal = State(initialValue: goal); self.suggestedTags = suggestedTags; self.onSave = onSave
    }
    var body: some View {
        EditorFrame(title: "Meta", canSave: !goal.title.trimmingCharacters(in: .whitespaces).isEmpty, save: { onSave(goal) }) {
            VStack(alignment: .leading, spacing: 18) {
                field("Nombre") { TextField("¿Qué quieres lograr?", text: $goal.title) }
                field("Fecha objetivo") { DatePicker("", selection: $goal.targetDate, displayedComponents: .date).labelsHidden() }
                ActivityTagEditor(tags: $goal.tags, suggestions: suggestedTags)
                field("Notas") { TextEditor(text: $goal.notes).scrollContentBackground(.hidden).frame(height: 85) }
                ClosureEditor(isClosed: Binding(get: { goal.isClosed }, set: { goal.isDone = $0 }),
                              completedAt: $goal.completedAt, deadline: goal.targetDate, includesTime: false, noun: "Meta")
                HStack { Text("Hitos").font(.subheadline.bold()); Spacer(); Button { goal.milestones.append(.init(title: "", dueDate: goal.targetDate)) } label: { Label("Añadir hito", systemImage: "plus") } }
                ForEach($goal.milestones) { $milestone in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { TextField("Nombre del hito", text: $milestone.title); Spacer(); Button { goal.milestones.removeAll { $0.id == milestone.id } } label: { Image(systemName: "trash") }.buttonStyle(.plain) }
                        DatePicker("Fecha límite", selection: $milestone.dueDate, displayedComponents: .date)
                        TextField("Nota del hito", text: $milestone.notes)
                        ActivityTagEditor(tags: $milestone.tags, suggestions: suggestedTags)
                        ClosureEditor(isClosed: $milestone.isDone, completedAt: $milestone.completedAt,
                                      deadline: milestone.dueDate, includesTime: false, noun: "Hito")
                    }.padding(15).background(Palette.raised.opacity(0.45), in: RoundedRectangle(cornerRadius: 13))
                }
            }
        }
    }
}

private struct InlineCategoryCreator: View {
    let kind: MoneyKind
    let onCreated: (MoneyCategory) -> Void
    let onCancel: () -> Void
    @State private var name = ""
    @State private var emoji: String? = "✨"
    @State private var tint = "#BDA6FF"
    private let emojis = ["✨", "🏠", "🍽️", "🚗", "💊", "🎮", "🛍️", "💼", "💰", "💳", "📲", "🏋️", "📚", "☕️", "✈️", "🎁", "🐶", "⚡️"]
    private let colors = ["#BDA6FF", "#91DFC2", "#FFBD98", "#7FCBD7", "#F59EB7", "#E2CE83", "#A8C4FF", "#A9B6C9"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Nueva categoría de \(kind.rawValue.lowercased())", systemImage: "plus.circle.fill")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.lavender)
                Spacer()
                Button("Cancelar", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
            }

            HStack(spacing: 10) {
                CategoryBadge(category: .init(name: name, symbol: "circle.fill", tint: tint, kind: kind, emoji: emoji))
                TextField("Nombre de la categoría…", text: $name)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Palette.raised, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(emojis, id: \.self) { item in
                        Button { emoji = item } label: {
                            Text(item)
                                .font(.system(size: 16))
                                .frame(width: 32, height: 32)
                                .background(emoji == item ? Palette.lavender.opacity(0.28) : Palette.raised, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 9) {
                ForEach(colors, id: \.self) { hex in
                    Button { tint = hex } label: {
                        Circle().fill(Color(hex: hex)).frame(width: 20, height: 20)
                            .padding(2)
                            .overlay(Circle().stroke(tint == hex ? Palette.text : .clear, lineWidth: 1.5))
                    }.buttonStyle(.plain)
                }
                Spacer()
                Button {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    let created = MoneyCategory(name: trimmed, symbol: "circle.fill", tint: tint, kind: kind, emoji: emoji)
                    onCreated(created)
                } label: {
                    Label("Crear y elegir", systemImage: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.background)
                        .padding(.horizontal, 13).padding(.vertical, 8)
                        .background(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Palette.muted.opacity(0.35) : Palette.mint, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .background(Palette.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.lavender.opacity(0.45)))
    }
}

struct EntryEditor: View {
    @State private var entry: MoneyEntry
    @State private var isCreatingCategory = false
    let categories: [MoneyCategory]
    let debts: [MoneyDebt]
    let accounts: [MoneyAccount]
    let mainAccountName: String
    let availableBalance: Double
    let accountBalances: [UUID: Double]
    let currencyCode: String
    let onCreateCategory: ((MoneyCategory) -> Void)?
    let onSave: (MoneyEntry) -> Void
    init(entry: MoneyEntry, categories: [MoneyCategory], debts: [MoneyDebt], accounts: [MoneyAccount],
         mainAccountName: String = "T. Débito Santander",
         availableBalance: Double, accountBalances: [UUID: Double], currencyCode: String,
         onCreateCategory: ((MoneyCategory) -> Void)? = nil,
         onSave: @escaping (MoneyEntry) -> Void) {
        _entry = State(initialValue: entry)
        self.debts = debts
        self.categories = categories
        self.accounts = accounts
        self.mainAccountName = mainAccountName
        self.availableBalance = availableBalance
        self.accountBalances = accountBalances
        self.currencyCode = currencyCode
        self.onCreateCategory = onCreateCategory
        self.onSave = onSave
    }
    private var available: [MoneyCategory] { categories.filter { $0.kind == entry.kind && (!$0.isArchived || $0.id == entry.categoryID) } }
    var body: some View {
        EditorFrame(title: "Movimiento", canSave: !entry.title.trimmingCharacters(in: .whitespaces).isEmpty && entry.amount.isFinite && entry.amount > 0 && available.contains(where: { $0.id == entry.categoryID }) && (entry.debtAction == nil || debts.contains(where: { $0.id == entry.debtID })), save: { onSave(entry) }) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    ForEach(MoneyKind.allCases) { kind in
                        Button {
                            entry.kind = kind
                            entry.debtAction = nil
                            entry.debtID = nil
                            entry.categoryID = categories.first(where: { $0.kind == kind && !$0.isArchived })?.id ?? UUID()
                        } label: {
                            Label(kind.rawValue, systemImage: kind == .expense ? "arrow.up.right" : "arrow.down.left")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(entry.kind == kind ? Palette.background : Palette.muted)
                                .frame(maxWidth: .infinity).padding(.vertical, 11)
                                .background(entry.kind == kind ? (kind == .expense ? Palette.peach : Palette.mint) : Palette.raised,
                                            in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain)
                    }
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text("IMPORTE EN \(currencyCode)").font(.system(size: 10, weight: .bold)).tracking(1.1).foregroundStyle(Palette.muted)
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("$").font(.system(size: 27, weight: .bold, design: .rounded))
                        MoneyField(value: $entry.amount)
                            .textFieldStyle(.plain)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(entry.kind == .expense ? Palette.peach : Palette.mint)
                    Text(entry.debtAction == .charge ? "Este importe aumentará la deuda seleccionada." : entry.kind == .expense ? "Este importe saldrá del origen seleccionado." : "Este importe entrará al destino seleccionado.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                .padding(17).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.background, in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(Palette.line))
                field("Concepto") { TextField(entry.kind == .expense ? "¿En qué gastaste?" : "¿De dónde llegó?", text: $entry.title) }
                field("Fecha") { DatePicker("", selection: $entry.date, displayedComponents: .date).labelsHidden() }
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("CATEGORÍA").font(.system(size: 10, weight: .bold)).tracking(1.1).foregroundStyle(Palette.muted)
                        Spacer()
                        if onCreateCategory != nil {
                            Button {
                                withAnimation(.easeInOut(duration: 0.18)) { isCreatingCategory.toggle() }
                            } label: {
                                Label(isCreatingCategory ? "Ocultar" : "Nueva categoría", systemImage: isCreatingCategory ? "chevron.up" : "plus.circle.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Palette.lavender)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if isCreatingCategory, let onCreateCategory {
                        InlineCategoryCreator(
                            kind: entry.kind,
                            onCreated: { newCategory in
                                onCreateCategory(newCategory)
                                entry.categoryID = newCategory.id
                                isCreatingCategory = false
                            },
                            onCancel: { isCreatingCategory = false }
                        )
                    }
                    if available.isEmpty {
                        Text("Crea una categoría de \(entry.kind.rawValue.lowercased()) para guardar este movimiento.")
                            .font(.caption).foregroundStyle(Palette.peach)
                    } else {
                        LazyVGrid(columns: [.init(.adaptive(minimum: 130), spacing: 9)], spacing: 9) {
                            ForEach(available) { category in
                                Button {
                                    entry.categoryID = category.id
                                    if category.isDebtPayment == true || category.name.localizedCaseInsensitiveContains("deuda") {
                                        entry.debtAction = .payment
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        CategoryBadge(category: category)
                                        Text(category.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                        Spacer(minLength: 0)
                                    }
                                    .foregroundStyle(Palette.text)
                                    .padding(7).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Palette.raised.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(entry.categoryID == category.id ? Palette.lavender : Palette.line,
                                                                                     lineWidth: entry.categoryID == category.id ? 2 : 1))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                if entry.kind == .expense {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("FORMA DEL MOVIMIENTO").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(Palette.muted)
                        HStack(spacing: 8) {
                            paymentMode("Contado", action: nil)
                            paymentMode("Compra a crédito", action: .charge)
                            paymentMode("Abono a deuda", action: .payment)
                        }
                        if entry.debtAction != nil {
                            if debts.isEmpty {
                                Text("Crea primero una tarjeta o deuda en Cajas y deudas.").font(.caption).foregroundStyle(Palette.peach)
                            }
                            ForEach(debts) { debt in
                                Button { entry.debtID = debt.id } label: {
                                    HStack {
                                        Image(systemName: debt.kind.symbol)
                                        Text(debt.name)
                                        Spacer()
                                        Image(systemName: entry.debtID == debt.id ? "checkmark.circle.fill" : "circle")
                                    }.font(.system(size: 12, weight: .semibold)).padding(13)
                                        .foregroundStyle(entry.debtID == debt.id ? Palette.lavender : Palette.text)
                                        .background(Palette.raised, in: RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(.plain)
                            }
                            Text(entry.debtAction == .charge ? "Aumenta la deuda. No descuenta dinero de tus cajas ni del disponible." : "Descuenta del origen elegido y reduce la deuda. Se muestra como abono, separado de tus gastos.")
                                .font(.caption).foregroundStyle(Palette.muted)
                        }
                    }
                }
                if entry.debtAction != .charge {
                    MoneySourcePicker(title: entry.kind == .expense ? "¿DE DÓNDE SALE?" : "¿A DÓNDE ENTRA?",
                                      selection: $entry.accountID, accounts: accounts,
                                      mainAccountName: mainAccountName,
                                      availableBalance: availableBalance, accountBalances: accountBalances,
                                      currencyCode: currencyCode)
                }
                field("Notas") { TextEditor(text: $entry.notes).scrollContentBackground(.hidden).frame(height: 70) }
            }
        }
    }
    private func paymentMode(_ title: String, action: DebtAction?) -> some View {
        Button {
            entry.debtAction = action
            if action == nil { entry.debtID = nil }
            else if entry.debtID == nil { entry.debtID = debts.first?.id }
        } label: {
            Text(title).font(.system(size: 11, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                .foregroundStyle(entry.debtAction == action ? Palette.background : Palette.text)
                .background(entry.debtAction == action ? Palette.lavender : Palette.raised, in: RoundedRectangle(cornerRadius: 11))
        }.buttonStyle(.plain)
    }

}

private struct MoneySourcePicker: View {
    let title: String
    @Binding var selection: UUID?
    let accounts: [MoneyAccount]
    let mainAccountName: String
    let availableBalance: Double
    let accountBalances: [UUID: Double]
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 10, weight: .bold)).tracking(1.1).foregroundStyle(Palette.muted)
            sourceButton(name: mainAccountName, symbol: "creditcard.fill", balance: availableBalance, id: nil, color: Palette.lavender)
            ForEach(accounts) { account in
                sourceButton(name: account.name, symbol: account.symbol, balance: accountBalances[account.id] ?? account.openingBalance,
                             id: account.id, color: Palette.mint)
            }
        }
    }
    private func sourceButton(name: String, symbol: String, balance: Double, id: UUID?, color: Color) -> some View {
        Button { selection = id } label: {
            HStack(spacing: 11) {
                Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(color)
                    .frame(width: 36, height: 36)
                    .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                Text(name).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                Spacer()
                Text(balance.formatted(.currency(code: currencyCode)))
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
                Image(systemName: selection == id ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selection == id ? Palette.lavender : Palette.muted)
            }
            .padding(10)
            .background(Palette.raised.opacity(0.65), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(selection == id ? Palette.lavender : Palette.line))
        }.buttonStyle(.plain)
    }
}

struct TransferEditor: View {
    @State private var transfer: MoneyTransfer
    let accounts: [MoneyAccount]
    let mainAccountName: String
    let availableBalance: Double
    let accountBalances: [UUID: Double]
    let currencyCode: String
    let onSave: (MoneyTransfer) -> Void

    init(transfer: MoneyTransfer, accounts: [MoneyAccount], mainAccountName: String = "T. Débito Santander", availableBalance: Double,
         accountBalances: [UUID: Double], currencyCode: String,
         onSave: @escaping (MoneyTransfer) -> Void) {
        _transfer = State(initialValue: transfer)
        self.accounts = accounts
        self.mainAccountName = mainAccountName
        self.availableBalance = availableBalance
        self.accountBalances = accountBalances
        self.currencyCode = currencyCode
        self.onSave = onSave
    }
    var body: some View {
        EditorFrame(title: "Transferencia", canSave: transfer.amount.isFinite && transfer.amount > 0 && transfer.fromAccountID != transfer.toAccountID,
                    save: { onSave(transfer) }) {
            VStack(alignment: .leading, spacing: 19) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("IMPORTE EN \(currencyCode)").font(.system(size: 10, weight: .bold)).tracking(1.1).foregroundStyle(Palette.muted)
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("$").font(.system(size: 27, weight: .bold, design: .rounded))
                        MoneyField(value: $transfer.amount)
                            .textFieldStyle(.plain).font(.system(size: 30, weight: .bold, design: .rounded))
                    }.foregroundStyle(Palette.lavender)
                    Text("El patrimonio total no cambia al mover dinero entre tus espacios.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                .padding(17).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.background, in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(Palette.line))
                MoneySourcePicker(title: "DESDE", selection: $transfer.fromAccountID, accounts: accounts,
                                  mainAccountName: mainAccountName,
                                  availableBalance: availableBalance, accountBalances: accountBalances, currencyCode: currencyCode)
                Image(systemName: "arrow.down").foregroundStyle(Palette.lavender).frame(maxWidth: .infinity)
                MoneySourcePicker(title: "HACIA", selection: $transfer.toAccountID, accounts: accounts,
                                  mainAccountName: mainAccountName,
                                  availableBalance: availableBalance, accountBalances: accountBalances, currencyCode: currencyCode)
                if transfer.fromAccountID == transfer.toAccountID {
                    Text("Elige espacios diferentes para transferir.").font(.caption).foregroundStyle(Palette.peach)
                }
                field("Fecha") { DatePicker("", selection: $transfer.date, displayedComponents: .date).labelsHidden() }
                field("Nota opcional") { TextEditor(text: $transfer.notes).scrollContentBackground(.hidden).frame(height: 65) }
            }
        }
    }
}

struct AvailableBalanceEditor: View {
    @State private var mainAccountName: String
    @State private var mainBalance: Double
    @State private var cashBalance: Double
    let currencyCode: String
    let onSave: (String, Double, Double) -> Void

    init(mainAccountName: String, mainBalance: Double, cashBalance: Double, currencyCode: String,
         onSave: @escaping (String, Double, Double) -> Void) {
        _mainAccountName = State(initialValue: mainAccountName)
        _mainBalance = State(initialValue: mainBalance)
        _cashBalance = State(initialValue: cashBalance)
        self.currencyCode = currencyCode
        self.onSave = onSave
    }

    private var totalLiquid: Double { mainBalance + cashBalance }
    private var displayMainName: String {
        let trimmed = mainAccountName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "T. Débito Santander" : trimmed
    }

    var body: some View {
        EditorFrame(
            title: "Dinero disponible",
            canSave: mainBalance.isFinite && cashBalance.isFinite,
            save: { onSave(displayMainName, mainBalance, cashBalance) }
        ) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    IconBadge(symbol: "wallet.pass.fill", color: Palette.lavender)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("DISPONIBLE TOTAL (\(displayMainName.uppercased()) + EFECTIVO)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(Palette.muted)
                        Text(totalLiquid.formatted(.currency(code: currencyCode)))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Palette.mint)
                    }
                    Spacer()
                }
                .padding(16)
                .background(Palette.background, in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(Palette.mint.opacity(0.35)))

                Text("Tu dinero disponible suma automáticamente tu cuenta principal (\(displayMainName)) más tu caja de Efectivo. Puedes cambiarle el nombre a tu cuenta principal y ajustar ambos saldos conservando tu historial de movimientos.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)

                field("Nombre de tu cuenta principal") {
                    TextField("T. Débito Santander", text: $mainAccountName)
                        .font(.system(size: 14, weight: .semibold))
                }

                field("Saldo actual en \(displayMainName) (\(currencyCode))") {
                    MoneyField(value: $mainBalance)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                }

                field("Saldo actual en caja Efectivo (\(currencyCode))") {
                    MoneyField(value: $cashBalance)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                }
            }
        }
    }
}

struct CategoryEditor: View {
    @State private var category: MoneyCategory
    let onSave: (MoneyCategory) -> Void
    init(category: MoneyCategory, onSave: @escaping (MoneyCategory) -> Void) { _category = State(initialValue: category); self.onSave = onSave }
    private let emojiChoices = ["🏠", "🍽️", "🚗", "💊", "🎮", "🛍️", "💼", "💰", "🐶", "✈️", "📚", "🎨", "☕️", "🎁", "🧘", "⚡️", "🏋️", "🎵"]
    private let colors = ["#BDA6FF", "#91DFC2", "#FFBD98", "#7FCBD7", "#F59EB7", "#E2CE83", "#A8C4FF", "#A9B6C9"]
    var body: some View {
        EditorFrame(title: "Categoría", canSave: !category.name.trimmingCharacters(in: .whitespaces).isEmpty, save: { onSave(category) }) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    CategoryBadge(category: category)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(category.name.isEmpty ? "Tu nueva categoría" : category.name)
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                        Text(category.kind.rawValue).font(.caption).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                }.padding(14).background(Palette.background, in: RoundedRectangle(cornerRadius: 13))
                field("Nombre") { TextField("Nombre de categoría", text: $category.name) }
                Toggle("Usar para abonos a deudas", isOn: Binding(get: { category.isDebtPayment == true }, set: { category.isDebtPayment = $0 })).foregroundStyle(Palette.text)
                field("Tipo") { Picker("", selection: $category.kind) { ForEach(MoneyKind.allCases) { kind in Text(kind.rawValue).tag(kind) } }.labelsHidden() }
                VStack(alignment: .leading, spacing: 9) {
                    Text("ELIGE UN EMOJI").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.1).foregroundStyle(Palette.muted)
                    LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 9), spacing: 8) {
                        ForEach(emojiChoices, id: \.self) { emoji in
                            Button { category.emoji = emoji } label: {
                                Text(emoji).font(.system(size: 20)).frame(maxWidth: .infinity).frame(height: 37)
                                    .background(category.emoji == emoji ? Palette.lavender.opacity(0.25) : Palette.raised, in: RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain)
                        }
                    }
                    HStack(spacing: 10) {
                        Text("O escribe el tuyo").font(.caption).foregroundStyle(Palette.muted)
                        TextField("✨", text: Binding(get: { category.emoji ?? "" }, set: { category.emoji = $0.first.map(String.init) }))
                            .textFieldStyle(.plain).frame(width: 50).padding(8)
                            .background(Palette.raised, in: RoundedRectangle(cornerRadius: 9))
                        Button("Sin emoji") { category.emoji = nil }
                            .buttonStyle(.plain).font(.caption).foregroundStyle(Palette.lavender)
                    }
                }
                VStack(alignment: .leading, spacing: 9) {
                    Text("COLOR").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.1).foregroundStyle(Palette.muted)
                    HStack(spacing: 11) {
                        ForEach(colors, id: \.self) { color in
                            Button { category.tint = color } label: {
                                Circle().fill(Color(hex: color)).frame(width: 26, height: 26)
                                    .padding(3).overlay(Circle().stroke(category.tint == color ? Palette.text : .clear, lineWidth: 1.5))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                DisclosureGroup("Más opciones") {
                    VStack(alignment: .leading, spacing: 12) {
                        field("Color hexadecimal") { TextField("#BDA6FF", text: $category.tint) }
                        field("Icono SF Symbols (si no usas emoji)") { TextField("circle.fill", text: $category.symbol) }
                    }.padding(.top, 10)
                }.foregroundStyle(Palette.muted)
            }
        }
    }
}

struct AccountEditor: View {
    @State private var account: MoneyAccount
    @State private var desiredBalance: Double
    let currentBalance: Double
    let onSave: (MoneyAccount) -> Void
    init(account: MoneyAccount, currentBalance: Double, onSave: @escaping (MoneyAccount) -> Void) {
        _account = State(initialValue: account)
        _desiredBalance = State(initialValue: currentBalance)
        self.currentBalance = currentBalance
        self.onSave = onSave
    }
    var body: some View {
        EditorFrame(title: "Cuenta o caja de ahorro", canSave: !account.name.trimmingCharacters(in: .whitespaces).isEmpty && desiredBalance.isFinite, save: {
            var saved = account
            saved.openingBalance += desiredBalance - currentBalance
            onSave(saved)
        }) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    IconBadge(symbol: account.symbol, color: Palette.mint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(account.name.isEmpty ? "Nueva caja" : account.name)
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                        Text("Un espacio para separar tu dinero.").font(.caption).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                }.padding(14).background(Palette.background, in: RoundedRectangle(cornerRadius: 13))
                field("Nombre") { TextField("Por ejemplo: ahorro", text: $account.name) }
                field("Saldo actual (MXN)") { MoneyField(value: $desiredBalance) }
                VStack(alignment: .leading, spacing: 10) {
                    Text("ICONO").font(.system(size: 10, weight: .bold)).tracking(1.1).foregroundStyle(Palette.muted)
                    HStack(spacing: 9) {
                        ForEach(["building.columns.fill", "creditcard.fill", "banknote.fill", "tray.full.fill", "lock.shield.fill"], id: \.self) { symbol in
                            Button { account.symbol = symbol } label: {
                                Image(systemName: symbol).font(.system(size: 17))
                                    .foregroundStyle(account.symbol == symbol ? Palette.mint : Palette.muted)
                                    .frame(width: 46, height: 42)
                                    .background(Palette.raised, in: RoundedRectangle(cornerRadius: 11))
                                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(account.symbol == symbol ? Palette.mint : Palette.line))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Text("El saldo que escribas será el de hoy. Los movimientos ya registrados se conservarán y los próximos gastos directos se descontarán de esta caja.")
                    .font(.caption).foregroundStyle(Palette.muted)
            }
        }
    }
}

struct BudgetEditor: View {
    @State private var budget: BudgetPlan
    @State private var isCreatingCategory = false
    let categories: [MoneyCategory]
    let currencyCode: String
    let monthlyFixedTotal: Double
    let monthlyFixedRemaining: Double
    let simulatedIncome: Double?
    let onCreateCategory: ((MoneyCategory) -> Void)?
    let onSave: (BudgetPlan) -> Void

    init(
        budget: BudgetPlan,
        categories: [MoneyCategory],
        currencyCode: String = "MXN",
        monthlyFixedTotal: Double = 0,
        monthlyFixedRemaining: Double = 0,
        simulatedIncome: Double? = nil,
        onCreateCategory: ((MoneyCategory) -> Void)? = nil,
        onSave: @escaping (BudgetPlan) -> Void
    ) {
        _budget = State(initialValue: budget)
        self.categories = categories
        self.currencyCode = currencyCode
        self.monthlyFixedTotal = monthlyFixedTotal
        self.monthlyFixedRemaining = monthlyFixedRemaining
        self.simulatedIncome = simulatedIncome
        self.onCreateCategory = onCreateCategory
        self.onSave = onSave
    }

    private var expenseCategories: [MoneyCategory] {
        categories.filter { $0.kind == .expense && (!$0.isArchived || $0.id == budget.categoryID) }
    }

    private var selectedCategory: MoneyCategory? {
        expenseCategories.first { $0.id == budget.categoryID }
    }

    private func money(_ value: Double) -> String {
        value.formatted(.currency(code: currencyCode))
    }

    private var daysInPeriod: Int {
        switch budget.period {
        case .week: return 7
        case .month: return 30
        case .custom:
            let cal = Calendar.current
            let d = cal.dateComponents([.day], from: cal.startOfDay(for: budget.start), to: cal.startOfDay(for: budget.end)).day ?? 1
            return max(1, d + 1)
        }
    }

    private var dailyAllowance: Double {
        guard budget.limit > 0 else { return 0 }
        return budget.limit / Double(max(1, daysInPeriod))
    }

    private var secondaryAllowanceLabel: String {
        guard budget.limit > 0 else { return "Define un tope para ver tu ritmo diario." }
        switch budget.period {
        case .week:
            return "Equivale a \(money(budget.limit * 4)) / mes (4 semanas)"
        case .month:
            return "Equivale a \(money(budget.limit / 4)) / semana"
        case .custom:
            return "Periodo personalizado de \(daysInPeriod) \(daysInPeriod == 1 ? "día" : "días")"
        }
    }

    private let quickNames = ["Gastos de la semana", "Comida del mes", "Ocio y salidas", "Gastos variables", "Tope mensual"]

    var body: some View {
        EditorFrame(
            title: "Presupuesto",
            canSave: !budget.name.trimmingCharacters(in: .whitespaces).isEmpty && budget.limit.isFinite && budget.limit > 0 && (budget.period != .custom || budget.end >= budget.start),
            save: { onSave(budget) }
        ) {
            VStack(alignment: .leading, spacing: 20) {
                // Tarjeta principal de límite y ritmo diario/semanal
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        if let selectedCategory {
                            CategoryBadge(category: selectedCategory)
                        } else {
                            IconBadge(symbol: "chart.pie.fill", color: Palette.lavender)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(budget.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Nuevo presupuesto" : budget.name)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(Palette.text)
                                .lineLimit(1)
                            Text("\(budget.period.rawValue) · \(selectedCategory?.name ?? "Todos los gastos")")
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Text(budget.period.rawValue.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(Palette.lavender)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Palette.lavender.opacity(0.14), in: Capsule())
                    }

                    Divider().overlay(Palette.line)

                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("LÍMITE DEL PRESUPUESTO (\(currencyCode))")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .tracking(1.1).foregroundStyle(Palette.muted)
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("$").font(.system(size: 26, weight: .bold, design: .rounded))
                                MoneyField(value: $budget.limit)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 30, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(Palette.lavender)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Rectangle().fill(Palette.line).frame(width: 1, height: 54)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("RITMO POR DÍA")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .tracking(1.1).foregroundStyle(Palette.muted)
                            Text(money(dailyAllowance))
                                .font(.system(size: 23, weight: .bold, design: .rounded))
                                .foregroundStyle(Palette.mint)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text("por día (\(daysInPeriod)d)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Palette.muted)
                        }
                        .frame(width: 175, alignment: .leading)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.mint)
                        Text(secondaryAllowanceLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted)
                        Spacer()
                    }
                    .padding(10)
                    .background(Palette.surface.opacity(0.75), in: RoundedRectangle(cornerRadius: 11))

                    if monthlyFixedTotal > 0 || (simulatedIncome ?? 0) > 0 {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 12) {
                                Text("Pagos fijos del mes: \(money(monthlyFixedTotal))")
                                Text("·")
                                Text("Por pagar este mes: \(money(monthlyFixedRemaining))")
                                    .foregroundStyle(Palette.peach)
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Palette.muted)

                            if let sim = simulatedIncome, sim > 0 {
                                let freeTotal = max(0, sim - monthlyFixedTotal)
                                let freeRemaining = max(0, sim - monthlyFixedRemaining)
                                HStack(spacing: 8) {
                                    Text("De tu simulador (\(money(sim))) libre:")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Palette.muted)
                                    Button("Usar libre total (\(money(freeTotal)))") {
                                        budget.limit = budget.period == .week ? (freeTotal / 4.0) : freeTotal
                                    }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Palette.mint)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Palette.mint.opacity(0.14), in: Capsule())

                                    if freeRemaining != freeTotal {
                                        Button("Usar libre actual (\(money(freeRemaining)))") {
                                            budget.limit = budget.period == .week ? (freeRemaining / 4.0) : freeRemaining
                                        }
                                        .buttonStyle(.plain)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Palette.lavender)
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(Palette.lavender.opacity(0.14), in: Capsule())
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(18)
                .background(Palette.background, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.lavender.opacity(0.28)))

                // Nombre y sugerencias rápidas
                VStack(alignment: .leading, spacing: 9) {
                    field("Nombre del presupuesto") {
                        TextField("Ej. Gastos de la semana, Comida, Ocio…", text: $budget.name)
                    }
                    if budget.name.trimmingCharacters(in: .whitespaces).isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(quickNames, id: \.self) { suggestion in
                                    Button { budget.name = suggestion } label: {
                                        Text(suggestion)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(Palette.muted)
                                            .padding(.horizontal, 10).padding(.vertical, 5)
                                            .background(Palette.raised, in: Capsule())
                                            .overlay(Capsule().stroke(Palette.line))
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                // Periodo visual
                VStack(alignment: .leading, spacing: 9) {
                    Text("PERIODO")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.1).foregroundStyle(Palette.muted)
                    HStack(spacing: 9) {
                        ForEach(BudgetPeriod.allCases) { period in
                            let selected = budget.period == period
                            let icon = period == .week ? "calendar.badge.clock" : period == .month ? "calendar" : "calendar.day.timeline.left"
                            Button { budget.period = period } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                                    Text(period.rawValue).font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(selected ? Palette.background : Palette.text)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(selected ? Palette.lavender : Palette.raised, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Palette.lavender : Palette.line))
                            }.buttonStyle(.plain)
                        }
                    }

                    if budget.period == .custom {
                        HStack(spacing: 12) {
                            field("Desde") { DatePicker("", selection: $budget.start, displayedComponents: .date).labelsHidden() }
                            field("Hasta") { DatePicker("", selection: $budget.end, displayedComponents: .date).labelsHidden() }
                        }
                    } else {
                        Text("La semana empieza el día elegido en Ajustes.")
                            .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                }

                // Categoría visual + creación rápida
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("ALCANCE / CATEGORÍA")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.1).foregroundStyle(Palette.muted)
                        Spacer()
                        if onCreateCategory != nil {
                            Button {
                                withAnimation(.easeInOut(duration: 0.18)) { isCreatingCategory.toggle() }
                            } label: {
                                Label(isCreatingCategory ? "Ocultar" : "Nueva categoría", systemImage: isCreatingCategory ? "chevron.up" : "plus.circle.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Palette.lavender)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if isCreatingCategory, let onCreateCategory {
                        InlineCategoryCreator(
                            kind: .expense,
                            onCreated: { newCat in
                                onCreateCategory(newCat)
                                budget.categoryID = newCat.id
                                if budget.name.trimmingCharacters(in: .whitespaces).isEmpty {
                                    budget.name = newCat.name
                                }
                                isCreatingCategory = false
                            },
                            onCancel: { isCreatingCategory = false }
                        )
                    }

                    LazyVGrid(columns: [.init(.adaptive(minimum: 132), spacing: 8)], spacing: 8) {
                        Button { budget.categoryID = nil } label: {
                            HStack(spacing: 8) {
                                IconBadge(symbol: "square.grid.2x2.fill", color: Palette.lavender)
                                Text("Todos los gastos")
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(Palette.text)
                            .padding(7).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.raised.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(budget.categoryID == nil ? Palette.lavender : Palette.line,
                                                                               lineWidth: budget.categoryID == nil ? 2 : 1))
                        }.buttonStyle(.plain)

                        ForEach(expenseCategories) { category in
                            let selected = budget.categoryID == category.id
                            Button {
                                budget.categoryID = category.id
                                if budget.name.trimmingCharacters(in: .whitespaces).isEmpty {
                                    budget.name = category.name
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    CategoryBadge(category: category)
                                    Text(category.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .foregroundStyle(Palette.text)
                                .padding(7).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Palette.raised.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Palette.lavender : Palette.line,
                                                                                   lineWidth: selected ? 2 : 1))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .foregroundStyle(Palette.text)
        }
    }
}

private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(1.1).foregroundStyle(Palette.muted)
        content()
            .textFieldStyle(.plain)
            .datePickerStyle(.compact)
            .pickerStyle(.menu)
            .tint(Palette.lavender)
            .padding(.horizontal, 11).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Palette.line))
    }
}


struct DebtEditor: View {
    @State private var debt: MoneyDebt
    @State private var desiredBalance: Double
    @State private var hasLimit: Bool
    @State private var limit: Double
    @State private var hasDate: Bool
    @State private var paymentDate: Date
    let currentBalance: Double
    let onSave: (MoneyDebt) -> Void
    init(debt: MoneyDebt, currentBalance: Double, onSave: @escaping (MoneyDebt) -> Void) {
        _debt = State(initialValue: debt)
        _desiredBalance = State(initialValue: currentBalance)
        _hasLimit = State(initialValue: debt.creditLimit != nil)
        _limit = State(initialValue: debt.creditLimit ?? 0)
        _hasDate = State(initialValue: debt.paymentDate != nil)
        _paymentDate = State(initialValue: debt.paymentDate ?? .now)
        self.currentBalance = currentBalance; self.onSave = onSave
    }
    var body: some View {
        EditorFrame(title: "Deuda", canSave: !debt.name.trimmingCharacters(in: .whitespaces).isEmpty && desiredBalance.isFinite && (!hasLimit || (limit.isFinite && limit > 0)), save: {
            var result = debt
            result.openingBalance += desiredBalance - currentBalance
            result.creditLimit = hasLimit && debt.kind == .creditCard ? limit : nil
            result.paymentDate = hasDate ? paymentDate : nil
            onSave(result)
        }) {
            VStack(alignment: .leading, spacing: 20) {
                IconBadge(symbol: debt.kind.symbol, color: Palette.peach)
                field("Nombre") { TextField("Por ejemplo: TDC Nu, préstamo auto", text: $debt.name) }
                field("Tipo") { Picker("", selection: $debt.kind) { ForEach(DebtKind.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden() }
                field("Deuda actual (MXN)") { MoneyField(value: $desiredBalance) }
                Text("Indica lo que debes hoy. Puedes ajustar este saldo conservando el historial; las nuevas compras y abonos se registran como movimientos.").font(.caption).foregroundStyle(Palette.muted)
                if debt.kind == .creditCard {
                    Toggle("Definir límite de crédito", isOn: $hasLimit)
                    if hasLimit { field("Límite (MXN)") { MoneyField(value: $limit) } }
                }
                Toggle("Próxima fecha de pago", isOn: $hasDate)
                if hasDate { field("Fecha límite") { DatePicker("", selection: $paymentDate, displayedComponents: .date).labelsHidden() } }
                field("Notas") { TextEditor(text: $debt.notes).scrollContentBackground(.hidden).frame(height: 70) }
            }.foregroundStyle(Palette.text)
        }
    }
}

struct FixedPaymentEditor: View {
    @State private var payment: FixedPayment
    @State private var useFullCycle: Bool
    @State private var isCreatingCategory = false
    private let originalDue: Date
    private let originalCycleStart: Date?
    let categories: [MoneyCategory]
    let suggestedTags: [String]
    let currencyCode: String
    let onCreateCategory: ((MoneyCategory) -> Void)?
    let onSave: (FixedPayment) -> Void

    init(
        payment: FixedPayment,
        categories: [MoneyCategory],
        suggestedTags: [String] = [],
        currencyCode: String = "MXN",
        onCreateCategory: ((MoneyCategory) -> Void)? = nil,
        onSave: @escaping (FixedPayment) -> Void
    ) {
        _payment = State(initialValue: payment)
        self.originalDue = payment.nextDue
        self.originalCycleStart = payment.cycleStart
        let savedMonths = FinanceMath.savingMonths(for: payment)
        let fromNowMonths = max(1, FinanceMath.monthDistance(from: .now, to: payment.nextDue))
        if let std = payment.frequency.standardMonths, std > 1, savedMonths == std, fromNowMonths != std {
            _useFullCycle = State(initialValue: true)
        } else {
            _useFullCycle = State(initialValue: false)
        }
        self.categories = categories
        self.suggestedTags = suggestedTags
        self.currencyCode = currencyCode
        self.onCreateCategory = onCreateCategory
        self.onSave = onSave
    }

    private var expenseCategories: [MoneyCategory] {
        categories.filter { $0.kind == .expense && (!$0.isArchived || $0.id == payment.categoryID) }
    }

    private var selectedCategory: MoneyCategory? {
        expenseCategories.first { $0.id == payment.categoryID }
    }

    private var effectivePayment: FixedPayment {
        var draft = payment
        if draft.frequency.isProratedByMonths {
            if useFullCycle, let std = draft.frequency.standardMonths, std > 1 {
                draft.cycleStart = Calendar.current.date(byAdding: .month, value: -std, to: draft.nextDue) ?? .now
            } else if !Calendar.current.isDate(draft.nextDue, inSameDayAs: originalDue) {
                draft.cycleStart = .now
            } else {
                draft.cycleStart = originalCycleStart ?? .now
            }
        } else {
            draft.cycleStart = .now
        }
        return draft
    }

    private var monthlyImpact: Double {
        var preview = effectivePayment
        preview.isActive = true
        return FinanceMath.monthlyEquivalent(for: preview)
    }

    private var monthsCount: Int {
        FinanceMath.savingMonths(for: effectivePayment)
    }

    private var monthsFromToday: Int {
        max(1, FinanceMath.monthDistance(from: .now, to: payment.nextDue))
    }

    private func money(_ value: Double) -> String {
        value.formatted(.currency(code: currencyCode))
    }

    private var impactExplanation: String {
        guard payment.amount > 0 else {
            return "Escribe el importe y elige cada cuánto se cobra para calcular tu apartado mensual."
        }
        if !payment.isActive {
            return "Está pausado: no se sumará al gasto fijo mensual hasta que lo actives."
        }
        switch payment.frequency {
        case .weekly:
            return "Cobro semanal × 4 semanas = \(money(monthlyImpact)) al mes."
        case .biweekly:
            return "Cobro quincenal × 2 quincenas = \(money(monthlyImpact)) al mes."
        case .monthly:
            return "Cargo mensual directo que se suma íntegro a tu presupuesto fijo."
        case .bimonthly, .quarterly, .semiannual, .yearly:
            let dueLabel = payment.nextDue.formatted(.dateTime.month(.abbreviated).year())
            var text = "Dividido entre \(monthsCount) \(monthsCount == 1 ? "mes" : "meses") para reunir \(money(payment.amount)) en \(dueLabel)."
            if let std = payment.frequency.standardMonths, let nextMonthly = FinanceMath.nextCycleMonthlyEquivalent(for: effectivePayment), monthsCount != std {
                text += " Al avanzar al siguiente periodo (\(std) meses) será de \(money(nextMonthly))/mes."
            }
            return text
        case .once:
            let dueLabel = payment.nextDue.formatted(.dateTime.month(.abbreviated).year())
            return "Dividido entre \(monthsCount) \(monthsCount == 1 ? "mes" : "meses") para tener \(money(payment.amount)) listo en \(dueLabel)."
        }
    }

    private let quickSuggestions = ["Netflix", "Spotify", "iCloud+", "Internet", "Luz", "Gimnasio", "Seguro auto", "Mantenimiento"]

    var body: some View {
        EditorFrame(
            title: "Pago fijo",
            canSave: !payment.name.trimmingCharacters(in: .whitespaces).isEmpty && payment.amount.isFinite && payment.amount > 0,
            save: { onSave(effectivePayment) }
        ) {
            VStack(alignment: .leading, spacing: 20) {
                // Tarjeta principal de importe e impacto mensual
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        if let selectedCategory {
                            CategoryBadge(category: selectedCategory)
                        } else {
                            IconBadge(symbol: payment.frequency.symbol, color: Palette.lavender)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(payment.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Nuevo compromiso fijo" : payment.name)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(Palette.text)
                                .lineLimit(1)
                            Text("\(payment.frequency.rawValue) · Próximo: \(payment.nextDue.formatted(date: .abbreviated, time: .omitted))")
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Text(payment.isActive ? "ACTIVO" : "PAUSADO")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(payment.isActive ? Palette.mint : Palette.muted)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background((payment.isActive ? Palette.mint : Palette.muted).opacity(0.14), in: Capsule())
                    }

                    Divider().overlay(Palette.line)

                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("IMPORTE DEL COBRO (\(currencyCode))")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .tracking(1.1).foregroundStyle(Palette.muted)
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("$").font(.system(size: 26, weight: .bold, design: .rounded))
                                MoneyField(value: $payment.amount)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 30, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(Palette.lavender)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Rectangle().fill(Palette.line).frame(width: 1, height: 54)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("APARTAR CADA MES")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .tracking(1.1).foregroundStyle(Palette.muted)
                            Text(payment.isActive ? money(monthlyImpact) : money(0))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(payment.isActive ? Palette.mint : Palette.muted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(payment.frequency == .monthly ? "1 cobro por mes" :
                                    payment.frequency == .weekly ? "4 semanas / mes" :
                                    payment.frequency == .biweekly ? "2 quincenas / mes" :
                                    "En \(monthsCount) \(monthsCount == 1 ? "mes" : "meses")")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Palette.muted)
                        }
                        .frame(width: 185, alignment: .leading)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.mint)
                        Text(impactExplanation)
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.surface.opacity(0.75), in: RoundedRectangle(cornerRadius: 11))
                }
                .padding(18)
                .background(Palette.background, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.lavender.opacity(0.28)))

                // Nombre / Concepto
                VStack(alignment: .leading, spacing: 9) {
                    field("Servicio o concepto") {
                        TextField("Ej. HBO, Gimnasio, Mantenimiento anual…", text: $payment.name)
                    }
                    if payment.name.trimmingCharacters(in: .whitespaces).isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(quickSuggestions, id: \.self) { item in
                                    Button { payment.name = item } label: {
                                        Text(item)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(Palette.muted)
                                            .padding(.horizontal, 10).padding(.vertical, 5)
                                            .background(Palette.raised, in: Capsule())
                                            .overlay(Capsule().stroke(Palette.line))
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                // Etiqueta principal: Gasto Personal vs En Pareja + Etiquetas adicionales
                VStack(alignment: .leading, spacing: 10) {
                    Text("TIPO DE GASTO (APARTADO PERSONAL O EN PAREJA)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.1).foregroundStyle(Palette.muted)
                    HStack(spacing: 10) {
                        ForEach(FixedPaymentScope.allCases) { scopeItem in
                            let isSelected = payment.effectiveScope == scopeItem
                            let tint = scopeItem == .couple ? Palette.peach : Palette.lavender
                            Button {
                                payment.scope = scopeItem
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: scopeItem.symbol)
                                        .font(.system(size: 13, weight: .semibold))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(scopeItem == .couple ? "Gasto en pareja" : "Gasto personal")
                                            .font(.system(size: 12, weight: .bold))
                                        Text(scopeItem == .couple ? "Suma a tu apartado de pareja" : "Suma a tu apartado personal")
                                            .font(.system(size: 10))
                                            .opacity(0.85)
                                    }
                                    Spacer()
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 14))
                                }
                                .foregroundStyle(isSelected ? Palette.background : Palette.text)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(isSelected ? tint : Palette.raised, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? tint : Palette.line))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                ActivityTagEditor(
                    tags: $payment.tags,
                    suggestions: Array(Set(["Casa", "Suscripción", "Salud", "Auto", "Servicios"] + suggestedTags)).sorted()
                )

                // Frecuencia visual en cuadrícula
                VStack(alignment: .leading, spacing: 9) {
                    Text("FRECUENCIA DE COBRO")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.1).foregroundStyle(Palette.muted)
                    LazyVGrid(columns: Array(repeating: .init(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(PaymentFrequency.allCases) { freq in
                            let isSelected = payment.frequency == freq
                            Button {
                                payment.frequency = freq
                                if !freq.isProratedByMonths { useFullCycle = false }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: freq.symbol)
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(freq.rawValue)
                                        .font(.system(size: 11, weight: .semibold))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(isSelected ? Palette.background : Palette.text)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10).padding(.horizontal, 6)
                                .background(isSelected ? Palette.lavender : Palette.raised, in: RoundedRectangle(cornerRadius: 11))
                                .overlay(RoundedRectangle(cornerRadius: 11).stroke(isSelected ? Palette.lavender : Palette.line))
                            }.buttonStyle(.plain)
                        }
                    }
                }

                // Próximo vencimiento y estado activo
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PRÓXIMO COBRO")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.1).foregroundStyle(Palette.muted)
                        HStack {
                            Image(systemName: "calendar").foregroundStyle(Palette.lavender)
                            DatePicker("", selection: $payment.nextDue, displayedComponents: .date)
                                .labelsHidden()
                                .datePickerStyle(.compact)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Palette.raised, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line))
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("ESTADO")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.1).foregroundStyle(Palette.muted)
                        HStack(spacing: 10) {
                            Image(systemName: payment.isActive ? "checkmark.circle.fill" : "pause.circle.fill")
                                .foregroundStyle(payment.isActive ? Palette.mint : Palette.muted)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(payment.isActive ? "Pago activo" : "En pausa")
                                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text)
                                Text("Sumar al mes")
                                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
                            }
                            Spacer(minLength: 0)
                            Toggle("", isOn: $payment.isActive).labelsHidden()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Palette.raised, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line))
                    }
                    .frame(maxWidth: .infinity)
                }

                // Selector de modo de prorrateo cuando faltan menos/más meses que el ciclo completo
                if let std = payment.frequency.standardMonths, std > 1, monthsFromToday != std {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CÓMO CALCULAR EL APARTADO ACTUAL")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.1).foregroundStyle(Palette.muted)
                        HStack(spacing: 8) {
                            prorationOption(
                                title: "De hoy a la fecha (\(monthsFromToday) \(monthsFromToday == 1 ? "mes" : "meses"))",
                                subtitle: payment.amount > 0 ? "\(money(payment.amount / Double(monthsFromToday))) / mes" : "Reunir a tiempo",
                                selected: !useFullCycle
                            ) { useFullCycle = false }

                            prorationOption(
                                title: "Ciclo completo (\(std) meses)",
                                subtitle: payment.amount > 0 ? "\(money(payment.amount / Double(std))) / mes" : "Prorrateo estándar",
                                selected: useFullCycle
                            ) { useFullCycle = true }
                        }
                    }
                }

                // Categoría visual
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("CATEGORÍA")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.1).foregroundStyle(Palette.muted)
                        Spacer()
                        if onCreateCategory != nil {
                            Button {
                                withAnimation(.easeInOut(duration: 0.18)) { isCreatingCategory.toggle() }
                            } label: {
                                Label(isCreatingCategory ? "Ocultar" : "Nueva categoría", systemImage: isCreatingCategory ? "chevron.up" : "plus.circle.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Palette.lavender)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if isCreatingCategory, let onCreateCategory {
                        InlineCategoryCreator(
                            kind: .expense,
                            onCreated: { newCat in
                                onCreateCategory(newCat)
                                payment.categoryID = newCat.id
                                isCreatingCategory = false
                            },
                            onCancel: { isCreatingCategory = false }
                        )
                    }
                    LazyVGrid(columns: [.init(.adaptive(minimum: 132), spacing: 8)], spacing: 8) {
                        Button { payment.categoryID = nil } label: {
                            HStack(spacing: 8) {
                                IconBadge(symbol: "sparkles", color: Palette.muted)
                                Text("Al registrar")
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(Palette.text)
                            .padding(7).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.raised.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(payment.categoryID == nil ? Palette.lavender : Palette.line,
                                                                               lineWidth: payment.categoryID == nil ? 2 : 1))
                        }.buttonStyle(.plain)

                        ForEach(expenseCategories) { category in
                            let selected = payment.categoryID == category.id
                            Button { payment.categoryID = category.id } label: {
                                HStack(spacing: 8) {
                                    CategoryBadge(category: category)
                                    Text(category.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .foregroundStyle(Palette.text)
                                .padding(7).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Palette.raised.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Palette.lavender : Palette.line,
                                                                                   lineWidth: selected ? 2 : 1))
                            }.buttonStyle(.plain)
                        }
                    }
                }

                field("Notas opcionales") {
                    TextEditor(text: $payment.notes)
                        .scrollContentBackground(.hidden)
                        .frame(height: 64)
                }
            }
            .foregroundStyle(Palette.text)
        }
    }

    private func prorationOption(title: String, subtitle: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12))
                }
                Text(subtitle).font(.system(size: 10)).opacity(0.85)
            }
            .foregroundStyle(selected ? Palette.mint : Palette.text)
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Palette.mint.opacity(0.12) : Palette.raised, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Palette.mint : Palette.line))
        }.buttonStyle(.plain)
    }
}
