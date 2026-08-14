//
//  ComsiganWatchApp.swift
//  comsiganWatch
//

import SwiftUI

@main
struct ComsiganWatchApp: App {
    init() {
        // 아이폰이 보내는 학교·학급 설정을 받기 시작한다.
        WatchSettingsSync.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchTimetableView()
        }
    }
}
