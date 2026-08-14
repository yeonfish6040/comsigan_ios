//
//  ComsiganWatchWidget.swift
//  comsiganWatchWidget
//
//  워치 페이스 컴플리케이션 — 지금(또는 다음) 수업을 보여준다.
//

import SwiftUI
import WidgetKit

struct WatchEntry: TimelineEntry {
    let date: Date
    let timetable: Timetable?
    let grade: Int
    let klass: Int
}

struct WatchProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchEntry {
        WatchEntry(date: Date(), timetable: nil, grade: AppSettings.grade, klass: AppSettings.klass)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchEntry) -> Void) {
        Task { completion(await entry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchEntry>) -> Void) {
        Task {
            let first = await entry()

            // 30초 간격 엔트리를 미리 채워 두면 앱을 깨우지 않고도 "지금 수업"이 따라간다.
            // (교시 경계만 넣으면 그 사이 상태 변화가 반영되지 않는다.)
            var entries = [first]
            for step in 1...60 {
                let date = first.date.addingTimeInterval(Double(step) * 30)
                entries.append(
                    WatchEntry(date: date, timetable: first.timetable, grade: first.grade, klass: first.klass)
                )
            }

            completion(Timeline(entries: entries, policy: .after(first.date.addingTimeInterval(30 * 60))))
        }
    }

    private func entry() async -> WatchEntry {
        let grade = AppSettings.grade
        let klass = AppSettings.klass
        let timetable = try? await ComciService.timetable(
            school: AppSettings.school.code, grade: grade, klass: klass
        )
        return WatchEntry(date: Date(), timetable: timetable, grade: grade, klass: klass)
    }
}

struct WatchComplicationView: View {
    @Environment(\.widgetFamily) private var family
    var entry: WatchEntry

    private var focus: (period: Int, cell: TimetableCell, isNow: Bool)? {
        guard let timetable = entry.timetable,
              let day = Timetable.dayIndex(for: entry.date) else { return nil }
        let current = timetable.currentPeriod(at: entry.date)
        guard let period = current ?? timetable.nextPeriod(at: entry.date) else { return nil }
        return (period, timetable.cell(day: day, period: period), current != nil)
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 0) {
                Text(focus.map { "\($0.period)" } ?? "-")
                    .font(.caption2)
                Text(focus?.cell.displaySubject ?? "끝")
                    .font(.system(size: 13, weight: .bold))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            .containerBackground(.clear, for: .widget)

        case .accessoryInline:
            Text(inlineText)
                .containerBackground(.clear, for: .widget)

        default: // accessoryRectangular
            VStack(alignment: .leading, spacing: 1) {
                Text("\(entry.grade)-\(entry.klass) · \(focus.map { $0.isNow ? "지금 \($0.period)교시" : "다음 \($0.period)교시" } ?? "오늘 수업 끝")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(focus?.cell.displaySubject ?? nextDayText)
                    .font(.headline)
                    .lineLimit(1)
                if let teacher = focus?.cell.teacher, !teacher.isEmpty {
                    Text(teacher).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(.clear, for: .widget)
        }
    }

    private var inlineText: String {
        guard let focus else { return "오늘 수업 끝" }
        return "\(focus.period)교시 \(focus.cell.displaySubject)"
    }

    private var nextDayText: String {
        guard let next = entry.timetable?.upcoming(at: entry.date, afterPeriod: 99, limit: 1).first else {
            return "수업 없음"
        }
        return "\(next.label) \(next.cell.displaySubject)"
    }
}

struct ComsiganWatchWidget: Widget {
    let kind = "ComsiganWatchWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchProvider()) { entry in
            WatchComplicationView(entry: entry)
        }
        .configurationDisplayName("시간표")
        .description("지금(또는 다음) 수업을 보여줍니다.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct ComsiganWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        ComsiganWatchWidget()
    }
}
