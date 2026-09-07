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
    /// 이번 주에 남은 수업이 없을 때 이어 보여줄 다음 주 표.
    var nextWeekTimetable: Timetable? = nil
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
                    WatchEntry(
                        date: date,
                        timetable: first.timetable,
                        nextWeekTimetable: first.nextWeekTimetable,
                        grade: first.grade,
                        klass: first.klass
                    )
                )
            }

            completion(Timeline(entries: entries, policy: .after(first.date.addingTimeInterval(30 * 60))))
        }
    }

    private func entry() async -> WatchEntry {
        let grade = AppSettings.grade
        let klass = AppSettings.klass
        let pair = try? await ComciService.weekPair(
            school: AppSettings.school.code, grade: grade, klass: klass
        )
        return WatchEntry(
            date: Date(),
            timetable: pair?.current,
            nextWeekTimetable: pair?.next,
            grade: grade,
            klass: klass
        )
    }
}

struct WatchComplicationView: View {
    @Environment(\.widgetFamily) private var family
    var entry: WatchEntry

    private var segment: DaySegment {
        entry.timetable?.segment(at: entry.date) ?? DaySegment(phase: .done)
    }

    private var focus: (period: Int, cell: TimetableCell)? {
        guard let timetable = entry.timetable,
              let day = Timetable.dayIndex(for: entry.date),
              let period = segment.period, segment.phase != .done else { return nil }
        return (period, timetable.cell(day: day, period: period))
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 0) {
                // 쉬는시간·점심에는 교시 대신 그걸 알려 주고, 과목은 곧 시작할 수업이다.
                Text(circularCaption)
                    .font(.caption2)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
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
                Text("\(entry.grade)-\(entry.klass) · \(rectangularCaption)")
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

    /// 원형은 자리가 좁아 "쉬는" / "점심" / "3교시"까지만.
    private var circularCaption: String {
        switch segment.phase {
        case .shortBreak: return "쉬는"
        case .lunch: return "점심"
        default: return focus.map { "\($0.period)" } ?? "-"
        }
    }

    private var rectangularCaption: String {
        guard let headline = segment.headline else { return "오늘 수업 끝" }
        return [headline, segment.nextLabel].compactMap { $0 }.joined(separator: " · ")
    }

    private var inlineText: String {
        guard let focus else { return "오늘 수업 끝" }
        let prefix = segment.isBreak ? (segment.phase == .lunch ? "점심, 다음" : "쉬는시간, 다음") : ""
        return "\(prefix.isEmpty ? "" : prefix + " ")\(focus.period)교시 \(focus.cell.displaySubject)"
    }

    private var nextDayText: String {
        guard let next = Timetable.upcoming(
            current: entry.timetable,
            next: entry.nextWeekTimetable,
            at: entry.date,
            afterPeriod: .max - 1,
            limit: 1
        ).first else {
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
