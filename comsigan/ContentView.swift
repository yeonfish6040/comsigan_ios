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
    /// 서버가 알려준 열람 가능한 주차 목록(일자자료)과 지금 보고 있는 주차.
    /// 선택은 r 하나로만 들고 있어야 라벨이 채워질 때 화면이 다시 로드되지 않는다.
    @State private var weeks: [ComciWeek] = []
    @State private var selectedWeek = ComciWeek.first.r
    @State private var todayWeek = 1
    @State private var didPickWeek = false
    /// 표가 밀려 들어올 방향. 다음 주로 넘기면 오른쪽에서 들어온다.
    @State private var goingForward = true
    @State private var timetable: Timetable?
    @State private var classCounts: [Int] = []
    @State private var errorText: String?
    @State private var isLoading = false
    @State private var now = Date()

    private let ticker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var week: ComciWeek {
        weeks.first { $0.r == selectedWeek } ?? ComciWeek(r: selectedWeek, label: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
            // 주/학급을 바꿔도 이전 표를 그대로 두고 자리에서 갈아 끼운다.
            // 비웠다 다시 그리면 화면이 깜박인다. 새 표는 넘긴 방향으로 밀려 들어온다.
            ZStack {
                if let timetable, timetable.hasAnyClass {
                    // 창이 작아도 헤더가 잘리지 않게 표만 스크롤한다.
                    ScrollView {
                        // 다른 주를 볼 때는 '오늘'과 '현재 수업' 표시를 하지 않는다.
                        WeekGrid(
                            timetable: timetable,
                            now: week.r == todayWeek ? now : nil,
                            forward: goingForward
                        )
                    }
                } else if isLoading {
                    ProgressView()
                } else {
                    Text(emptyMessage)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped() // 밀려 들어오는 표가 헤더/푸터를 덮지 않게
            footer
        }
        .padding(20)
        #if os(macOS)
        .frame(minWidth: 620, minHeight: 460)
        #endif
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
        .onChange(of: selectedWeek) { _, _ in
            Task { await load() }
        }
        .sheet(isPresented: $isSearchingSchool) {
            SchoolSearchView { school in
                schoolCode = school.code
                schoolName = school.name
                grade = 1
                klass = 1
                weeks = []
                didPickWeek = false // 학교마다 열람 가능한 주가 다르다
                publishSelection()
                Task { await load(force: true) }
            }
        }
    }

    private var header: some View {
        // 넓은 화면은 한 줄로, 좁은 화면(아이폰)은 학교명과 선택줄을 나눠 놓는다.
        #if os(macOS)
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            schoolButton
            gradePicker.frame(width: 110)
            classPicker.frame(width: 100)
            weekStepper
            Spacer()
            refreshButton
        }
        .labelsHidden()
        #else
        VStack(alignment: .leading, spacing: 8) {
            schoolButton
            HStack(spacing: 10) {
                gradePicker
                classPicker
                weekStepper
                Spacer()
                refreshButton
            }
        }
        .labelsHidden()
        #endif
    }

    /// 주차 이동. 열람 페이지처럼 화살표로만 넘긴다.
    /// 학교가 다음 주를 아직 올리지 않았으면 목록이 하나뿐이라 감춘다.
    @ViewBuilder private var weekStepper: some View {
        if weeks.count > 1 {
            HStack(spacing: 6) {
                Button { step(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled(!canStep(-1))
                // 가운데 버튼은 오늘이 낀 주로 되돌아간다.
                Button("이번 주") {
                    goingForward = todayWeek > selectedWeek
                    selectedWeek = todayWeek
                }
                .disabled(selectedWeek == todayWeek)
                Button { step(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(!canStep(1))
                Text(weekLabel)
                    .font(.caption)
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
    }

    /// 연도를 뗀 기간 표기. "26-08-24 ~ 26-08-29" → "08-24 ~ 08-29"
    private var weekLabel: String {
        week.label
            .split(separator: "~")
            .map { $0.trimmingCharacters(in: .whitespaces).split(separator: "-").dropFirst().joined(separator: "-") }
            .joined(separator: " ~ ")
    }

    private func canStep(_ delta: Int) -> Bool {
        weeks.contains { $0.r == selectedWeek + delta }
    }

    private func step(_ delta: Int) {
        guard canStep(delta) else { return }
        goingForward = delta > 0
        selectedWeek += delta
    }

    private var emptyMessage: String {
        if errorText != nil { return "시간표를 불러오지 못했습니다." }
        return week.r == todayWeek
            ? "이번 주에는 등록된 수업이 없습니다."
            : "\(weekLabel) 시간표가 아직 올라오지 않았습니다."
    }

    private var schoolButton: some View {
        Button {
            isSearchingSchool = true
        } label: {
            HStack(spacing: 4) {
                Text(schoolName.isEmpty ? "학교 선택" : schoolName)
                    .font(.title2.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Image(systemName: "chevron.down")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .help("학교 찾기")
        .tutorialAnchor(TutorialTarget.school)
    }

    private var gradePicker: some View {
        Picker("학년", selection: $grade) {
            ForEach(availableGrades, id: \.self) { Text("\($0)학년").tag($0) }
        }
    }

    private var classPicker: some View {
        Picker("반", selection: $klass) {
            ForEach(1...max(classCount(for: grade), 1), id: \.self) { Text("\($0)반").tag($0) }
        }
        .tutorialAnchor(TutorialTarget.klass)
    }

    private var refreshButton: some View {
        Button {
            Task { await load(force: true) }
        } label: {
            #if os(macOS)
            Label("새로고침", systemImage: "arrow.clockwise")
            #else
            Image(systemName: "arrow.clockwise")
            #endif
        }
        .disabled(isLoading)
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
        #if os(iOS)
        // 애플워치는 App Group을 공유할 수 없어 선택만 따로 보낸다.
        WatchSettingsSync.shared.push()
        #endif
    }

    private func load(force: Bool = false) async {
        isLoading = true
        publishSelection()
        defer { isLoading = false }
        do {
            let document = try await ComciService.document(school: schoolCode, week: week, forceRefresh: force)
            classCounts = document.classCounts
            // 고를 수 있는 주차는 서버가 응답마다 알려준다.
            weeks = document.weeks
            todayWeek = document.todayWeek
            // 목록이 지난 주부터 시작할 수도 있어서 처음 한 번은 오늘이 낀 주로 맞춘다.
            if !didPickWeek {
                didPickWeek = true
                selectedWeek = document.todayWeek
            }
            let loaded = try document.timetable(grade: grade, klass: klass)
            withAnimation(.easeOut(duration: 0.18)) { timetable = loaded }
            errorText = nil
            // 위젯은 오늘이 낀 주만 보여주므로 그 주를 받아왔을 때만 다시 그린다.
            if week.r == todayWeek { WidgetCenter.shared.reloadAllTimelines() }
        } catch {
            errorText = error.localizedDescription
            if timetable?.grade != grade || timetable?.klass != klass { timetable = nil }
        }
    }
}

private struct WeekGrid: View {
    let timetable: Timetable
    /// 다음 주를 볼 때는 nil이라 오늘/현재 수업 표시가 꺼진다.
    let now: Date?
    /// 칸 내용이 밀려 들어올 방향.
    let forward: Bool

    private var today: Int? { now.flatMap { Timetable.dayIndex(for: $0) } }
    private var currentPeriod: Int? { now.flatMap { timetable.currentPeriod(at: $0) } }

    /// 열람 페이지처럼 요일 옆에 날짜를 붙인다. 예: "월(24)"
    private func dayTitle(_ day: Int) -> String {
        let name = Timetable.dayNames[day]
        guard let date = timetable.date(forDay: day) else { return name }
        return "\(name)(\(Calendar.current.component(.day, from: date)))"
    }

    var body: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                Text("")
                    .frame(width: 46)
                ForEach(0..<Timetable.dayNames.count, id: \.self) { day in
                    Text(dayTitle(day))
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
                            isNow: day == today && period == currentPeriod,
                            forward: forward
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
    let forward: Bool

    var body: some View {
        // 칸(배경·테두리)은 가만히 있고 글자만 제자리에서 갈린다.
        VStack(spacing: 2) {
            if cell.isEmpty {
                line("—", font: .body, style: AnyShapeStyle(.quaternary))
            } else {
                line(cell.displaySubject, font: .callout.weight(.medium), style: AnyShapeStyle(.primary))
                if !cell.teacher.isEmpty {
                    line(cell.teacher, font: .caption2, style: AnyShapeStyle(.secondary))
                }
                if !cell.room.isEmpty {
                    line(cell.room, font: .caption2, style: AnyShapeStyle(.tertiary))
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
        .clipped() // 밀려 나가는 글자가 옆 칸을 침범하지 않게
    }

    private func line(_ text: String, font: Font, style: AnyShapeStyle) -> some View {
        SwapText(text: text, font: font, style: style, forward: forward)
    }
}

/// 글자 한 줄. 내용이 바뀌면 옛 글자가 옆으로 빠지고 새 글자가 반대쪽에서 들어온다.
/// Grid 칸 안에서는 `.transition`이 먹지 않아 오프셋을 직접 움직인다.
private struct SwapText: View {
    let text: String
    let font: Font
    let style: AnyShapeStyle
    /// 다음 주로 넘길 때 true. 옛 글자가 왼쪽으로 나가고 새 글자가 오른쪽에서 들어온다.
    let forward: Bool

    @State private var shown: String
    @State private var offset: CGFloat = 0
    @State private var opacity: Double = 1

    init(text: String, font: Font, style: AnyShapeStyle, forward: Bool) {
        self.text = text
        self.font = font
        self.style = style
        self.forward = forward
        _shown = State(initialValue: text)
    }

    private static let outDuration = 0.12
    private static let inDuration = 0.16
    private static let distance: CGFloat = 14

    var body: some View {
        Text(shown)
            .font(font)
            .foregroundStyle(style)
            .lineLimit(1)
            .offset(x: offset)
            .opacity(opacity)
            .onChange(of: text) { _, next in swap(to: next) }
    }

    private func swap(to next: String) {
        let exit: CGFloat = forward ? -Self.distance : Self.distance
        withAnimation(.easeIn(duration: Self.outDuration)) {
            offset = exit
            opacity = 0
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.outDuration))
            shown = next
            offset = -exit // 반대쪽에서 들어온다
            withAnimation(.easeOut(duration: Self.inDuration)) {
                offset = 0
                opacity = 1
            }
        }
    }
}

#Preview {
    ContentView()
}
