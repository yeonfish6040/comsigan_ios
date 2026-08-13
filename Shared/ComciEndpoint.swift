//
//  ComciEndpoint.swift
//  comsigan
//
//  컴시간 열람 페이지(/st)에 박혀 있는 호출 상수. 컴시간이 갱신되면 값이 바뀌므로
//  페이지에서 직접 뽑아 쓰고, 실패하면 마지막으로 알려진 값으로 동작한다.
//

import Foundation

nonisolated struct ComciEndpoint: Codable, Sendable, Equatable {
    /// 자료 요청 경로. 예: "36179"
    var route: String
    /// 학교 검색 접두어. 예: "17384l"
    var searchPrefix: String
    /// 시간표 요청 접두어. 예: "73629_"
    var dataPrefix: String

    static let host = "http://comci.net:4082"
    static let fallback = ComciEndpoint(route: "36179", searchPrefix: "17384l", dataPrefix: "73629_")

    /// 학교명 검색 URL. 질의는 EUC-KR로 퍼센트 인코딩해야 한다.
    func searchURL(query: String) -> URL? {
        guard let encoded = String.eucKRPercentEncoded(query), !encoded.isEmpty else { return nil }
        return URL(string: "\(Self.host)/\(route)?\(searchPrefix)\(encoded)")
    }

    /// 시간표 URL. `<dataPrefix><학교코드>_0_<주차>`를 base64로 넘긴다.
    func timetableURL(schoolCode: Int, week: Int = 1) -> URL? {
        let payload = "\(dataPrefix)\(schoolCode)_0_\(week)"
        let token = Data(payload.utf8).base64EncodedString()
        return URL(string: "\(Self.host)/\(route)?\(token)")
    }

    /// 열람 페이지를 긁어 상수를 갱신한다.
    static func discover() async throws -> ComciEndpoint {
        guard let url = URL(string: "\(host)/st") else { return fallback }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, _) = try await URLSession.shared.data(for: request)
        let html = String(data: data, encoding: .eucKR) ?? String(decoding: data, as: UTF8.self)

        let route = html.firstMatch(#"\./(\d+)\?"#) ?? fallback.route
        let searchPrefix = html.firstMatch(#"\?(\d+l)'"#) ?? fallback.searchPrefix
        let dataPrefix = html.firstMatch(#"sc_data\('(\d+_)'"#) ?? fallback.dataPrefix
        return ComciEndpoint(route: route, searchPrefix: searchPrefix, dataPrefix: dataPrefix)
    }
}

nonisolated struct School: Codable, Sendable, Hashable, Identifiable {
    var code: Int
    var name: String
    var region: String

    var id: Int { code }
}

// MARK: - EUC-KR 유틸

extension String.Encoding {
    static let eucKR = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.EUC_KR.rawValue))
    )
}

extension String {
    /// 컴시간 페이지가 EUC-KR이라 검색어도 EUC-KR 바이트로 인코딩해야 결과가 나온다.
    static func eucKRPercentEncoded(_ value: String) -> String? {
        guard let data = value.data(using: .eucKR) else { return nil }
        var result = ""
        for byte in data {
            let isUnreserved = (byte >= 0x30 && byte <= 0x39)
                || (byte >= 0x41 && byte <= 0x5A)
                || (byte >= 0x61 && byte <= 0x7A)
                || byte == 0x2D || byte == 0x2E || byte == 0x5F || byte == 0x7E
            if isUnreserved {
                result.append(Character(UnicodeScalar(byte)))
            } else {
                result += String(format: "%%%02X", byte)
            }
        }
        return result
    }

    fileprivate func firstMatch(_ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: self) else { return nil }
        return String(self[range])
    }
}
