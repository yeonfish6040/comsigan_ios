//
//  WatchSettingsSync.swift
//  comsigan
//
//  아이폰과 애플워치는 서로 다른 기기라 App Group을 공유할 수 없다.
//  그래서 학교·학년·반만 WatchConnectivity로 넘기고, 워치는 그 값으로 직접 시간표를 받아온다.
//

#if canImport(WatchConnectivity)
import Foundation
import WatchConnectivity
#if canImport(WidgetKit)
import WidgetKit
#endif

final class WatchSettingsSync: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchSettingsSync()

    /// 세션이 아직 준비되지 않았을 때 들어온 요청. 활성화되면 그때 보낸다.
    private var hasPendingPush = false

    private enum Key {
        static let schoolCode = "schoolCode"
        static let schoolName = "schoolName"
        static let grade = "grade"
        static let klass = "klass"
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// 아이폰에서 호출 — 현재 선택을 워치로 보낸다.
    func push() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default

        // 앱을 켜자마자 부르면 세션이 아직 활성화 전이라 그냥 버려진다. 활성화 후 다시 보낸다.
        guard session.activationState == .activated else {
            hasPendingPush = true
            if session.delegate == nil { session.delegate = self }
            if session.activationState == .notActivated { session.activate() }
            return
        }

        let school = AppSettings.school
        let payload: [String: Any] = [
            Key.schoolCode: school.code,
            Key.schoolName: school.name,
            Key.grade: AppSettings.grade,
            Key.klass: AppSettings.klass,
        ]
        try? session.updateApplicationContext(payload)
    }

    private func apply(_ context: [String: Any]) {
        guard let code = context[Key.schoolCode] as? Int, code > 0 else { return }
        AppSettings.persist(
            school: School(code: code, name: context[Key.schoolName] as? String ?? "", region: "")
        )
        AppSettings.persist(
            grade: context[Key.grade] as? Int ?? AppSettings.grade,
            klass: context[Key.klass] as? Int ?? AppSettings.klass
        )
        NotificationCenter.default.post(name: .watchSettingsChanged, object: nil)
        // 설정이 바뀌면 컴플리케이션(위젯)도 다시 그리게 한다.
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        guard state == .activated else { return }
        #if os(watchOS)
        // 워치가 켜질 때 마지막으로 받은 설정을 반영한다.
        if !session.receivedApplicationContext.isEmpty {
            apply(session.receivedApplicationContext)
        }
        #else
        // 아이폰은 활성화되는 대로 현재 선택을 한 번 보낸다(밀린 요청 포함).
        hasPendingPush = false
        push()
        #endif
    }

    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        apply(context)
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}

extension Notification.Name {
    static let watchSettingsChanged = Notification.Name("watchSettingsChanged")
}
#endif
