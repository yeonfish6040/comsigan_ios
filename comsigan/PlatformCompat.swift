//
//  PlatformCompat.swift
//  comsigan
//
//  플랫폼마다 없는 SwiftUI API를 한곳에서 흡수한다.
//  (tvOS에는 테두리 텍스트필드·키보드 단축키·컬러 피커가 없다.)
//

import SwiftUI

extension View {
    /// 입력칸 테두리. tvOS에서는 기본 모양을 그대로 쓴다.
    func borderedField() -> some View {
        #if os(tvOS)
        self
        #else
        textFieldStyle(.roundedBorder)
        #endif
    }

    /// 기본 동작(Return) 단축키. tvOS에는 키보드 개념이 없다.
    func defaultActionShortcut() -> some View {
        #if os(tvOS)
        self
        #else
        keyboardShortcut(.defaultAction)
        #endif
    }

    /// 목록 여백. tvOS에는 inset 스타일이 없다.
    func insetListStyle() -> some View {
        #if os(tvOS)
        self
        #else
        listStyle(.inset)
        #endif
    }
}
