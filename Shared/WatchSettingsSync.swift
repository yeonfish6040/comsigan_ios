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

final class WatchSettingsSync: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchSettingsSync()

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
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let school = AppSettings.school
        let payload: [String: Any] = [
            Key.schoolCode: school.code,
            Key.schoolName: school.name,
            Key.grade: AppSettings.grade,
            Key.klass: AppSettings.klass,
        ]
        try? WCSession.default.updateApplicationContext(payload)
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
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        // 워치가 켜질 때 마지막으로 받은 설정을 반영한다.
        if !session.receivedApplicationContext.isEmpty {
            apply(session.receivedApplicationContext)
        }
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
