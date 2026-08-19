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

    /// 지금 진행 중인 교시 번호(1-base). 수업 시간이 아니면 nil.
    func currentPeriod(at date: Date, calendar: Calendar = .current) -> Int? {
        guard let day = Self.dayIndex(for: date, calendar: calendar) else { return nil }
        let count = periodCounts.indices.contains(day) ? periodCounts[day] : 0
        guard count > 0 else { return nil }

        for period in 1...count {
            guard let time = periodTime(period), let start = time.start(on: date, calendar: calendar) else { continue }
            let end: Date
            if let next = periodTime(period + 1), period < count,
               let nextStart = next.start(on: date, calendar: calendar) {
                end = nextStart
            } else {
                end = start.addingTimeInterval(50 * 60)
            }
            if date >= start && date < end { return period }
        }
        return nil
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

    /// 앞으로 있을 수업. 오늘 남은 교시를 먼저 채우고, 없으면 다음 등교일로 넘어간다.
    func upcoming(at date: Date = Date(), afterPeriod: Int = 0, limit: Int = 3) -> [UpcomingClass] {
        let today = Self.dayIndex(for: date)
        let startDay = today ?? 0
        var result: [UpcomingClass] = []

        for offset in 0..<Self.dayNames.count {
            let day = (startDay + offset) % Self.dayNames.count
            let from = (offset == 0 && today != nil) ? afterPeriod + 1 : 1
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
                        isToday: offset == 0 && today != nil
                    )
                )
                if result.count >= limit { return result }
            }
        }
        return result
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

    var id: String { "\(day)-\(period)" }

    /// "7교시" 또는 "금 1교시".
    var label: String {
        isToday ? "\(period)교시" : "\(Timetable.dayNames[day]) \(period)교시"
    }
}
