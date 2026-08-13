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
}

struct MainView: View {
    @State private var tab: MainTab = .timetable
    @State private var showsTutorial = !AppSettings.isTutorialDone
    @State private var anchors = TutorialAnchors()

    var body: some View {
        TabView(selection: $tab) {
            ContentView()
                .tabItem { Text(MainTab.timetable.rawValue) }
                .tag(MainTab.timetable)
            WidgetSettingsView()
                .tabItem { Text(MainTab.widget.rawValue) }
                .tag(MainTab.widget)
            AboutView()
                .tabItem { Text(MainTab.about.rawValue) }
                .tag(MainTab.about)
        }
        .frame(minWidth: 640, minHeight: 520)
        .environment(anchors)
        .overlay {
            if showsTutorial {
                TutorialOverlay(anchors: anchors) {
                    AppSettings.isTutorialDone = true
                    showsTutorial = false
                }
            }
        }
    }
}
