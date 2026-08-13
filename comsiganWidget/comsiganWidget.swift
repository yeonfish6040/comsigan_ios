//
//  comsiganWidget.swift
//  comsiganWidget
//
//  컴시간 시간표 macOS 위젯.
//

import AppIntents
import SwiftUI
import WidgetKit

struct TimetableEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationAppIntent
    let timetable: Timetable?
    let errorText: String?
}

struct TimetableProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TimetableEntry {
        TimetableEntry(date: Date(), configuration: ConfigurationAppIntent(), timetable: .placeholder, errorText: nil)
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> TimetableEntry {
        await entry(for: configuration, at: Date())
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<TimetableEntry> {
        let now = Date()
        let first = await entry(for: configuration, at: now)

        var entries = [first]
        // 오늘 남은 교시 시작 시각마다 다시 그려서 "지금 수업"이 저절로 넘어가게 한다.
        if let timetable = first.timetable, let day = Timetable.dayIndex(for: now) {
            let count = timetable.periodCounts.indices.contains(day) ? timetable.periodCounts[day] : 0
            for period in stride(from: 1, through: count, by: 1) {
                guard let start = timetable.periodTime(period)?.start(on: now), start > now else { continue }
                entries.append(TimetableEntry(
                    date: start,
                    configuration: configuration,
                    timetable: timetable,
                    errorText: first.errorText
                ))
            }
        }

        let refresh = now.addingTimeInterval(first.timetable == nil ? 10 * 60 : 30 * 60)
        return Timeline(entries: entries, policy: .after(refresh))
    }

    private func entry(for configuration: ConfigurationAppIntent, at date: Date) async -> TimetableEntry {
        do {
            let timetable = try await ComciService.timetable(
                school: AppSettings.school.code,
                grade: configuration.resolvedGrade,
                klass: configuration.resolvedClass
            )
            return TimetableEntry(date: date, configuration: configuration, timetable: timetable, errorText: nil)
        } catch {
            return TimetableEntry(date: date, configuration: configuration, timetable: nil, errorText: error.localizedDescription)
        }
    }
}

struct comsiganWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: TimetableProvider.Entry

    var body: some View {
        Group {
            if let timetable = entry.timetable {
                switch family {
                case .systemSmall: SmallView(timetable: timetable, now: entry.date)
                case .systemLarge, .systemExtraLarge: WeekView(timetable: timetable, now: entry.date)
                default: TodayView(timetable: timetable, now: entry.date)
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "wifi.exclamationmark")
                    Text(entry.errorText ?? "시간표를 불러오지 못했습니다.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Small: 지금/다음 수업

private struct SmallView: View {
    let timetable: Timetable
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HeaderLine(timetable: timetable, now: now)

            if let day = Timetable.dayIndex(for: now) {
                let current = timetable.currentPeriod(at: now)
                let next = timetable.nextPeriod(at: now)
                let focus = current ?? next

                if let focus {
                    let cell = timetable.cell(day: day, period: focus)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(current == nil ? "다음 \(focus)교시" : "지금 \(focus)교시")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(cell.isEmpty ? "수업 없음" : cell.displaySubject)
                            .font(.title3.bold())
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if !cell.teacher.isEmpty {
                            Text(cell.teacher + (cell.room.isEmpty ? "" : " · \(cell.room)"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    let upcoming = upcomingPeriods(after: focus, day: day)
                    if !upcoming.isEmpty {
                        Divider()
                        ForEach(upcoming, id: \.self) { period in
                            HStack(spacing: 4) {
                                Text("\(period)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 12, alignment: .trailing)
                                Text(timetable.cell(day: day, period: period).displaySubject)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                } else {
                    Text("오늘 수업 끝")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("오늘은 수업이 없습니다")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func upcomingPeriods(after period: Int, day: Int) -> [Int] {
        let count = timetable.periodCounts.indices.contains(day) ? timetable.periodCounts[day] : 0
        guard count > period else { return [] }
        return Array((period + 1)...count).filter { !timetable.cell(day: day, period: $0).isEmpty }.prefix(2).map { $0 }
    }
}

// MARK: - Medium: 오늘 전체

private struct TodayView: View {
    let timetable: Timetable
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HeaderLine(timetable: timetable, now: now)

            if let day = Timetable.dayIndex(for: now) {
                let count = timetable.periodCounts.indices.contains(day) ? timetable.periodCounts[day] : 0
                let current = timetable.currentPeriod(at: now)
                if count > 0 {
                    HStack(spacing: 4) {
                        ForEach(1...count, id: \.self) { period in
                            let cell = timetable.cell(day: day, period: period)
                            VStack(spacing: 2) {
                                Text("\(period)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Text(cell.isEmpty ? "—" : cell.displaySubject)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                Text(cell.teacher)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.vertical, 3)
                            .background {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(cell.isChanged && !cell.isEmpty ? Color.orange.opacity(0.3) : Color.primary.opacity(0.07))
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 7)
                                    .strokeBorder(.tint, lineWidth: period == current ? 2 : 0)
                            }
                        }
                    }
                } else {
                    Text("오늘 수업 없음").foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                Text("오늘은 수업이 없습니다").foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
}

// MARK: - Large: 주간 표

private struct WeekView: View {
    let timetable: Timetable
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HeaderLine(timetable: timetable, now: now)

            let today = Timetable.dayIndex(for: now)
            let current = timetable.currentPeriod(at: now)

            HStack(spacing: 4) {
                Text("")
                    .frame(width: 14)
                ForEach(0..<Timetable.dayNames.count, id: \.self) { day in
                    Text(Timetable.dayNames[day])
                        .font(.caption2.bold())
                        .foregroundStyle(day == today ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .frame(maxWidth: .infinity)
                }
            }

            ForEach(1...timetable.maxPeriod, id: \.self) { period in
                HStack(spacing: 4) {
                    Text("\(period)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                    ForEach(0..<Timetable.dayNames.count, id: \.self) { day in
                        let cell = timetable.cell(day: day, period: period)
                        Text(cell.isEmpty ? "" : cell.displaySubject)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(cell.isChanged && !cell.isEmpty ? Color.orange.opacity(0.3) : Color.primary.opacity(0.07))
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(.tint, lineWidth: day == today && period == current ? 2 : 0)
                            }
                    }
                }
            }
        }
    }
}

private struct HeaderLine: View {
    let timetable: Timetable
    let now: Date

    var body: some View {
        HStack(spacing: 4) {
            Text("\(timetable.grade)-\(timetable.klass)")
                .font(.caption.bold())
            if let day = Timetable.dayIndex(for: now) {
                Text(Timetable.dayNames[day] + "요일")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            // 서버가 학교명을 가려서 보내므로 검색해서 저장해 둔 이름을 쓴다.
            Text(AppSettings.school.name)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }
}

// MARK: - Widget

struct comsiganWidget: Widget {
    let kind: String = "comsiganWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: TimetableProvider()) { entry in
            comsiganWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("시간표")
        .description("컴시간 시간표를 보여줍니다.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

extension Timetable {
    /// 프리뷰/플레이스홀더용 더미 시간표.
    static var placeholder: Timetable {
        let subjects = ["국어", "수학", "영어", "체육", "과학", "역사", "미술"]
        let days = (0..<5).map { day in
            (0..<8).map { period in
                period < 7
                    ? TimetableCell(subject: subjects[(day + period) % subjects.count], teacher: "교사", isChanged: false)
                    : TimetableCell.empty
            }
        }
        return Timetable(
            schoolName: "컴시간중",
            grade: 1,
            klass: 1,
            days: days,
            periodCounts: [7, 7, 7, 6, 7],
            periodTimes: (1...8).map { PeriodTime(period: $0, hour: 8 + $0, minute: 0) },
            sourceUpdatedAt: "",
            fetchedAt: Date()
        )
    }
}

#Preview(as: .systemMedium) {
    comsiganWidget()
} timeline: {
    TimetableEntry(date: .now, configuration: ConfigurationAppIntent(), timetable: .placeholder, errorText: nil)
}
