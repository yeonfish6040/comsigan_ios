//
//  comsiganApp.swift
//  comsigan
//
//  Created by Yeonjun Lee on 8/13/26.
//

import AppKit
import SwiftUI

@main
struct comsiganApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 창을 닫으면 앱도 같이 종료해 Dock에 남지 않게 한다.
    /// 위젯은 별도 프로세스라 앱이 꺼져도 계속 동작한다.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
