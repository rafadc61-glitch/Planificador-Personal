import SwiftUI
import WidgetKit

private struct Snapshot: Codable {
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

private struct PlannerEntry: TimelineEntry {
    var date: Date
    var snapshot: Snapshot?
}

private struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> PlannerEntry { PlannerEntry(date: .now, snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (PlannerEntry) -> Void) { completion(read()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PlannerEntry>) -> Void) {
        completion(Timeline(entries: [read()], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
    private func read() -> PlannerEntry {
        let bytes = UserDefaults(suiteName: "group.com.planificador.personal")?.data(forKey: "snapshot")
        return PlannerEntry(date: .now, snapshot: bytes.flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) })
    }
}

private struct PlannerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PlannerEntry
    let focus: Focus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "square.stack.3d.up.fill").foregroundStyle(Color(red: 0.75, green: 0.65, blue: 1))
                Text(focus == .today ? "MI DÍA" : "PRÓXIMOS")
                    .font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.3)
                Spacer()
                Text(Date.now.formatted(.dateTime.day().month(.abbreviated))).font(.caption2).foregroundStyle(.secondary)
            }
            Text(entry.snapshot?.name ?? "Planificador Personal")
                .font(.system(size: family == .systemSmall ? 15 : 19, weight: .bold, design: .rounded)).lineLimit(1)
            let visible = items
            if visible.isEmpty {
                Spacer()
                Label("Todo en orden", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Color(red: 0.58, green: 0.87, blue: 0.76))
                Spacer()
            } else {
                ForEach(visible.indices, id: \.self) { index in
                    let item = visible[index]
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: item.type == "event" ? "calendar" : "circle")
                            .foregroundStyle(item.type == "event" ? Color(red: 1, green: 0.75, blue: 0.6) : Color(red: 0.75, green: 0.65, blue: 1))
                        Text(item.title).lineLimit(1)
                        Spacer(minLength: 2)
                        Text(item.date.formatted(.dateTime.hour().minute())).font(.caption2).foregroundStyle(.secondary)
                    }.font(.system(size: 11, weight: .medium))
                }
                Spacer(minLength: 0)
            }
            if family != .systemSmall {
                Text("\(entry.snapshot?.pendingCount ?? 0) tareas pendientes")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(family == .systemSmall ? 13 : 18)
        .containerBackground(Color(red: 0.08, green: 0.12, blue: 0.20).gradient, for: .widget)
        .foregroundStyle(.white)
    }

    private var items: [Snapshot.Item] {
        let all = entry.snapshot?.items ?? []
        let relevant = focus == .today ? all.filter { Calendar.current.isDateInToday($0.date) || ($0.type == "task" && $0.date < .now) } : all
        return Array(relevant.prefix(family == .systemSmall ? 2 : family == .systemMedium ? 4 : 7))
    }
}

private enum Focus { case today, upcoming }

private struct TodayWidget: Widget {
    let kind = "PlanificadorToday"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in PlannerWidgetView(entry: entry, focus: .today) }
            .configurationDisplayName("Mi día")
            .description("Tareas y compromisos de hoy.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct UpcomingWidget: Widget {
    let kind = "PlanificadorUpcoming"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in PlannerWidgetView(entry: entry, focus: .upcoming) }
            .configurationDisplayName("Próximos pasos")
            .description("Tus siguientes tareas y compromisos.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct PlanificadorWidgets: WidgetBundle {
    var body: some Widget { TodayWidget(); UpcomingWidget() }
}
