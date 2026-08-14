//
//  Tutorial.swift
//  comsigan
//
//  첫 실행 안내. 화면을 어둡게 덮고 설명할 요소만 뚫어서 보여준다.
//

import SwiftUI

/// 안내가 가리킬 화면 요소들의 위치. 화면 쪽에서 `.tutorialAnchor(_:)`로 등록한다.
@MainActor @Observable
final class TutorialAnchors {
    var frames: [String: CGRect] = [:]
}

enum TutorialTarget {
    static let school = "school"
    static let klass = "class"
}

extension View {
    /// 이 요소의 위치를 안내에 알려준다.
    func tutorialAnchor(_ key: String) -> some View {
        modifier(TutorialAnchorModifier(key: key))
    }
}

private struct TutorialAnchorModifier: ViewModifier {
    let key: String
    @Environment(TutorialAnchors.self) private var anchors: TutorialAnchors?

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { proxy in
                Color.clear.onAppear {
                    anchors?.frames[key] = proxy.frame(in: .global)
                }
                .onChange(of: proxy.frame(in: .global)) { _, frame in
                    anchors?.frames[key] = frame
                }
            }
        }
    }
}

struct TutorialStep {
    var target: String?
    var title: String
    var body: String
}

private let tutorialSteps: [TutorialStep] = [
    TutorialStep(
        target: nil,
        title: "컴시간 뷰어에 오신 걸 환영해요",
        body: "학교 시간표를 앱과 위젯으로 봅니다.\n설정은 30초면 끝나요."
    ),
    TutorialStep(
        target: TutorialTarget.school,
        title: "먼저 학교를 고르세요",
        body: "학교 이름을 누르면 검색창이 열립니다.\n이름 일부만 입력해도 찾을 수 있어요."
    ),
    TutorialStep(
        target: TutorialTarget.klass,
        title: "학년과 반 선택",
        body: "고른 학급이 시간표와 위젯에 함께 적용됩니다.\n언제든 눌러서 바꿀 수 있어요."
    ),
    TutorialStep(
        target: nil,
        title: "위젯 꾸미기",
        body: "위젯 탭에서 테마와 레이아웃을 고르세요.\n알림 센터에서 위젯을 추가하면 됩니다."
    ),
]

struct TutorialOverlay: View {
    let anchors: TutorialAnchors
    var onFinish: () -> Void

    @State private var index = 0

    var body: some View {
        let step = tutorialSteps[index]
        let hole = step.target.flatMap { anchors.frames[$0] }

        GeometryReader { proxy in
            ZStack(alignment: hole.map { $0.midY < proxy.size.height / 2 ? .bottom : .top } ?? .center) {
                // 설명할 요소만 구멍을 낸다.
                Color.black.opacity(0.72)
                    .mask {
                        ZStack {
                            Rectangle()
                            if let hole {
                                RoundedRectangle(cornerRadius: 12)
                                    .frame(width: hole.width + 16, height: hole.height + 16)
                                    .position(x: hole.midX, y: hole.midY)
                                    .blendMode(.destinationOut)
                            }
                        }
                        .compositingGroup()
                    }
                    .ignoresSafeArea()

                card(step)
                    .padding(20)
            }
        }
        // 안내 중에는 뒤쪽 화면이 눌리지 않게 막는다.
        .contentShape(Rectangle())
        .onTapGesture { }
    }

    private func card(_ step: TutorialStep) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(index + 1) / \(tutorialSteps.count)")
                .font(.caption2.bold())
                .foregroundStyle(Color.accentColor)
            Text(step.title).font(.headline)
            Text(step.body)
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button("건너뛰기", action: onFinish)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(index == tutorialSteps.count - 1 ? "시작하기" : "다음") {
                    if index == tutorialSteps.count - 1 { onFinish() } else { index += 1 }
                }
                .defaultActionShortcut()
            }
        }
        .padding(18)
        .frame(maxWidth: 420, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 20)
    }
}
