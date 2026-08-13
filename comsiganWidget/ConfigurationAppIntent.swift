//
//  ConfigurationAppIntent.swift
//  comsiganWidget
//
//  위젯 편집 화면에서 학년/반을 고른다.
//

import AppIntents
import WidgetKit

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "시간표" }
    static var description: IntentDescription { "표시할 학년과 반을 선택합니다." }

    /// 꺼져 있으면(= 값이 없으면) 앱에서 고른 학년/반을 따라간다.
    /// 예전에 추가된 위젯의 저장된 설정에는 이 키가 없어 false로 읽히므로,
    /// "앱 따르기"가 기본이 되도록 일부러 이 방향으로 두었다.
    @Parameter(title: "다른 학급 직접 지정", default: false)
    var overridesClass: Bool

    @Parameter(title: "학년", default: 1, inclusiveRange: (1, 6))
    var grade: Int

    @Parameter(title: "반", default: 1, inclusiveRange: (1, 20))
    var klass: Int

    static var parameterSummary: some ParameterSummary {
        When(\.$overridesClass, .equalTo, true) {
            Summary("\(\.$grade)학년 \(\.$klass)반 표시") {
                \.$overridesClass
                \.$grade
                \.$klass
            }
        } otherwise: {
            Summary("앱에서 고른 학급 표시") {
                \.$overridesClass
            }
        }
    }

    init() {}

    init(grade: Int, klass: Int, overridesClass: Bool = true) {
        self.grade = grade
        self.klass = klass
        self.overridesClass = overridesClass
    }

    /// 실제로 표시할 학급.
    var resolvedGrade: Int { overridesClass ? grade : AppSettings.grade }
    var resolvedClass: Int { overridesClass ? klass : AppSettings.klass }
}
