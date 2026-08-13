//
//  WidgetLayouts.swift
//  comsigan
//
//  위젯 레이아웃. 데이터(WidgetRenderScope)만 받아 배경·머리글까지 직접 구성한다.
//  색은 반드시 scope.palette에서 읽어야 모든 테마가 모든 레이아웃에 적용된다.
//

import SwiftUI

/// 레이아웃에 넘어오는 것 전부.
nonisolated struct WidgetRenderScope {
    var palette: WidgetPalette
    /// 시간표. 아직 못 받아왔으면 nil.
    var timetable: Timetable?
    var school: School
    var grade: Int
    var klass: Int
    /// 시간표가 없을 때 대신 보여줄 설명.
    var status: String?
    var now: Date = Date()

    var today: Int? { Timetable.dayIndex(for: now) }
    var currentPeriod: Int? { timetable?.currentPeriod(at: now) }
    var nextPeriod: Int? { timetable?.nextPeriod(at: now) }
    /// 지금(없으면 다음) 교시.
    var focusPeriod: Int? { currentPeriod ?? nextPeriod }

    /// 오늘 일과가 끝났으면 오늘은 건너뛰고 다음 등교일에서 찾는다.
    func upcoming(limit: Int) -> [UpcomingClass] {
        timetable?.upcoming(at: now, afterPeriod: focusPeriod ?? 99, limit: limit) ?? []
    }
}

nonisolated protocol WidgetLayout: Sendable {
    var id: String { get }
    var name: String { get }
    var summary: String { get }

    @MainActor @ViewBuilder
    func body(_ scope: WidgetRenderScope) -> AnyView
}

nonisolated enum WidgetLayouts {
    static let all: [any WidgetLayout] = [
        NowNextLayout(),
        TodayRowLayout(),
        AgendaLayout(),
        WeekGridLayout(),
        FocusLayout(),
    ]

    static func byId(_ id: String?, fallback: any WidgetLayout) -> any WidgetLayout {
        all.first { $0.id == id } ?? fallback
    }
}

/// 위젯 자리 — macOS 위젯 크기와 1:1로 맞물린다.
nonisolated enum WidgetSlot: String, CaseIterable, Sendable {
    case small, medium, large

    var label: String {
        switch self {
        case .small: return "작은 위젯"
        case .medium: return "가로 위젯"
        case .large: return "큰 위젯"
        }
    }

    var defaultLayout: any WidgetLayout {
        switch self {
        case .small: return NowNextLayout()
        case .medium: return TodayRowLayout()
        case .large: return WeekGridLayout()
        }
    }
}

// MARK: - 공통 조각

/// 흔한 형태(머리글 + 본문). 쓰고 싶지 않은 레이아웃은 무시하고 직접 그려도 된다.
struct WidgetSurface<Content: View>: View {
    let scope: WidgetRenderScope
    var showsHeader: Bool = true
    @ViewBuilder var content: (Timetable) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsHeader { WidgetHeader(scope: scope) }
            if let timetable = scope.timetable {
                content(timetable)
            } else {
                WidgetMessage(scope: scope, text: scope.status ?? "시간표를 불러오지 못했습니다")
            }
        }
    }
}

struct WidgetHeader: View {
    let scope: WidgetRenderScope

    var body: some View {
        HStack(spacing: 4) {
            Text("\(scope.grade)-\(scope.klass)")
                .font(.caption.bold())
                .foregroundStyle(scope.palette.text)
            if let day = scope.today {
                Text("\(Timetable.dayNames[day])요일")
                    .font(.caption)
                    .foregroundStyle(scope.palette.textMuted)
            }
            Spacer(minLength: 0)
            Text(scope.school.name)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(scope.palette.textMuted)
        }
    }
}

struct WidgetMessage: View {
    let scope: WidgetRenderScope
    let text: String

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            Text(text)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(scope.palette.textMuted)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 지금 수업 + 다음 수업

nonisolated struct NowNextLayout: WidgetLayout {
    let id = "now"
    let name = "지금 수업"
    let summary = "지금(또는 다음) 수업을 크게, 이어지는 수업을 아래에"

    @MainActor
    func body(_ scope: WidgetRenderScope) -> AnyView {
        AnyView(
            WidgetSurface(scope: scope) { timetable in
                let palette = scope.palette
                let focus = scope.focusPeriod
                let cell = (scope.today != nil && focus != nil)
                    ? timetable.cell(day: scope.today!, period: focus!)
                    : nil

                VStack(alignment: .leading, spacing: 2) {
                    if let cell, let focus {
                        HStack(spacing: 4) {
                            Text(scope.currentPeriod == nil ? "다음 \(focus)교시" : "지금 \(focus)교시")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(palette.accent)
                            if let time = timetable.periodTime(focus) {
                                Text(time.label)
                                    .font(.caption2)
                                    .foregroundStyle(palette.textMuted)
                            }
                        }
                        Text(cell.isEmpty ? "수업 없음" : cell.displaySubject)
                            .font(.title2.bold())
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(cell.isChanged ? palette.changed : palette.text)
                        if !cell.teacher.isEmpty {
                            Text(cell.teacher)
                                .font(.caption)
                                .foregroundStyle(palette.textMuted)
                        }
                    } else {
                        Text("오늘 수업 끝")
                            .font(.headline)
                            .foregroundStyle(palette.text)
                    }

                    Spacer(minLength: 2)

                    let upcoming = scope.upcoming(limit: 2)
                    if !upcoming.isEmpty {
                        Text("다음")
                            .font(.system(size: 9))
                            .foregroundStyle(palette.textMuted)
                        ForEach(upcoming) { item in
                            HStack(spacing: 6) {
                                Text(item.label)
                                    .font(.system(size: 9))
                                    .foregroundStyle(palette.textMuted)
                                Text(item.cell.displaySubject)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                    .foregroundStyle(item.cell.isChanged ? palette.changed : palette.text)
                                Spacer(minLength: 0)
                                Text(item.cell.teacher)
                                    .font(.system(size: 9))
                                    .foregroundStyle(palette.textMuted)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(palette.cell, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        )
    }
}

// MARK: - 오늘 교시를 가로로

nonisolated struct TodayRowLayout: WidgetLayout {
    let id = "today"
    let name = "오늘 (가로)"
    let summary = "오늘 하루 교시를 나란히"

    @MainActor
    func body(_ scope: WidgetRenderScope) -> AnyView {
        AnyView(
            WidgetSurface(scope: scope) { timetable in
                let palette = scope.palette
                if let day = scope.today, timetable.periodCounts.indices.contains(day), timetable.periodCounts[day] > 0 {
                    let count = timetable.periodCounts[day]
                    HStack(spacing: 4) {
                        ForEach(1...count, id: \.self) { period in
                            let cell = timetable.cell(day: day, period: period)
                            let isNow = period == scope.currentPeriod
                            VStack(spacing: 2) {
                                Text("\(period)")
                                    .font(.system(size: 9))
                                    .foregroundStyle(isNow ? palette.textOnCurrent : palette.textMuted)
                                Text(cell.isEmpty ? "—" : cell.displaySubject)
                                    .font(.caption.bold())
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                    .foregroundStyle(
                                        cell.isChanged ? palette.changed : (isNow ? palette.textOnCurrent : palette.text)
                                    )
                                Text(cell.teacher)
                                    .font(.system(size: 9))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                    .foregroundStyle(isNow ? palette.textOnCurrent : palette.textMuted)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.vertical, 4)
                            .background(isNow ? palette.cellCurrent : palette.cell, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                } else {
                    WidgetMessage(scope: scope, text: scope.today == nil ? "오늘은 수업이 없습니다" : "오늘 수업 없음")
                }
            }
        )
    }
}

// MARK: - 오늘 교시를 세로 목록으로

nonisolated struct AgendaLayout: WidgetLayout {
    let id = "agenda"
    let name = "오늘 (목록)"
    let summary = "오늘 교시를 시각과 함께 세로로"

    @MainActor
    func body(_ scope: WidgetRenderScope) -> AnyView {
        AnyView(
            WidgetSurface(scope: scope) { timetable in
                let palette = scope.palette
                if let day = scope.today, timetable.periodCounts.indices.contains(day), timetable.periodCounts[day] > 0 {
                    let count = timetable.periodCounts[day]
                    VStack(spacing: 3) {
                        ForEach(1...count, id: \.self) { period in
                            let cell = timetable.cell(day: day, period: period)
                            let isNow = period == scope.currentPeriod
                            HStack(spacing: 8) {
                                Text("\(period)")
                                    .font(.caption.bold())
                                    .frame(width: 14)
                                    .foregroundStyle(isNow ? palette.textOnCurrent : palette.textMuted)
                                if let time = timetable.periodTime(period) {
                                    Text(time.label)
                                        .font(.system(size: 9))
                                        .foregroundStyle(isNow ? palette.textOnCurrent : palette.textMuted)
                                }
                                Text(cell.isEmpty ? "—" : cell.displaySubject)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                    .foregroundStyle(
                                        cell.isChanged ? palette.changed : (isNow ? palette.textOnCurrent : palette.text)
                                    )
                                Spacer(minLength: 0)
                                Text(cell.teacher)
                                    .font(.system(size: 9))
                                    .foregroundStyle(isNow ? palette.textOnCurrent : palette.textMuted)
                            }
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(isNow ? palette.cellCurrent : palette.cell, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                } else {
                    WidgetMessage(scope: scope, text: scope.today == nil ? "오늘은 수업이 없습니다" : "오늘 수업 없음")
                }
            }
        )
    }
}

// MARK: - 주간 표

nonisolated struct WeekGridLayout: WidgetLayout {
    let id = "week"
    let name = "주간 표"
    let summary = "월~금 전체 시간표"

    @MainActor
    func body(_ scope: WidgetRenderScope) -> AnyView {
        AnyView(
            WidgetSurface(scope: scope) { timetable in
                let palette = scope.palette
                VStack(spacing: 3) {
                    HStack(spacing: 3) {
                        Spacer().frame(width: 14)
                        ForEach(0..<Timetable.dayNames.count, id: \.self) { day in
                            Text(Timetable.dayNames[day])
                                .font(.system(size: 10, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .foregroundStyle(day == scope.today ? palette.accent : palette.textMuted)
                        }
                    }
                    ForEach(1...timetable.maxPeriod, id: \.self) { period in
                        HStack(spacing: 3) {
                            Text("\(period)")
                                .font(.system(size: 9))
                                .frame(width: 14)
                                .foregroundStyle(palette.textMuted)
                            ForEach(0..<Timetable.dayNames.count, id: \.self) { day in
                                let cell = timetable.cell(day: day, period: period)
                                let isNow = day == scope.today && period == scope.currentPeriod
                                VStack(spacing: 0) {
                                    Text(cell.isEmpty ? "" : cell.displaySubject)
                                        .font(.system(size: 10, weight: isNow ? .bold : .medium))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.6)
                                        .foregroundStyle(
                                            cell.isChanged ? palette.changed : (isNow ? palette.textOnCurrent : palette.text)
                                        )
                                    if !cell.teacher.isEmpty {
                                        Text(cell.teacher)
                                            .font(.system(size: 8))
                                            .lineLimit(1)
                                            .foregroundStyle(isNow ? palette.textOnCurrent : palette.textMuted)
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(
                                    isNow ? palette.cellCurrent : (day == scope.today ? palette.cellToday : palette.cell),
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                            }
                        }
                    }
                }
            }
        )
    }
}

// MARK: - 과목만 크게 (머리글 없이 직접 그리는 예)

nonisolated struct FocusLayout: WidgetLayout {
    let id = "focus"
    let name = "포커스"
    let summary = "머리글 없이 지금 수업만 큼직하게"

    @MainActor
    func body(_ scope: WidgetRenderScope) -> AnyView {
        let palette = scope.palette
        let focus = scope.focusPeriod
        let cell = (scope.timetable != nil && scope.today != nil && focus != nil)
            ? scope.timetable!.cell(day: scope.today!, period: focus!)
            : nil

        return AnyView(
            VStack(spacing: 2) {
                if let cell, let focus {
                    Text(scope.currentPeriod == nil ? "다음 \(focus)교시" : "\(focus)교시")
                        .font(.caption)
                        .foregroundStyle(palette.accent)
                    Text(cell.displaySubject.isEmpty ? "공강" : cell.displaySubject)
                        .font(.system(size: 34, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .foregroundStyle(cell.isChanged ? palette.changed : palette.text)
                    if !cell.teacher.isEmpty {
                        Text(cell.teacher)
                            .font(.callout)
                            .foregroundStyle(palette.textMuted)
                    }
                } else {
                    Text(scope.status ?? "수업 없음")
                        .font(.headline)
                        .foregroundStyle(palette.textMuted)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
    }
}
