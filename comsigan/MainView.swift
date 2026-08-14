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
        TabView(selection: $tab) {
            ContentView()
                .tabItem { Label(MainTab.timetable.rawValue, systemImage: MainTab.timetable.icon) }
                .tag(MainTab.timetable)
            WidgetSettingsView()
                .tabItem { Label(MainTab.widget.rawValue, systemImage: MainTab.widget.icon) }
                .tag(MainTab.widget)
            AboutView()
                .tabItem { Label(MainTab.about.rawValue, systemImage: MainTab.about.icon) }
                .tag(MainTab.about)
        }
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
            }
        }
    }
}
