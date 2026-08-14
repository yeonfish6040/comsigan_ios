//
//  WidgetSettingsView.swift
//  comsigan
//
//  위젯 테마와 자리별 레이아웃을 고른다. 목록은 WidgetThemes/WidgetLayouts에서
//  그대로 가져오므로, 새 테마나 레이아웃을 등록하면 여기에도 자동으로 나타난다.
//

import SwiftUI
import WidgetKit

struct WidgetSettingsView: View {
    @State private var themeId = AppSettings.widgetThemeId ?? WidgetThemes.default.id
    @State private var layoutIds: [String: String] = [:]
    @State private var palettes: [CustomPalette] = AppSettings.customPalettes()
    @State private var editing: CustomPalette?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("테마").font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(WidgetThemes.all(), id: \.id) { theme in
                            ThemePreview(
                                theme: theme,
                                isSelected: theme.id == themeId,
                                onEdit: (theme as? CustomWidgetTheme).map { custom in
                                    { editing = custom.source }
                                }
                            )
                            .onTapGesture { select(theme.id) }
                        }
                        NewPaletteCard { editing = CustomPalette.blank() }
                    }
                    .padding(.vertical, 2)
                }

                ForEach(WidgetSlot.allCases, id: \.rawValue) { slot in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(slot.label) 레이아웃").font(.headline)
                        Picker("", selection: binding(for: slot)) {
                            ForEach(WidgetLayouts.all, id: \.id) { layout in
                                Text(layout.name).tag(layout.id)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        if let layout = WidgetLayouts.all.first(where: { $0.id == layoutIds[slot.rawValue] }) {
                            Text(layout.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Text("테마는 색만 바꿉니다 — 어떤 테마든 모든 레이아웃에 그대로 적용됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .task { loadLayouts() }
        .sheet(item: $editing) { palette in
            PaletteEditorView(
                palette: palette,
                onSave: {
                    AppSettings.saveCustomPalette($0)
                    palettes = AppSettings.customPalettes()
                    select($0.id)
                    editing = nil
                },
                onDelete: {
                    AppSettings.deleteCustomPalette(id: palette.id)
                    palettes = AppSettings.customPalettes()
                    if themeId == palette.id { select(WidgetThemes.default.id) }
                    editing = nil
                },
                onCancel: { editing = nil }
            )
        }
    }

    private func binding(for slot: WidgetSlot) -> Binding<String> {
        Binding(
            get: { layoutIds[slot.rawValue] ?? slot.defaultLayout.id },
            set: { newValue in
                layoutIds[slot.rawValue] = newValue
                AppSettings.setWidgetLayoutId(newValue, slot: slot.rawValue)
                WidgetCenter.shared.reloadAllTimelines()
            }
        )
    }

    private func loadLayouts() {
        layoutIds = WidgetSlot.allCases.reduce(into: [:]) { result, slot in
            result[slot.rawValue] = AppSettings.widgetLayoutId(slot: slot.rawValue) ?? slot.defaultLayout.id
        }
    }

    private func select(_ id: String) {
        themeId = id
        AppSettings.widgetThemeId = id
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// 실제 위젯과 같은 색 구성으로 테마를 축소해 보여준다.
private struct ThemePreview: View {
    let theme: any WidgetTheme
    let isSelected: Bool
    var onEdit: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = theme.palette(dark: colorScheme == .dark)

        VStack(spacing: 0) {
            ZStack {
                // 투명 테마는 배경화면 위에 얹어 보여준다.
                if theme.isTranslucent {
                    LinearGradient(
                        colors: [Color(red: 0.43, green: 0.48, blue: 0.65), Color(red: 0.18, green: 0.20, blue: 0.31)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 2) {
                        Text("3-4").font(.system(size: 9, weight: .bold)).foregroundStyle(palette.text)
                        Text("목").font(.system(size: 9)).foregroundStyle(palette.textMuted)
                    }
                    HStack(spacing: 3) {
                        MiniCell("커문", palette.cell, palette.text)
                        MiniCell("DB", palette.cellToday, palette.text)
                        MiniCell("공수", palette.cellCurrent, palette.textOnCurrent)
                    }
                    HStack(spacing: 3) {
                        MiniCell("빅데", palette.cell, palette.text)
                        MiniCell("응개", palette.cell, palette.changed)
                        MiniCell("비영", palette.cell, palette.text)
                    }
                }
                .padding(7)
                .background(palette.background, in: RoundedRectangle(cornerRadius: 10))
                .padding(6)
            }
            .frame(width: 138, height: 104)

            HStack {
                Text(theme.name)
                    .font(.caption)
                    .fontWeight(isSelected ? .bold : .regular)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                Spacer(minLength: 0)
                if let onEdit {
                    Button("편집", action: onEdit)
                        .buttonStyle(.plain)
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(width: 138)
        .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isSelected ? Color.accentColor : Color.gray.opacity(0.25), lineWidth: isSelected ? 2 : 1)
        }
    }

    private func MiniCell(_ text: String, _ background: Color, _ foreground: Color) -> some View {
        Text(text)
            .font(.system(size: 8))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .background(background, in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(foreground)
    }
}

private struct NewPaletteCard: View {
    var onTap: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Text("＋").font(.title2).foregroundStyle(Color.accentColor)
            Text("새 팔레트").font(.caption).foregroundStyle(Color.accentColor)
        }
        .frame(width: 138, height: 140)
        .background(Color.gray.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14).strokeBorder(Color.gray.opacity(0.25), lineWidth: 1)
        }
        .onTapGesture(perform: onTap)
    }
}
