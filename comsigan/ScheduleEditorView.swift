//
//  ScheduleEditorView.swift
//  comsigan
//
//  일과시간(교시 시작 시각) 수정. 학교가 컴시간에 올려 둔 값이 실제 운영과
//  다를 때 쓴다. 저장한 값은 앱·위젯·워치가 모두 함께 본다.
//

import SwiftUI
import WidgetKit

struct ScheduleEditorView: View {
    var onClose: () -> Void

    private let school = AppSettings.school

    @State private var times: [PeriodTime] = []
    /// 학교가 올려 둔 원본. "서버 값으로 되돌리기"에 쓴다.
    @State private var serverTimes: [PeriodTime] = []
    @State private var isLoading = true

    /// 자동 채우기 규칙 — 이 교시부터 아래로 "수업 + 쉬는시간" 간격으로 다시 깐다.
    @State private var fillFrom = 1
    @State private var lessonMinutes = 50
    @State private var breakMinutes = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("일과시간").font(.title3.bold())
            Text("\(school.name)의 교시 시작 시각입니다. 학교가 올린 값이 실제와 다르면 여기서 고치세요.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            if isLoading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(times.indices, id: \.self) { index in
                            HStack {
                                Text("\(times[index].period)교시")
                                    .font(.callout)
                                    .frame(width: 70, alignment: .leading)
                                DatePicker(
                                    "",
                                    selection: startBinding(index),
                                    displayedComponents: .hourAndMinute
                                )
                                .labelsHidden()
                                Spacer()
                                Text(endLabel(index))
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(minHeight: 220)

                Divider()

                autoFill
            }

            HStack {
                Button("서버 값으로 되돌리기") { times = serverTimes }
                    .disabled(isLoading || serverTimes.isEmpty || times == serverTimes)
                Spacer()
                Button("취소", action: onClose)
                Button("저장", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isLoading)
            }
        }
        .padding(20)
        #if os(macOS)
        .frame(width: 460)
        #endif
        .task { await load() }
    }

    /// "5교시부터 50분 수업 · 10분 쉬는시간" 한 번에 깔기.
    /// 점심처럼 중간에 긴 사이가 있는 학교는 그 뒤 교시만 골라서 다시 깔면 된다.
    private var autoFill: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Picker("", selection: $fillFrom) {
                    ForEach(times.map(\.period), id: \.self) { Text("\($0)교시").tag($0) }
                }
                .labelsHidden()
                .frame(width: 96)
                Text("부터")
                    .font(.callout)
                Spacer()
            }
            HStack(spacing: 6) {
                Stepper("수업 \(lessonMinutes)분", value: $lessonMinutes, in: 30...90, step: 5)
                    .font(.callout)
            }
            HStack(spacing: 6) {
                Stepper("쉬는시간 \(breakMinutes)분", value: $breakMinutes, in: 0...30, step: 5)
                    .font(.callout)
            }
            Button("이 간격으로 아래 교시 채우기", action: applyAutoFill)
                .disabled(times.isEmpty)
        }
    }

    // MARK: - 편집

    private static let referenceDay = Calendar.current.startOfDay(for: Date())

    private func startBinding(_ index: Int) -> Binding<Date> {
        Binding(
            get: {
                let time = times[index]
                return Calendar.current.date(
                    bySettingHour: time.hour, minute: time.minute, second: 0, of: Self.referenceDay
                ) ?? Self.referenceDay
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                times[index].hour = parts.hour ?? 0
                times[index].minute = parts.minute ?? 0
            }
        )
    }

    /// 그 교시가 끝나는 시각. 다음 교시와의 간격에서 계산하지 않고 수업 길이를 그대로 쓴다.
    private func endLabel(_ index: Int) -> String {
        let start = times[index].hour * 60 + times[index].minute
        let end = start + lessonMinutes
        return String(format: "~ %02d:%02d", (end / 60) % 24, end % 60)
    }

    private func applyAutoFill() {
        guard let anchor = times.firstIndex(where: { $0.period == fillFrom }) else { return }
        var minutes = times[anchor].hour * 60 + times[anchor].minute
        for index in anchor..<times.count {
            times[index].hour = (minutes / 60) % 24
            times[index].minute = minutes % 60
            minutes += lessonMinutes + breakMinutes
        }
    }

    // MARK: - 불러오기 / 저장

    private func load() async {
        defer { isLoading = false }
        // 캐시가 있으면 그대로 쓴다. 못 받아오면 저장해 둔 값만으로도 고칠 수 있게 둔다.
        let document = try? await ComciService.document(school: school.code)
        serverTimes = document?.serverPeriodTimes ?? []
        let resolved = AppSettings.resolvedPeriodTimes(school: school.code, server: serverTimes)
        times = resolved.isEmpty ? serverTimes : resolved
        fillFrom = times.first?.period ?? 1
    }

    private func save() {
        // 서버 값과 같아졌으면 보정을 들고 있을 이유가 없다.
        AppSettings.setPeriodTimes(times == serverTimes ? nil : times, school: school.code)
        WidgetCenter.shared.reloadAllTimelines()
        #if os(iOS)
        WatchSettingsSync.shared.push()
        #endif
        onClose()
    }
}
