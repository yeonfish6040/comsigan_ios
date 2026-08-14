//
//  SchoolSearchView.swift
//  comsigan
//
//  학교명으로 컴시간에 등록된 학교를 찾는다.
//

import SwiftUI

struct SchoolSearchView: View {
    /// 학교를 고르면 호출된다.
    var onSelect: (School) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [School] = []
    @State private var isSearching = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("학교 찾기")
                .font(.title3.bold())

            HStack {
                TextField("학교명 (예: 한국디지털미디어고)", text: $query)
                    .borderedField()
                    .onSubmit { Task { await search() } }
                Button("검색") { Task { await search() } }
                    .disabled(query.trimmingCharacters(in: .whitespaces).count < 2 || isSearching)
            }

            Group {
                if isSearching {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(results) { school in
                        Button {
                            onSelect(school)
                            dismiss()
                        } label: {
                            HStack {
                                Text(school.name)
                                Spacer()
                                Text(school.region)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .insetListStyle()
                }
            }
            .frame(minHeight: 220)

            HStack {
                Text("일과진행을 사용하는 학교만 검색됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("닫기") { dismiss() }
            }
        }
        .padding(20)
        .frame(width: 420, height: 380)
    }

    private func search() async {
        isSearching = true
        message = nil
        defer { isSearching = false }
        do {
            results = try await ComciService.searchSchools(name: query)
            if results.isEmpty { message = "검색 결과가 없습니다." }
        } catch {
            results = []
            message = error.localizedDescription
        }
    }
}
