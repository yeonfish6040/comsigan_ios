//
//  comsiganWidget.swift
//  comsiganWidget
//
//  컴시간 시간표 macOS 위젯. 크기별로 자리(slot)가 정해지고,
//  실제로 그릴 내용은 설정에서 고른 레이아웃과 테마가 정한다.
//

import AppIntents
import SwiftUI
import WidgetKit

struct TimetableEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationAppIntent
    let timetable: Timetable?
    let school: School
    let grade: Int
    let klass: Int
    let status: String?
}

struct TimetableProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TimetableEntry {
        TimetableEntry(
            date: Date(),
            configuration: ConfigurationAppIntent(),
            timetable: .placeholder,
            school: AppSettings.school,
            grade: 1,
            klass: 1,
            status: nil
        )
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> TimetableEntry {
        await entry(for: configuration, at: Date())
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<TimetableEntry> {
        let now = Date()
        let first = await entry(for: configuration, at: now)

        // 30초 간격 엔트리를 미리 채워 두면 프로세스를 깨우지 않고도 "지금 수업" 표시가 따라간다.
        var entries = [first]
        for step in 1...60 {
            let date = now.addingTimeInterval(Double(step) * 30)
            entries.append(
                TimetableEntry(
                    date: date,
                    configuration: configuration,
                    timetable: first.timetable,
                    school: first.school,
                    grade: first.grade,
                    klass: first.klass,
                    status: first.status
                )
            )
        }

        let refresh = now.addingTimeInterval(first.timetable == nil ? 10 * 60 : 30 * 60)
        return Timeline(entries: entries, policy: .after(refresh))
    }

    private func entry(for configuration: ConfigurationAppIntent, at date: Date) async -> TimetableEntry {
        let school = AppSettings.school
        let grade = configuration.resolvedGrade
        let klass = configuration.resolvedClass

        let timetable = try? await ComciService.timetable(school: school.code, grade: grade, klass: klass)
        return TimetableEntry(
            date: date,
            configuration: configuration,
            timetable: timetable,
            school: school,
            grade: grade,
            klass: klass,
            status: timetable == nil ? "시간표를 불러오지 못했습니다" : nil
        )
    }
}

struct comsiganWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    var entry: TimetableProvider.Entry

    private var slot: WidgetSlot {
        switch family {
        case .systemSmall: return .small
        case .systemLarge, .systemExtraLarge: return .large
        default: return .medium
        }
    }

    private var theme: any WidgetTheme { WidgetThemes.byId(AppSettings.widgetThemeId) }

    var body: some View {
        let palette = theme.palette(dark: colorScheme == .dark)
        let layout = WidgetLayouts.byId(
            AppSettings.widgetLayoutId(slot: slot.rawValue),
            fallback: slot.defaultLayout
        )
        let scope = WidgetRenderScope(
            palette: palette,
            timetable: entry.timetable,
            school: entry.school,
            grade: entry.grade,
            klass: entry.klass,
            status: entry.status,
            now: entry.date
        )

        layout.body(scope)
            // 투명 테마는 배경을 비운다.
            .containerBackground(for: .widget) {
                if theme.isTranslucent {
                    Color.clear
                } else {
                    palette.background
                }
            }
    }
}

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
    TimetableEntry(
        date: .now,
        configuration: ConfigurationAppIntent(),
        timetable: .placeholder,
        school: AppSettings.defaultSchool,
        grade: 1,
        klass: 1,
        status: nil
    )
}
