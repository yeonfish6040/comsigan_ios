//
//  PaletteEditorView.swift
//  comsigan
//
//  사용자 정의 팔레트 편집. 색 목록은 ColorSlot.all을 그대로 훑으므로
//  팔레트에 색이 늘어나면 여기도 자동으로 늘어난다.
//

import SwiftUI

struct PaletteEditorView: View {
    @State var palette: CustomPalette
    var onSave: (CustomPalette) -> Void
    var onDelete: () -> Void
    var onCancel: () -> Void

    @State private var isExisting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("팔레트 편집").font(.title3.bold())

            HStack(spacing: 12) {
                PalettePreview(palette: palette.palette(), translucent: palette.isTranslucent)
                VStack(alignment: .leading, spacing: 8) {
                    TextField("이름", text: $palette.name)
                        .textFieldStyle(.roundedBorder)
                    Toggle("배경이 비치는 테마", isOn: $palette.isTranslucent)
                        .toggleStyle(.switch)
                }
            }

            Divider()

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(ColorSlot.all) { slot in
                        ColorRow(slot: slot, palette: $palette)
                    }
                }
            }
            .frame(height: 250)

            Text("색은 #RRGGBBAA(rgba) 표기입니다. 끝 두 자리가 투명도예요.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                if isExisting {
                    Button("삭제", role: .destructive, action: onDelete)
                }
                Spacer()
                Button("취소", action: onCancel)
                Button("저장") { onSave(palette) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            isExisting = AppSettings.customPalettes().contains { $0.id == palette.id }
        }
    }
}

/// 색 한 줄 — 네이티브 컬러 피커와 RGBA 입력을 함께 준다.
private struct ColorRow: View {
    let slot: ColorSlot
    @Binding var palette: CustomPalette

    @State private var text: String = ""

    var body: some View {
        HStack(spacing: 10) {
            ColorPicker("", selection: colorBinding, supportsOpacity: true)
                .labelsHidden()
                .frame(width: 44)
            Text(slot.label)
                .font(.callout)
                .frame(width: 110, alignment: .leading)
            TextField("#RRGGBBAA", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .onSubmit { commit() }
                .onChange(of: text) { _, _ in commit() }
        }
        .onAppear { text = palette.colors[slot.key] ?? RGBA.string(from: slot.get(palette.palette())) }
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { slot.get(palette.palette()) },
            set: { newValue in
                let encoded = RGBA.string(from: newValue)
                palette.colors[slot.key] = encoded
                text = encoded
            }
        )
    }

    private func commit() {
        guard RGBA.color(from: text) != nil else { return }
        palette.colors[slot.key] = text
    }
}

private struct PalettePreview: View {
    let palette: WidgetPalette
    let translucent: Bool

    var body: some View {
        ZStack {
            if translucent {
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
                    cell("커문", palette.cell, palette.text)
                    cell("DB", palette.cellToday, palette.text)
                    cell("공수", palette.cellCurrent, palette.textOnCurrent)
                }
                HStack(spacing: 3) {
                    cell("빅데", palette.cell, palette.text)
                    cell("응개", palette.cell, palette.changed)
                    cell("비영", palette.cell, palette.text)
                }
            }
            .padding(7)
            .background(palette.background, in: RoundedRectangle(cornerRadius: 10))
            .padding(6)
        }
        .frame(width: 150, height: 106)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func cell(_ text: String, _ background: Color, _ foreground: Color) -> some View {
        Text(text)
            .font(.system(size: 8))
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .background(background, in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(foreground)
    }
}
