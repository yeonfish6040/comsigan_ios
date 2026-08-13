//
//  WidgetTheme.swift
//  comsigan
//
//  위젯 색 한 벌(테마). 레이아웃은 색을 직접 쓰지 않고 항상 팔레트를 통해 읽으므로,
//  어떤 테마든 모든 레이아웃에 그대로 적용된다.
//

import SwiftUI

nonisolated struct WidgetPalette: Sendable, Equatable {
    var background: Color
    /// 일반 칸 배경.
    var cell: Color
    /// 오늘 요일 칸 배경.
    var cellToday: Color
    /// 현재 교시 칸 배경.
    var cellCurrent: Color
    var text: Color
    var textMuted: Color
    /// 현재 교시 칸 위의 글자색.
    var textOnCurrent: Color
    var accent: Color
    /// 변경·보강된 수업.
    var changed: Color
}

extension WidgetPalette {
    /// 위젯이 비활성일 때 macOS는 vibrant 모드로 그린다. 이 모드에서는 내용이 전부
    /// 흰색으로 매핑되므로, 불투명한 칸 배경은 흰 덩어리가 되고 그 위 글자가 사라진다.
    /// 그래서 색 대신 "알파 차이"로 층을 나눈 팔레트를 쓴다.
    var vibrant: WidgetPalette {
        WidgetPalette(
            background: .clear,
            cell: Color.white.opacity(0.14),
            cellToday: Color.white.opacity(0.22),
            cellCurrent: Color.white.opacity(0.38),
            text: Color.white,
            textMuted: Color.white.opacity(0.65),
            textOnCurrent: Color.white,
            accent: Color.white.opacity(0.85),
            changed: Color.white.opacity(0.9)
        )
    }
}

/// 위젯 테마. 새 테마는 여기 구현체를 만들고 [WidgetThemes.builtIn]에 한 줄 더하면 된다.
nonisolated protocol WidgetTheme: Sendable {
    var id: String { get }
    var name: String { get }
    /// 배경이 비치는 테마인지(앱 미리보기에서 배경화면 위에 얹어 보여준다).
    var isTranslucent: Bool { get }

    func palette(dark: Bool) -> WidgetPalette
}

extension WidgetTheme {
    var isTranslucent: Bool { false }
}

// MARK: - 기본 테마

/// 시스템 밝기를 따르는 기본 테마.
nonisolated struct SystemWidgetTheme: WidgetTheme {
    let id = "system"
    let name = "시스템"

    func palette(dark: Bool) -> WidgetPalette {
        dark
            ? WidgetPalette(
                background: Color(white: 0.11),
                cell: Color(white: 0.19),
                cellToday: Color(red: 0.24, green: 0.22, blue: 0.31),
                cellCurrent: Color(red: 0.34, green: 0.27, blue: 0.60),
                text: Color(white: 0.92),
                textMuted: Color(white: 0.68),
                textOnCurrent: Color(white: 0.97),
                accent: Color(red: 0.82, green: 0.74, blue: 1.0),
                changed: Color(red: 1.0, green: 0.72, blue: 0.44)
            )
            : WidgetPalette(
                background: Color(white: 0.99),
                cell: Color(red: 0.93, green: 0.91, blue: 0.95),
                cellToday: Color(red: 0.87, green: 0.89, blue: 0.98),
                cellCurrent: Color(red: 0.81, green: 0.77, blue: 0.96),
                text: Color(white: 0.10),
                textMuted: Color(white: 0.38),
                textOnCurrent: Color(red: 0.13, green: 0.0, blue: 0.36),
                accent: Color(red: 0.40, green: 0.31, blue: 0.64),
                changed: Color(red: 0.76, green: 0.38, blue: 0.04)
            )
    }
}

/// 배경이 비치는 테마 — 어두운 배경화면용(밝은 글씨).
nonisolated struct TransparentLightTextTheme: WidgetTheme {
    let id = "transparent"
    let name = "투명 · 밝은 글씨"
    let isTranslucent = true

    func palette(dark: Bool) -> WidgetPalette {
        WidgetPalette(
            background: .clear,
            cell: Color.black.opacity(0.22),
            cellToday: Color.black.opacity(0.34),
            cellCurrent: Color.white.opacity(0.6),
            text: .white,
            textMuted: Color.white.opacity(0.8),
            textOnCurrent: Color(white: 0.11),
            accent: Color(red: 0.82, green: 0.74, blue: 1.0),
            changed: Color(red: 1.0, green: 0.76, blue: 0.47)
        )
    }
}

/// 배경이 비치는 테마 — 밝은 배경화면용(어두운 글씨).
nonisolated struct TransparentDarkTextTheme: WidgetTheme {
    let id = "transparentDark"
    let name = "투명 · 어두운 글씨"
    let isTranslucent = true

    func palette(dark: Bool) -> WidgetPalette {
        WidgetPalette(
            background: .clear,
            cell: Color.white.opacity(0.19),
            cellToday: Color.white.opacity(0.33),
            cellCurrent: Color.black.opacity(0.66),
            text: Color(white: 0.08),
            textMuted: Color.black.opacity(0.75),
            textOnCurrent: .white,
            accent: Color(red: 0.31, green: 0.22, blue: 0.55),
            changed: Color(red: 0.54, green: 0.24, blue: 0.0)
        )
    }
}

/// 밝기 모드와 무관하게 항상 어두운 테마.
nonisolated struct MidnightWidgetTheme: WidgetTheme {
    let id = "midnight"
    let name = "미드나이트"

    func palette(dark: Bool) -> WidgetPalette {
        WidgetPalette(
            background: Color(red: 0.10, green: 0.09, blue: 0.13),
            cell: Color(red: 0.17, green: 0.16, blue: 0.19),
            cellToday: Color(red: 0.23, green: 0.21, blue: 0.28),
            cellCurrent: Color(red: 0.31, green: 0.22, blue: 0.55),
            text: Color(white: 0.90),
            textMuted: Color(white: 0.68),
            textOnCurrent: Color(red: 0.92, green: 0.87, blue: 1.0),
            accent: Color(red: 0.82, green: 0.74, blue: 1.0),
            changed: Color(red: 1.0, green: 0.72, blue: 0.44)
        )
    }
}

/// 밝기 모드와 무관하게 항상 밝은 테마.
nonisolated struct PaperWidgetTheme: WidgetTheme {
    let id = "paper"
    let name = "페이퍼"

    func palette(dark: Bool) -> WidgetPalette {
        WidgetPalette(
            background: Color(red: 0.99, green: 0.98, blue: 1.0),
            cell: Color(red: 0.93, green: 0.91, blue: 0.95),
            cellToday: Color(red: 0.87, green: 0.89, blue: 0.98),
            cellCurrent: Color(red: 0.81, green: 0.77, blue: 0.96),
            text: Color(white: 0.11),
            textMuted: Color(white: 0.37),
            textOnCurrent: Color(red: 0.13, green: 0.0, blue: 0.36),
            accent: Color(red: 0.40, green: 0.31, blue: 0.64),
            changed: Color(red: 0.70, green: 0.33, blue: 0.04)
        )
    }
}

/// 바다색 계열.
nonisolated struct OceanWidgetTheme: WidgetTheme {
    let id = "ocean"
    let name = "오션"

    func palette(dark: Bool) -> WidgetPalette {
        dark
            ? WidgetPalette(
                background: Color(red: 0.03, green: 0.10, blue: 0.14),
                cell: Color(red: 0.07, green: 0.19, blue: 0.25),
                cellToday: Color(red: 0.09, green: 0.25, blue: 0.35),
                cellCurrent: Color(red: 0.04, green: 0.43, blue: 0.56),
                text: Color(red: 0.86, green: 0.95, blue: 1.0),
                textMuted: Color(red: 0.62, green: 0.77, blue: 0.84),
                textOnCurrent: .white,
                accent: Color(red: 0.44, green: 0.84, blue: 0.96),
                changed: Color(red: 1.0, green: 0.75, blue: 0.47)
            )
            : WidgetPalette(
                background: Color(red: 0.95, green: 0.98, blue: 1.0),
                cell: Color(red: 0.87, green: 0.93, blue: 0.96),
                cellToday: Color(red: 0.78, green: 0.89, blue: 0.95),
                cellCurrent: Color(red: 0.04, green: 0.43, blue: 0.56),
                text: Color(red: 0.02, green: 0.13, blue: 0.18),
                textMuted: Color(red: 0.31, green: 0.42, blue: 0.47),
                textOnCurrent: .white,
                accent: Color(red: 0.04, green: 0.43, blue: 0.56),
                changed: Color(red: 0.70, green: 0.33, blue: 0.04)
            )
    }
}

// MARK: - 사용자 정의 팔레트

/// 사용자가 앱에서 만든 팔레트. 색은 밝기 모드와 무관하게 지정한 값 그대로 쓴다.
nonisolated struct CustomPalette: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var name: String
    var isTranslucent: Bool
    /// 색 이름 → "#RRGGBBAA"
    var colors: [String: String]

    static func blank(id: String = "custom-\(Int(Date().timeIntervalSince1970))") -> CustomPalette {
        CustomPalette(
            id: id,
            name: "내 팔레트",
            isTranslucent: false,
            colors: ColorSlot.all.reduce(into: [:]) { result, slot in
                result[slot.key] = RGBA.string(from: slot.get(MidnightWidgetTheme().palette(dark: true)))
            }
        )
    }

    func palette() -> WidgetPalette {
        var result = MidnightWidgetTheme().palette(dark: true)
        for slot in ColorSlot.all {
            if let text = colors[slot.key], let color = RGBA.color(from: text) {
                result = slot.set(result, color)
            }
        }
        return result
    }
}

nonisolated struct CustomWidgetTheme: WidgetTheme {
    let source: CustomPalette

    var id: String { source.id }
    var name: String { source.name }
    var isTranslucent: Bool { source.isTranslucent }

    func palette(dark: Bool) -> WidgetPalette { source.palette() }
}

/// 팔레트에서 색 하나를 가리키는 항목. 편집 화면은 이 목록을 훑어 만들어진다.
nonisolated struct ColorSlot: Identifiable, Sendable {
    let key: String
    let label: String
    let get: @Sendable (WidgetPalette) -> Color
    let set: @Sendable (WidgetPalette, Color) -> WidgetPalette

    var id: String { key }

    static let all: [ColorSlot] = [
        ColorSlot(key: "background", label: "배경", get: { $0.background }, set: { var p = $0; p.background = $1; return p }),
        ColorSlot(key: "cell", label: "칸", get: { $0.cell }, set: { var p = $0; p.cell = $1; return p }),
        ColorSlot(key: "cellToday", label: "오늘 칸", get: { $0.cellToday }, set: { var p = $0; p.cellToday = $1; return p }),
        ColorSlot(key: "cellCurrent", label: "현재 교시 칸", get: { $0.cellCurrent }, set: { var p = $0; p.cellCurrent = $1; return p }),
        ColorSlot(key: "text", label: "글자", get: { $0.text }, set: { var p = $0; p.text = $1; return p }),
        ColorSlot(key: "textMuted", label: "보조 글자", get: { $0.textMuted }, set: { var p = $0; p.textMuted = $1; return p }),
        ColorSlot(key: "textOnCurrent", label: "현재 교시 글자", get: { $0.textOnCurrent }, set: { var p = $0; p.textOnCurrent = $1; return p }),
        ColorSlot(key: "accent", label: "강조", get: { $0.accent }, set: { var p = $0; p.accent = $1; return p }),
        ColorSlot(key: "changed", label: "변경 수업", get: { $0.changed }, set: { var p = $0; p.changed = $1; return p }),
    ]
}

/// "#RRGGBBAA" 표기 — 알파를 뒤에 붙이는 rgba 순서다.
nonisolated enum RGBA {
    static func color(from text: String) -> Color? {
        var hex = text.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        let full: String
        switch hex.count {
        case 3: full = hex.map { "\($0)\($0)" }.joined() + "FF"
        case 6: full = hex + "FF"
        case 8: full = hex
        default: return nil
        }
        guard let value = UInt32(full, radix: 16) else { return nil }
        return Color(
            .sRGB,
            red: Double((value >> 24) & 0xFF) / 255,
            green: Double((value >> 16) & 0xFF) / 255,
            blue: Double((value >> 8) & 0xFF) / 255,
            opacity: Double(value & 0xFF) / 255
        )
    }

    static func string(from color: Color) -> String {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.black
        let channel = { (value: CGFloat) in Int((value * 255).rounded()) }
        return String(
            format: "#%02X%02X%02X%02X",
            channel(resolved.redComponent),
            channel(resolved.greenComponent),
            channel(resolved.blueComponent),
            channel(resolved.alphaComponent)
        )
    }
}

// MARK: - 목록

nonisolated enum WidgetThemes {
    /// 앱에 내장된 테마.
    static let builtIn: [any WidgetTheme] = [
        SystemWidgetTheme(),
        TransparentLightTextTheme(),
        TransparentDarkTextTheme(),
        MidnightWidgetTheme(),
        PaperWidgetTheme(),
        OceanWidgetTheme(),
    ]

    static let `default`: any WidgetTheme = SystemWidgetTheme()

    /// 기본 테마 + 사용자 팔레트.
    static func all() -> [any WidgetTheme] {
        builtIn + AppSettings.customPalettes().map { CustomWidgetTheme(source: $0) }
    }

    static func byId(_ id: String?) -> any WidgetTheme {
        all().first { $0.id == id } ?? `default`
    }
}
