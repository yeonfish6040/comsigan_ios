//
//  ContentView.swift
//  comsigan
//
//  Created by Yeonjun Lee on 8/13/26.
//

import Combine
import SwiftUI
import WidgetKit

struct ContentView: View {
    // App Group에 저장해 위젯이 같은 값을 읽는다.
    @AppStorage(AppSettings.Key.grade, store: AppSettings.defaults) private var grade = 1
    @AppStorage(AppSettings.Key.klass, store: AppSettings.defaults) private var klass = 1
    @AppStorage(AppSettings.Key.schoolCode, store: AppSettings.defaults)
    private var schoolCode = AppSettings.defaultSchool.code
    @AppStorage(AppSettings.Key.schoolName, store: AppSettings.defaults)
    private var schoolName = AppSettings.defaultSchool.name

    @State private var isSearchingSchool = false
    @State private var timetable: Timetable?
    @State private var classCounts: [Int] = []
    @State private var errorText: String?
    @State private var isLoading = false
    @State private var now = Date()

    private let ticker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
            if let timetable {
                WeekGrid(timetable: timetable, now: now)
            } else if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("시간표를 불러오지 못했습니다.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            footer
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 460)
        .task { await load() }
        .onReceive(ticker) { now = $0 }
        .onChange(of: grade) { _, _ in
            klass = min(klass, max(classCount(for: grade), 1))
            publishSelection()
            Task { await load() }
        }
        .onChange(of: klass) { _, _ in
            publishSelection()
            Task { await load() }
        }
        .sheet(isPresented: $isSearchingSchool) {
            SchoolSearchView { school in
                schoolCode = school.code
                schoolName = school.name
                grade = 1
                klass = 1
                publishSelection()
                Task { await load(force: true) }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button {
                isSearchingSchool = true
            } label: {
                HStack(spacing: 4) {
                    Text(schoolName.isEmpty ? "학교 선택" : schoolName)
                        .font(.title2.bold())
                    Image(systemName: "chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .help("학교 찾기")
            .tutorialAnchor(TutorialTarget.school)

            Picker("학년", selection: $grade) {
                ForEach(availableGrades, id: \.self) { Text("\($0)학년").tag($0) }
            }
            .frame(width: 110)

            Picker("반", selection: $klass) {
                ForEach(1...max(classCount(for: grade), 1), id: \.self) { Text("\($0)반").tag($0) }
            }
            .frame(width: 100)
            .tutorialAnchor(TutorialTarget.klass)

            Spacer()

            Button {
                Task { await load(force: true) }
            } label: {
                Label("새로고침", systemImage: "arrow.clockwise")
            }
            .disabled(isLoading)
        }
        .labelsHidden()
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let timetable, !timetable.sourceUpdatedAt.isEmpty {
                Text("학교 갱신 \(timetable.sourceUpdatedAt)")
            }
            if let timetable {
                Text("· 불러온 시각 \(timetable.fetchedAt.formatted(date: .omitted, time: .shortened))")
            }
            Spacer()
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3).fill(Color.orange.opacity(0.35)).frame(width: 12, height: 12)
                Text("변경된 수업")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var availableGrades: [Int] {
        let grades = (1..<max(classCounts.count, 2)).filter { classCounts.indices.contains($0) && classCounts[$0] > 0 }
        return grades.isEmpty ? [1, 2, 3] : grades
    }

    private func classCount(for grade: Int) -> Int {
        classCounts.indices.contains(grade) ? classCounts[grade] : 10
    }

    /// 선택을 공유 저장소에 먼저 쓰고 나서 위젯을 다시 그리게 한다(순서 중요).
    private func publishSelection() {
        AppSettings.persist(grade: grade, klass: klass)
        AppSettings.persist(school: School(code: schoolCode, name: schoolName, region: ""))
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func load(force: Bool = false) async {
        isLoading = true
        publishSelection()
        defer { isLoading = false }
        do {
            let document = try await ComciService.document(school: schoolCode, forceRefresh: force)
            classCounts = document.classCounts
            timetable = try document.timetable(grade: grade, klass: klass)
            errorText = nil
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            errorText = error.localizedDescription
            if timetable?.grade != grade || timetable?.klass != klass { timetable = nil }
        }
    }
}

private struct WeekGrid: View {
    let timetable: Timetable
    let now: Date

    private var today: Int? { Timetable.dayIndex(for: now) }
    private var currentPeriod: Int? { timetable.currentPeriod(at: now) }

    var body: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                Text("")
                    .frame(width: 46)
                ForEach(0..<Timetable.dayNames.count, id: \.self) { day in
                    Text(Timetable.dayNames[day])
                        .font(.subheadline.bold())
                        .foregroundStyle(day == today ? Color.accentColor : .secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(1...timetable.maxPeriod, id: \.self) { period in
                GridRow {
                    VStack(spacing: 1) {
                        Text("\(period)")
                            .font(.subheadline.bold())
                        if let time = timetable.periodTime(period) {
                            Text(time.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 46)

                    ForEach(0..<Timetable.dayNames.count, id: \.self) { day in
                        CellView(
                            cell: timetable.cell(day: day, period: period),
                            isNow: day == today && period == currentPeriod
                        )
                    }
                }
            }
        }
    }
}

private struct CellView: View {
    let cell: TimetableCell
    let isNow: Bool

    var body: some View {
        VStack(spacing: 2) {
            if cell.isEmpty {
                Text("—").foregroundStyle(.quaternary)
            } else {
                Text(cell.displaySubject)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                if !cell.teacher.isEmpty {
                    Text(cell.teacher)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !cell.room.isEmpty {
                    Text(cell.room)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 46)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(cell.isChanged && !cell.isEmpty ? Color.orange.opacity(0.28) : Color.gray.opacity(0.12))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor, lineWidth: isNow ? 2 : 0)
        }
    }
}

#Preview {
    ContentView()
}
