//
//  MainView.swift
//  comsigan
//
//  탭 구성과 첫 실행 안내.
//

import SwiftUI

/// 탭 구성. 화면을 추가하려면 여기 한 줄만 늘리면 된다.
private enum MainTab: String, CaseIterable, Identifiable {
    case timetable = "시간표"
    case widget = "위젯"
    case about = "정보"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .timetable: return "calendar"
        case .widget: return "square.grid.2x2"
        case .about: return "info.circle"
        }
    }
}

struct MainView: View {
    @State private var tab: MainTab = .timetable
    @State private var showsTutorial = !AppSettings.isTutorialDone
    @State private var anchors = TutorialAnchors()

    var body: some View {
        content
            #if os(macOS)
            .frame(minWidth: 640, minHeight: 520)
            #endif
            .environment(anchors)
            .overlay {
                if showsTutorial {
                    TutorialOverlay(anchors: anchors) {
                        AppSettings.isTutorialDone = true
                        showsTutorial = false
                    }
                    .transition(.opacity)
                }
            }
    }

    #if os(macOS)
    /// 맥에서는 탭을 직접 그린다. TabView는 화면이 툭 바뀌어서 넘어가는 느낌이 없다.
    private var content: some View {
        pages.toolbar {
            ToolbarItem(placement: .principal) {
                Picker("", selection: tabBinding) {
                    ForEach(MainTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }
    #else
    private var content: some View {
        TabView(selection: tabBinding) {
            ForEach(MainTab.allCases) { item in
                page(item)
                    .tabItem { Label(item.rawValue, systemImage: item.icon) }
                    .tag(item)
            }
        }
    }
    #endif

    /// 탭을 옮길 때만 애니메이션을 건다.
    private var tabBinding: Binding<MainTab> {
        Binding(
            get: { tab },
            set: { next in withAnimation(.easeInOut(duration: 0.22)) { tab = next } }
        )
    }

    /// 세 화면을 모두 살려 둔 채 가로로 밀어 준다.
    /// 화면을 새로 만들면 시간표를 다시 불러오면서 깜박인다.
    private var pages: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(MainTab.allCases) { item in
                    page(item)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .offset(x: CGFloat(index(item) - index(tab)) * proxy.size.width)
                        .opacity(item == tab ? 1 : 0)
                        .allowsHitTesting(item == tab)
                        .accessibilityHidden(item != tab)
                }
            }
        }
        .clipped()
    }

    @ViewBuilder private func page(_ item: MainTab) -> some View {
        switch item {
        case .timetable: ContentView()
        case .widget: WidgetSettingsView()
        case .about: AboutView()
        }
    }

    private func index(_ item: MainTab) -> Int {
        MainTab.allCases.firstIndex(of: item) ?? 0
    }
}
