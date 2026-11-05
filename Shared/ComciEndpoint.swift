//
//  ComciEndpoint.swift
//  comsigan
//
//  컴시간 열람 페이지(/st)에 박혀 있는 호출 상수. 컴시간이 갱신되면 값이 바뀌므로
//  페이지에서 직접 뽑아 쓰고, 실패하면 마지막으로 알려진 값으로 동작한다.
//

import Foundation
import CryptoKit
import CommonCrypto

nonisolated struct ComciEndpoint: Codable, Sendable, Equatable {
    /// 자료 요청 경로. 예: "36179"
    var route: String
    /// 학교 검색 접두어. 예: "17384l"
    var searchPrefix: String
    /// 시간표 요청 접두어. 예: "73629_"
    var dataPrefix: String

    /// 열람 페이지에 공개된 응답 복호화 키. nil이면 예전 평문 프로토콜이다.
    var encryptionKey: String? = nil
    var fieldNames: [String: String]? = nil

    static let host = "http://comci.net:4082"
    static let fallback = ComciEndpoint(
        route: "937001", searchPrefix: "44704l", dataPrefix: "74173_",
        encryptionKey: "6f428ea903c751d0b82f649d1e703ac5d4892fb601e8c347a5d09b2cf316784e",
        fieldNames: ["자료481": "자료121", "자료147": "자료139", "자료245": "자료151",
                     "자료446": "자료148", "자료492": "자료178", "자료244": "자료100"]
    )

    /// 학교명 검색 URL. 질의는 EUC-KR로 퍼센트 인코딩해야 한다.
    func searchURL(query: String) -> URL? {
        guard let encoded = String.eucKRPercentEncoded(query), !encoded.isEmpty else { return nil }
        return URL(string: "\(Self.host)/\(route)?\(searchPrefix)\(encoded)")
    }

    /// 시간표 URL. `<dataPrefix><학교코드>_0_<주차>`를 base64로 넘긴다.
    func timetableURL(schoolCode: Int, week: Int = 1) -> URL? {
        let payload = "\(dataPrefix)\(schoolCode)_0_\(week)" + (encryptionKey == nil ? "" : "_enc2")
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

        return try parse(html: html)
    }

    /// JavaScript를 실행하지 않고 알려진 XOR 래퍼의 데이터만 복원한다.
    static func parse(html: String) throws -> ComciEndpoint {
        var source = html
        let wrapper = try NSRegularExpression(pattern: #"\}\)\((\[\[.*?\]\]),\s*(\d+)\);"#,
                                              options: .dotMatchesLineSeparators)
        for match in wrapper.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let arrayRange = Range(match.range(at: 1), in: html),
                  let keyRange = Range(match.range(at: 2), in: html),
                  let key = Int(html[keyRange]),
                  let bytes = String(html[arrayRange]).data(using: .utf8),
                  let chunks = try JSONSerialization.jsonObject(with: bytes) as? [[Any]] else {
                throw ComciError.malformedResponse
            }
            var decoded = ""
            for chunk in chunks {
                guard chunk.count == 2, let flag = chunk[0] as? Int, let text = chunk[1] as? String else {
                    throw ComciError.malformedResponse
                }
                if flag != 0 { decoded += text; continue }
                let chars = Array(text.utf8)
                guard chars.count % 4 == 0 else { throw ComciError.malformedResponse }
                var units: [UInt16] = []
                for offset in stride(from: 0, to: chars.count, by: 4) {
                    guard let code = UInt16(String(decoding: chars[offset..<offset + 4], as: UTF8.self), radix: 16) else {
                        throw ComciError.malformedResponse
                    }
                    units.append(code ^ UInt16((key + offset / 4 * 13) & 255))
                }
                decoded += String(decoding: units, as: UTF16.self)
            }
            source += "\n" + decoded
        }
        guard let route = source.firstMatch(#"\./(\d+)\?"#),
              let searchPrefix = source.firstMatch(#"\?(\d+l)['"]"#),
              let dataPrefix = source.firstMatch(#"sc_data\(['"](\d+_)['"]"#) else {
            throw ComciError.malformedResponse
        }
        let key = source.firstMatch(#"var\s+key\s*=\s*CryptoJS\.enc\.Hex\.parse\(['"]([0-9a-f]{64})['"]\)"#)
        if source.contains("_enc2"), key == nil { throw ComciError.malformedResponse }
        let patterns = [
            "자료481": #"원자료\s*=\s*Q자료\(자료\.(자료\d+)\["#,
            "자료147": #"일일자료\s*=\s*Q자료\(자료\.(자료\d+)\["#,
            "자료245": #"var\s+m3\s*=\s*자료\.(자료\d+)\["#,
            "자료446": #"Q성명\(자료\.(자료\d+)\["#,
            "자료492": #"Q과목명\(자료\.(자료\d+)\["#,
            "자료244": #"text\(['"]수정일:\s*['"]\s*\+\s*H시간표\.(자료\d+)"#,
        ]
        var fields: [String: String] = [:]
        for (canonical, pattern) in patterns {
            if let value = source.firstMatch(pattern) { fields[canonical] = value }
        }
        if key != nil, fields.count != patterns.count { throw ComciError.malformedResponse }
        return ComciEndpoint(route: route, searchPrefix: searchPrefix, dataPrefix: dataPrefix,
                             encryptionKey: key, fieldNames: fields.isEmpty ? nil : fields)
    }

    /// enc1(16진수) / enc2(Base64): HMAC 검증 후 AES-CBC/PKCS7로 복호화한다.
    func decodedResponse(_ data: Data) throws -> Data {
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        guard text.hasPrefix("enc1:") || text.hasPrefix("enc2:") else { return data }
        let parts = text.components(separatedBy: ":")
        guard parts.count == 4, let keyText = encryptionKey, let key = Self.hexData(keyText), key.count == 32 else {
            throw ComciError.malformedResponse
        }
        let binary = try parts.dropFirst().map { part -> Data in
            if parts[0] == "enc2", let bytes = Data(base64Encoded: part), bytes.base64EncodedString() == part {
                return bytes
            }
            if parts[0] == "enc1", let bytes = Self.hexData(part),
               bytes.map({ String(format: "%02x", $0) }).joined() == part { return bytes }
            throw ComciError.malformedResponse
        }
        let iv = binary[0], ciphertext = binary[1], tag = binary[2]
        guard iv.count == kCCBlockSizeAES128, !ciphertext.isEmpty,
              ciphertext.count % kCCBlockSizeAES128 == 0, tag.count == 32,
              HMAC<SHA256>.isValidAuthenticationCode(tag,
                  authenticating: Data(parts.prefix(3).joined(separator: ":").utf8),
                  using: SymmetricKey(data: SHA256.hash(data: key))) else {
            throw ComciError.malformedResponse
        }
        var output = Data(count: ciphertext.count + kCCBlockSizeAES128)
        let capacity = output.count
        var written = 0
        let status = output.withUnsafeMutableBytes { out in
            ciphertext.withUnsafeBytes { input in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                                keyBytes.baseAddress, key.count, ivBytes.baseAddress,
                                input.baseAddress, ciphertext.count, out.baseAddress, capacity, &written)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw ComciError.malformedResponse }
        return output.prefix(written)
    }

    /// 서버가 바꾸는 자료 번호를 앱 내부의 고정 이름으로 정규화한 뒤 캐시한다.
    func documentData(_ data: Data) throws -> Data {
        var clean = try decodedResponse(data)
        clean.removeAll { $0 == 0 }
        if let end = clean.lastIndex(of: UInt8(ascii: "}")) { clean = Data(clean[...end]) }
        guard let source = try JSONSerialization.jsonObject(with: clean) as? [String: Any] else {
            throw ComciError.malformedResponse
        }
        var root = source
        for (canonical, remote) in fieldNames ?? [:] {
            guard let value = source[remote] else {
                if canonical == "자료245" { continue }
                throw ComciError.malformedResponse
            }
            root[canonical] = value
        }
        guard root["자료147"] is [Any], root["자료481"] is [Any],
              root["자료446"] is [Any], root["자료492"] is [Any] else {
            throw ComciError.malformedResponse
        }
        return try JSONSerialization.data(withJSONObject: root)
    }

    private static func hexData(_ text: String) -> Data? {
        let chars = Array(text.utf8)
        guard !chars.isEmpty, chars.count % 2 == 0 else { return nil }
        var bytes = Data()
        for offset in stride(from: 0, to: chars.count, by: 2) {
            guard let byte = UInt8(String(decoding: chars[offset..<offset + 2], as: UTF8.self), radix: 16) else { return nil }
            bytes.append(byte)
        }
        return bytes
    }
}

/// 열람할 주차. 요청 끝자리 `r`이 이 값이고, 고를 수 있는 주차 목록은
/// 응답의 `일자자료`가 알려준다(열람 페이지 일자설정하기와 동일).
nonisolated struct ComciWeek: Hashable, Sendable, Identifiable {
    var r: Int
    /// 서버가 준 기간 표기. 예: "26-08-17 ~ 26-08-22"
    var label: String

    var id: Int { r }

    /// 주차를 모르는 상태에서 처음 부를 때 쓰는 값(열람 페이지도 r=1로 시작한다).
    static let first = ComciWeek(r: 1, label: "")
}

nonisolated struct School: Codable, Sendable, Hashable, Identifiable {
    var code: Int
    var name: String
    var region: String

    /// 검색 응답은 첫 값에 따라 실제 학교 코드가 놓이는 열이 달라진다.
    init?(searchRow: Any) {
        guard let fields = searchRow as? [Any], fields.count >= 4,
              let marker = fields[0] as? NSNumber,
              let region = fields[1] as? String, let name = fields[2] as? String else { return nil }
        let index = marker.intValue / 6347 + 2
        guard fields.indices.contains(index), let code = fields[index] as? NSNumber, code.intValue > 0 else { return nil }
        self.init(code: code.intValue, name: name, region: region)
    }

    init(code: Int, name: String, region: String) {
        self.code = code
        self.name = name
        self.region = region
    }

    var id: Int { code }
}

// MARK: - EUC-KR 유틸

extension String.Encoding {
    nonisolated static let eucKR = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.EUC_KR.rawValue))
    )
}

extension String {
    /// 컴시간 페이지가 EUC-KR이라 검색어도 EUC-KR 바이트로 인코딩해야 결과가 나온다.
    nonisolated static func eucKRPercentEncoded(_ value: String) -> String? {
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

    nonisolated fileprivate func firstMatch(_ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: self) else { return nil }
        return String(self[range])
    }
}
