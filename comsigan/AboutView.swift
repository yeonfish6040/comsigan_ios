//
//  AboutView.swift
//  comsigan
//

import SwiftUI

/// 개인정보 처리방침 페이지.
private let privacyPolicyURL = URL(string: "https://sneaky-parrot-647.notion.site/3bb874aebd068010b5f4e988af1a677f")!

struct AboutView: View {
    @State private var isEditingSchedule = false

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("컴시간").font(.title2.bold())
            Text("버전 \(version)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider().padding(.vertical, 10)

            Link(destination: privacyPolicyURL) {
                HStack {
                    Text("개인정보 처리방침")
                    Spacer()
                    Text("↗").foregroundStyle(Color.accentColor)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider().padding(.vertical, 10)

            Button {
                isEditingSchedule = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("일과시간 수정")
                        Text("교시 시작 시각이 실제와 다를 때")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider().padding(.vertical, 10)

            Text("현재 학급").font(.caption.bold())
            Text("\(AppSettings.school.name) \(AppSettings.grade)학년 \(AppSettings.klass)반")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("시간표 자료는 컴시간알리미(comci.net)에서 가져옵니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 6)

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $isEditingSchedule) {
            ScheduleEditorView { isEditingSchedule = false }
        }
    }
}
