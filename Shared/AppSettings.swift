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
        static let widgetTheme = "widgetTheme"
        static let widgetLayoutPrefix = "widgetLayout_"
        static let customPalettes = "customPalettes"
        static let tutorialDone = "tutorialDone"
    }

    // MARK: 위젯 꾸미기

    /// 위젯 테마 id. 투명 배경도 테마 중 하나다.
    static var widgetThemeId: String? {
        get { defaults.string(forKey: Key.widgetTheme) }
        set { defaults.set(newValue, forKey: Key.widgetTheme) }
    }

    /// 위젯 자리(크기)별로 고른 레이아웃 id.
    static func widgetLayoutId(slot: String) -> String? {
        defaults.string(forKey: Key.widgetLayoutPrefix + slot)
    }

    static func setWidgetLayoutId(_ id: String, slot: String) {
        defaults.set(id, forKey: Key.widgetLayoutPrefix + slot)
    }

    /// 사용자가 만든 팔레트 목록.
    static func customPalettes() -> [CustomPalette] {
        guard let data = defaults.data(forKey: Key.customPalettes),
              let decoded = try? JSONDecoder().decode([CustomPalette].self, from: data) else { return [] }
        return decoded
    }

    static func saveCustomPalette(_ palette: CustomPalette) {
        var list = customPalettes()
        if let index = list.firstIndex(where: { $0.id == palette.id }) {
            list[index] = palette
        } else {
            list.append(palette)
        }
        writeCustomPalettes(list)
    }

    static func deleteCustomPalette(id: String) {
        writeCustomPalettes(customPalettes().filter { $0.id != id })
    }

    private static func writeCustomPalettes(_ list: [CustomPalette]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        defaults.set(data, forKey: Key.customPalettes)
    }

    /// 첫 실행 안내를 이미 봤는지.
    static var isTutorialDone: Bool {
        get { defaults.bool(forKey: Key.tutorialDone) }
        set { defaults.set(newValue, forKey: Key.tutorialDone) }
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
