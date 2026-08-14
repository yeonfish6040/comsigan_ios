//
//  WatchTimetableView.swift
//  comsiganWatch
//
//  워치는 화면이 좁아 주간 표 대신 오늘 교시와 지금/다음 수업을 보여준다.
//

import SwiftUI
import WidgetKit

struct WatchTimetableView: View {
    @State private var timetable: Timetable?
    @State private var errorText: String?
    @State private var isLoading = false
    @State private var now = Date()

    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            List {
                if let timetable {
                    nowSection(timetable)
                    todaySection(timetable)
                } else if isLoading {
                    ProgressView()
                } else {
                    Text(errorText ?? "시간표를 불러오지 못했습니다")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("\(AppSettings.grade)-\(AppSettings.klass)")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await load(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .task { await load() }
        .onReceive(ticker) { now = $0 }
        .onReceive(NotificationCenter.default.publisher(for: .watchSettingsChanged)) { _ in
            Task { await load(force: true) }
        }
    }

    @ViewBuilder
    private func nowSection(_ timetable: Timetable) -> some View {
        let day = Timetable.dayIndex(for: now)
        let current = timetable.currentPeriod(at: now)
        let focus = current ?? timetable.nextPeriod(at: now)

        Section {
            if let day, let focus {
                let cell = timetable.cell(day: day, period: focus)
                VStack(alignment: .leading, spacing: 2) {
                    Text(current == nil ? "다음 \(focus)교시" : "지금 \(focus)교시")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text(cell.isEmpty ? "수업 없음" : cell.displaySubject)
                        .font(.title3.bold())
                    if !cell.teacher.isEmpty {
                        Text(cell.teacher).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("오늘 수업 끝").font(.headline)
                    if let next = timetable.upcoming(at: now, afterPeriod: 99, limit: 1).first {
                        Text("\(next.label) \(next.cell.displaySubject)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func todaySection(_ timetable: Timetable) -> some View {
        if let day = Timetable.dayIndex(for: now), timetable.periodCounts.indices.contains(day) {
            let count = timetable.periodCounts[day]
            if count > 0 {
                Section("오늘") {
                    ForEach(1...count, id: \.self) { period in
                        let cell = timetable.cell(day: day, period: period)
                        HStack(spacing: 6) {
                            Text("\(period)")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                                .frame(width: 14)
                            if let time = timetable.periodTime(period) {
                                Text(time.label).font(.caption2).foregroundStyle(.secondary)
                            }
                            Text(cell.isEmpty ? "—" : cell.displaySubject)
                                .font(.caption)
                                .foregroundStyle(cell.isChanged ? .orange : .primary)
                            Spacer(minLength: 0)
                        }
                        .listRowBackground(
                            period == timetable.currentPeriod(at: now)
                                ? Color.accentColor.opacity(0.25)
                                : Color.clear
                        )
                    }
                }
            }
        }
    }

    private func load(force: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        do {
            timetable = try await ComciService.timetable(
                school: AppSettings.school.code,
                grade: AppSettings.grade,
                klass: AppSettings.klass,
                forceRefresh: force
            )
            errorText = nil
            // 새로 받은 시간표를 컴플리케이션에도 반영한다.
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
