//
//  WidgetRefresh.swift
//  comsigan
//
//  위젯 갱신 요청. WidgetKit이 없는 플랫폼(tvOS)에서는 아무 일도 하지 않는다.
//

#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
func reloadWidgets() {
    #if canImport(WidgetKit)
    WidgetCenter.shared.reloadAllTimelines()
    #endif
}
