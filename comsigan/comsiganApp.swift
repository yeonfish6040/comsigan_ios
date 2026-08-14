//
//  comsiganApp.swift
//  comsigan
//
//  Created by Yeonjun Lee on 8/13/26.
//

#if os(macOS)
import AppKit
#endif
import SwiftUI

@main
struct comsiganApp: App {
    init() {
        #if os(iOS)
        // 워치로 설정을 넘기려면 세션을 미리 열어 둬야 한다.
        WatchSettingsSync.shared.activate()
        #endif
    }

    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            MainView()
        }
    }
}

#if os(macOS)
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 창을 닫으면 앱도 같이 종료해 Dock에 남지 않게 한다.
    /// 위젯은 별도 프로세스라 앱이 꺼져도 계속 동작한다.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
#endif
