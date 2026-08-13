//
//  AppSettings.swift
//  comsigan
//
//  앱과 위젯이 App Group으로 공유하는 설정.
//

import Foundation

nonisolated enum AppSettings {
    static let appGroupID = "group.com.yftech.comsigan"

    /// App Group 저장소. 사용할 수 없으면 표준 저장소로 물러난다.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    enum Key {
        static let grade = "grade"
        static let klass = "klass"
        static let schoolCode = "schoolCode"
        static let schoolName = "schoolName"
    }

    /// 처음 실행 시 기본으로 보던 학교(검색 결과의 이름·코드 그대로).
    static let defaultSchool = School(code: 29175, name: "한국디지털미디어고등학", region: "경기")

    static var school: School {
        let code = defaults.integer(forKey: Key.schoolCode)
        guard code > 0 else { return defaultSchool }
        return School(
            code: code,
            name: defaults.string(forKey: Key.schoolName) ?? "",
            region: ""
        )
    }

    static func persist(school: School) {
        defaults.set(school.code, forKey: Key.schoolCode)
        defaults.set(school.name, forKey: Key.schoolName)
    }

    static var grade: Int {
        let value = defaults.integer(forKey: Key.grade)
        return value > 0 ? value : 1
    }

    static var klass: Int {
        let value = defaults.integer(forKey: Key.klass)
        return value > 0 ? value : 1
    }

    /// 위젯이 첫 실행부터 같은 값을 읽도록 현재 선택을 공유 저장소에 기록한다.
    static func persist(grade: Int, klass: Int) {
        defaults.set(grade, forKey: Key.grade)
        defaults.set(klass, forKey: Key.klass)
    }

    /// App Group 컨테이너. 캐시를 앱과 위젯이 함께 쓴다.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }
}
