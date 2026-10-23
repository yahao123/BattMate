// Sources/BattMateWidget/BattMateWidget.swift
import SwiftUI
import WidgetKit

struct BattMateWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct BattMateTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> BattMateWidgetEntry {
        BattMateWidgetEntry(date: Date(), snapshot: .widgetPreview())
    }

    func getSnapshot(in context: Context, completion: @escaping (BattMateWidgetEntry) -> Void) {
        let entry = BattMateWidgetEntry(date: Date(), snapshot: WidgetSharedStore.loadFromSharedFile())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BattMateWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSharedStore.loadFromSharedFile()
        // 每分钟一个 entry，仅供「x 分钟前」文本推进；主 App 每 5 分钟触发一次重载。
        let entries = (0..<5).map { minute in
            BattMateWidgetEntry(date: now.addingTimeInterval(Double(minute) * 60), snapshot: snapshot)
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(300))))
    }
}

struct BattMateWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BattMateWidgetEntry

    var body: some View {
        BattMateWidgetView(snapshot: entry.snapshot,
                           size: family == .systemMedium ? .medium : .small,
                           now: entry.date)
            .containerBackground(for: .widget) { Color.clear }
    }
}

struct BattMateWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSharedStore.widgetKind,
                            provider: BattMateTimelineProvider()) { entry in
            BattMateWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("BattMate 服务器状态")
        .description("监控远端 Mac 的电量、CPU 与内存，每 5 分钟自动刷新。")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

@main
struct BattMateWidgetBundle: WidgetBundle {
    var body: some Widget {
        BattMateWidget()
    }
}
