//
//  TimetableModels.swift
//  comsigan
//
//  컴시간 시간표 데이터 모델. 앱과 위젯이 함께 사용한다.
//

import Foundation

nonisolated enum ComciError: LocalizedError {
    case malformedResponse
    case classNotFound(grade: Int, klass: Int)

    var errorDescription: String? {
        switch self {
        case .malformedResponse:
            return "시간표 서버 응답을 해석하지 못했습니다."
        case let .classNotFound(grade, klass):
            return "\(grade)학년 \(klass)반 시간표가 없습니다."
        }
    }
}

/// 한 교시에 해당하는 수업.
nonisolated struct TimetableCell: Codable, Hashable, Sendable {
    var subject: String = ""
    var teacher: String = ""
    var room: String = ""
    /// 동시수업(그룹) 접두어. 예: "A_"
    var group: String = ""
    /// 원본 시간표(자료481)와 달라진 칸이면 true — 즉 변경/보강.
    var isChanged: Bool = false

    var isEmpty: Bool { subject.isEmpty }

    /// "A_체육" 형태의 표시용 과목명.
    var displaySubject: String { group + subject }

    static let empty = TimetableCell()
}

nonisolated struct PeriodTime: Codable, Hashable, Sendable {
    var period: Int
    var hour: Int
    var minute: Int

    var label: String { String(format: "%02d:%02d", hour, minute) }

    func start(on day: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }
}

/// 하루를 잘랐을 때 지금 서 있는 자리.
nonisolated enum DayPhase: String, Codable, Hashable, Sendable {
    /// 1교시 시작 전.
    case beforeClasses
    /// 수업 중.
    case lesson
    /// 수업과 수업 사이 쉬는시간.
    case shortBreak
    /// 점심시간(쉬는시간보다 뚜렷하게 긴 사이).
    case lunch
    /// 오늘 일과가 끝났거나 오늘은 수업이 없다.
    case done
}

/// 지금이 어느 구간인지와, 그 구간에서 가리킬 교시.
nonisolated struct DaySegment: Hashable, Sendable {
    var phase: DayPhase
    /// 수업 중이면 그 교시, 쉬는시간·점심·등교 전이면 이어질 교시.
    var period: Int?
    /// 방금 끝난 교시(쉬는시간·점심에만).
    var previousPeriod: Int?
    /// 이 구간이 끝나는 시각.
    var end: Date?

    var isBreak: Bool { phase == .shortBreak || phase == .lunch }

    /// 머리글에 쓰는 지금 상태. 예: "지금 3교시", "지금 쉬는시간", "점심시간", "다음 1교시"
    var headline: String? {
        switch phase {
        case .lesson: return period.map { "지금 \($0)교시" }
        case .shortBreak: return "지금 쉬는시간"
        case .lunch: return "점심시간"
        case .beforeClasses: return period.map { "다음 \($0)교시" }
        case .done: return nil
        }
    }

    /// 쉬는시간·점심에만 덧붙는 다음 교시 표기. 예: "다음 5교시"
    var nextLabel: String? {
        guard isBreak, let period else { return nil }
        return "다음 \(period)교시"
    }
}

nonisolated struct Timetable: Codable, Hashable, Sendable {
    var schoolName: String
    var grade: Int
    var klass: Int
    /// [요일][교시] — 요일 0 = 월요일, 교시 0 = 1교시.
    var days: [[TimetableCell]]
    /// 요일별 수업 교시 수.
    var periodCounts: [Int]
    var periodTimes: [PeriodTime]
    /// 학교 시간표가 마지막으로 갱신된 시각(자료244).
    var sourceUpdatedAt: String
    var fetchedAt: Date
    /// 이 표가 담고 있는 주의 월요일(시작일). 예: "2026-08-24"
    var weekStart: String = ""
    /// 서버가 준 기간 표기. 예: "26-08-17 ~ 26-08-22"
    var weekLabel: String = ""

    static let dayNames = ["월", "화", "수", "목", "금"]

    var maxPeriod: Int { max(periodCounts.max() ?? 0, 1) }

    /// 한 칸이라도 수업이 들어 있는지. 방학 주간처럼 표가 통째로 비는 경우가 있다.
    var hasAnyClass: Bool {
        days.contains { $0.contains { !$0.isEmpty } }
    }

    /// 요일(월=0)에 해당하는 날짜. 시작일을 모르면 nil.
    func date(forDay day: Int, calendar: Calendar = .current) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let monday = formatter.date(from: weekStart) else { return nil }
        return calendar.date(byAdding: .day, value: day, to: monday)
    }

    func cells(forDay day: Int) -> [TimetableCell] {
        guard days.indices.contains(day) else { return [] }
        let count = periodCounts.indices.contains(day) ? periodCounts[day] : days[day].count
        return Array(days[day].prefix(max(count, 0)))
    }

    func periodTime(_ period: Int) -> PeriodTime? {
        periodTimes.first { $0.period == period }
    }

    /// 주어진 시각 기준 요일 인덱스(월=0). 주말이면 nil.
    static func dayIndex(for date: Date, calendar: Calendar = .current) -> Int? {
        let weekday = calendar.component(.weekday, from: date) // 일=1
        let index = weekday - 2
        return (0...4).contains(index) ? index : nil
    }

    /// 수업 사이 쉬는시간(분).
    static let breakMinutes = 10
    /// 이보다 긴 사이는 점심시간으로 본다.
    static let lunchMinutes = 20
    /// 시작 시각만 알 때 쓰는 기본 수업 길이(분).
    static let defaultLessonMinutes = 50

    /// 수업 한 교시의 길이(분). 서버는 시작 시각만 주므로
    /// 연속한 교시의 시작 간격에서 쉬는시간을 뺀 값으로 본다.
    var lessonMinutes: Int {
        let sorted = periodTimes.sorted { $0.period < $1.period }
        let gaps = zip(sorted, sorted.dropFirst()).compactMap { previous, next -> Int? in
            guard next.period == previous.period + 1 else { return nil }
            let minutes = (next.hour * 60 + next.minute) - (previous.hour * 60 + previous.minute)
            return minutes > 0 ? minutes : nil
        }
        guard let shortest = gaps.min() else { return Self.defaultLessonMinutes }
        return min(max(shortest - Self.breakMinutes, 30), 70)
    }

    /// 그날 각 교시가 차지하는 시간대. 시각을 모르는 교시는 빠진다.
    func periodSpans(on date: Date, calendar: Calendar = .current) -> [(period: Int, start: Date, end: Date)] {
        guard let day = Self.dayIndex(for: date, calendar: calendar) else { return [] }
        let count = periodCounts.indices.contains(day) ? periodCounts[day] : 0
        guard count > 0 else { return [] }

        let length = TimeInterval(lessonMinutes * 60)
        return (1...count).compactMap { period in
            guard let start = periodTime(period)?.start(on: date, calendar: calendar) else { return nil }
            return (period, start, start.addingTimeInterval(length))
        }
    }

    /// 지금이 수업인지 쉬는시간인지 점심인지.
    func segment(at date: Date, calendar: Calendar = .current) -> DaySegment {
        let spans = periodSpans(on: date, calendar: calendar)
        guard let first = spans.first, let last = spans.last else { return DaySegment(phase: .done) }

        if date < first.start {
            return DaySegment(phase: .beforeClasses, period: first.period, end: first.start)
        }
        if date >= last.end { return DaySegment(phase: .done) }

        for (index, span) in spans.enumerated() {
            if date >= span.start && date < span.end {
                return DaySegment(phase: .lesson, period: span.period, end: span.end)
            }
            guard index + 1 < spans.count else { break }
            let next = spans[index + 1]
            guard date >= span.end && date < next.start else { continue }
            let gap = next.start.timeIntervalSince(span.end) / 60
            return DaySegment(
                phase: gap >= Double(Self.lunchMinutes) ? .lunch : .shortBreak,
                period: next.period,
                previousPeriod: span.period,
                end: next.start
            )
        }
        return DaySegment(phase: .done)
    }

    /// 지금 진행 중인 교시 번호(1-base). 쉬는시간·점심이면 nil.
    func currentPeriod(at date: Date, calendar: Calendar = .current) -> Int? {
        let segment = segment(at: date, calendar: calendar)
        return segment.phase == .lesson ? segment.period : nil
    }

    /// 지금(없으면 다음) 교시.
    func focusPeriod(at date: Date, calendar: Calendar = .current) -> Int? {
        currentPeriod(at: date, calendar: calendar) ?? nextPeriod(at: date, calendar: calendar)
    }

    /// 오늘 남은 수업 중 다음 교시 번호.
    func nextPeriod(at date: Date, calendar: Calendar = .current) -> Int? {
        guard let day = Self.dayIndex(for: date, calendar: calendar) else { return nil }
        let count = periodCounts.indices.contains(day) ? periodCounts[day] : 0
        guard count > 0 else { return nil }

        for period in 1...count {
            guard let start = periodTime(period)?.start(on: date, calendar: calendar) else { continue }
            if start > date { return period }
        }
        return nil
    }

    /// 이 표 안에서 앞으로 있을 수업. 금요일을 지나면 더 찾지 않는다 —
    /// 그 다음은 이 표가 아니라 다음 주 표에 들어 있다.
    func upcoming(at date: Date = Date(), afterPeriod: Int = 0, limit: Int = 3) -> [UpcomingClass] {
        guard let today = Self.dayIndex(for: date) else { return [] }
        return classes(fromDay: today, fromPeriod: afterPeriod + 1, today: today, weekOffset: 0, limit: limit)
    }

    /// 월요일 1교시부터 채운다. 아직 시작하지 않은 주의 표에 쓴다.
    func upcomingFromMonday(limit: Int = 3, weekOffset: Int = 1) -> [UpcomingClass] {
        classes(fromDay: 0, fromPeriod: 1, today: nil, weekOffset: weekOffset, limit: limit)
    }

    private func classes(
        fromDay: Int,
        fromPeriod: Int,
        today: Int?,
        weekOffset: Int,
        limit: Int
    ) -> [UpcomingClass] {
        guard limit > 0 else { return [] }
        var result: [UpcomingClass] = []

        for day in fromDay..<Self.dayNames.count {
            let from = max(day == fromDay ? fromPeriod : 1, 1)
            let count = periodCounts.indices.contains(day) ? periodCounts[day] : 0
            guard from <= count else { continue }

            for period in from...count {
                let value = cell(day: day, period: period)
                if value.isEmpty { continue }
                result.append(
                    UpcomingClass(
                        day: day,
                        period: period,
                        cell: value,
                        isToday: day == today,
                        weekOffset: weekOffset
                    )
                )
                if result.count >= limit { return result }
            }
        }
        return result
    }

    /// 이번 주 표와 다음 주 표를 이어 붙여 앞으로 있을 수업을 찾는다.
    /// 금요일 방과 후처럼 이번 주에 남은 수업이 없으면 다음 주 월요일부터 이어진다.
    static func upcoming(
        current: Timetable?,
        next: Timetable?,
        at date: Date = Date(),
        afterPeriod: Int,
        limit: Int
    ) -> [UpcomingClass] {
        guard let current else { return [] }
        // 주말에는 서버가 벌써 다음 주 표를 '이번 주'로 주기도 한다. 그때는 그 표의 월요일이 곧 다음 수업이다.
        if current.startsAfter(date) == true {
            return current.upcomingFromMonday(limit: limit)
        }

        var result = current.upcoming(at: date, afterPeriod: afterPeriod, limit: limit)
        if result.count < limit, let next, next.startsAfter(date) != false {
            result += next.upcomingFromMonday(limit: limit - result.count)
        }
        return result
    }

    /// 이 표가 담은 주가 아직 시작하지 않았는지. 시작일을 모르면 nil.
    func startsAfter(_ date: Date, calendar: Calendar = .current) -> Bool? {
        guard let monday = self.date(forDay: 0, calendar: calendar) else { return nil }
        return calendar.startOfDay(for: monday) > calendar.startOfDay(for: date)
    }

    func cell(day: Int, period: Int) -> TimetableCell {
        guard days.indices.contains(day), days[day].indices.contains(period - 1) else { return .empty }
        return days[day][period - 1]
    }
}

/// 위젯이 "다음 수업"을 보여줄 때 쓰는 항목.
nonisolated struct UpcomingClass: Codable, Hashable, Sendable, Identifiable {
    var day: Int
    var period: Int
    var cell: TimetableCell
    var isToday: Bool
    /// 0이면 이번 주, 1이면 다음 주.
    var weekOffset: Int = 0

    var id: String { "\(weekOffset)-\(day)-\(period)" }

    /// "7교시", "금 1교시", "다음 주 월 1교시".
    var label: String {
        if isToday { return "\(period)교시" }
        let dayLabel = "\(Timetable.dayNames[day]) \(period)교시"
        return weekOffset > 0 ? "다음 주 \(dayLabel)" : dayLabel
    }
}
