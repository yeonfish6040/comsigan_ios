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
    var responseFormat: String? = nil
    var encryptedSearch: Bool? = nil

    static let host = "http://comci.net:4082"
    var protocolConfig: ComciProtocolConfig? = nil
    var config: ComciProtocolConfig { protocolConfig ?? .bundled }
    static let fallback = ComciProtocolConfig.bundled.fixedEndpoint()

    /// 새 프로토콜은 UTF-8 검색어를 URI 인코딩하고 요청 전체를 Base64로 묶는다. 예전 서버는 EUC-KR이다.
    func searchURL(query: String) -> URL? {
        let name = encryptedSearch == true ? "search" : "legacySearch"
        guard let request = config.requests[name],
              let token = try? request.token(variables: variables(query: query)) else { return nil }
        return URL(string: "\(config.baseURL)/\(route)?\(token)")
    }

    func timetableURL(schoolCode: Int, week: Int = 1) -> URL? {
        guard let request = config.requests["timetable"],
              let token = try? request.token(variables: variables(school: schoolCode, week: week)) else { return nil }
        return URL(string: "\(config.baseURL)/\(route)?\(token)")
    }

    private func variables(query: String = "", school: Int = 0, week: Int = 1) -> [String: String] {
        ["query": query, "school": String(school), "week": String(week), "searchPrefix": searchPrefix,
         "dataPrefix": dataPrefix, "format": responseFormat ?? "enc2"]
    }

    /// 열람 페이지를 긁어 상수를 갱신한다.
    static func discover(config: ComciProtocolConfig = .bundled) async throws -> ComciEndpoint {
        if !config.discovery.enabled { return config.fixedEndpoint() }
        guard let url = URL(string: config.baseURL + config.discovery.path) else { throw ComciProtocolError.invalidConfiguration }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ComciError.malformedResponse
        }
        let encoding: String.Encoding = config.discovery.encoding == "eucKR" ? .eucKR : .utf8
        let html = String(data: data, encoding: encoding) ?? String(decoding: data, as: UTF8.self)

        return try parse(html: html, config: config)
    }

    /// JavaScript를 실행하지 않고 알려진 XOR 래퍼의 데이터만 복원한다.
    static func parse(html: String, config: ComciProtocolConfig = .bundled) throws -> ComciEndpoint {
        guard html.utf8.count <= 2_000_000 else { throw ComciError.malformedResponse }
        let rules = config.discovery
        var source = html
        let wrapper = try NSRegularExpression(pattern: rules.wrapperPattern, options: .dotMatchesLineSeparators)
        var layer = html
        for depth in 0..<rules.maxDepth {
            let matches = wrapper.matches(in: layer, range: NSRange(layer.startIndex..., in: layer))
            if matches.isEmpty { break }
            guard depth < rules.maxDepth - 1, source.utf8.count < 2_000_000 else { throw ComciError.malformedResponse }
            var nextLayer = ""
            for match in matches {
                guard let arrayRange = Range(match.range(at: 1), in: layer),
                      let keyRange = Range(match.range(at: 2), in: layer),
                      let key = Int(layer[keyRange]), (0...255).contains(key),
                      let bytes = String(layer[arrayRange]).data(using: .utf8),
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
                nextLayer += "\n" + decoded
            }
            source += nextLayer
            layer = nextLayer
        }
        func extract(_ name: String) -> String? {
            for pattern in rules.patterns[name] ?? [] {
                if let value = source.firstMatch(pattern) { return value }
            }
            return nil
        }
        guard let route = extract("route"), let searchPrefix = extract("searchPrefix"),
              let dataPrefix = extract("dataPrefix") else { throw ComciError.malformedResponse }
        let key = try responseKey(in: source, rules: rules)
        let format = extract("format")
        if format != nil, key == nil { throw ComciError.malformedResponse }
        let searchIsEncrypted = source.range(of: rules.encodedSearchPattern, options: .regularExpression) != nil
        let patterns = rules.fieldPatterns
        var fields = config.endpoint.fieldNames
        var extracted = 0
        for (canonical, pattern) in patterns {
            if let value = source.firstMatch(pattern) { fields[canonical] = value; extracted += 1 }
        }
        if key != nil, extracted != patterns.count { throw ComciError.malformedResponse }
        return ComciEndpoint(route: route, searchPrefix: searchPrefix, dataPrefix: dataPrefix,
                             encryptionKey: key, fieldNames: fields.isEmpty ? nil : fields,
                             responseFormat: format, encryptedSearch: searchIsEncrypted, protocolConfig: config)
    }

    /// enc1(16진수), enc2·enc5(Base64): HMAC 검증 후 AES-CBC/PKCS7로 복호화한다.
    func decodedResponse(_ data: Data) throws -> Data {
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        let parts = text.components(separatedBy: ":")
        let response = config.response
        let hexFormats = response.hexFormats.map { $0.replacingOccurrences(of: "{format}", with: responseFormat ?? "enc2") }
        let base64Formats = response.base64Formats.map { $0.replacingOccurrences(of: "{format}", with: responseFormat ?? "enc2") }
        let formats = hexFormats + base64Formats
        guard let format = parts.first, formats.contains(format) else {
            if text.hasPrefix("enc") || !response.allowPlaintext { throw ComciError.malformedResponse }
            return data
        }
        guard parts.count == 4, let keyText = encryptionKey, let key = Self.hexData(keyText), key.count == 32 else {
            throw ComciError.malformedResponse
        }
        let binary = try parts.dropFirst().map { part -> Data in
            if base64Formats.contains(parts[0]), let bytes = Data(base64Encoded: part), bytes.base64EncodedString() == part {
                return bytes
            }
            if hexFormats.contains(parts[0]), let bytes = Self.hexData(part),
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

    /// 공개 스크립트의 리터럴 키 또는 리터럴 배열 조각의 연결만 읽는다. JS는 실행하지 않는다.
    private static func responseKey(in source: String, rules: ComciProtocolConfig.Discovery) throws -> String? {
        for pattern in rules.patterns["key"] ?? [] {
            if let direct = source.firstMatch(pattern) { return direct }
        }
        let regex = try NSRegularExpression(pattern: rules.splitKeyPattern)
        guard let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              match.numberOfRanges >= 3,
              let expressionRange = Range(match.range(at: 1), in: source),
              let arrayRange = Range(match.range(at: 2), in: source) else { return nil }
        let expression = String(source[expressionRange])
        let json = String(source[arrayRange]).replacingOccurrences(of: "'", with: "\"")
        guard let bytes = json.data(using: .utf8),
              let fragments = try JSONSerialization.jsonObject(with: bytes) as? [String] else {
            throw ComciError.malformedResponse
        }
        let indices = try NSRegularExpression(pattern: rules.keyIndexPattern)
        var key = ""
        for match in indices.matches(in: expression, range: NSRange(expression.startIndex..., in: expression)) {
            guard let range = Range(match.range(at: 1), in: expression), let index = Int(expression[range]),
                  fragments.indices.contains(index) else { throw ComciError.malformedResponse }
            key += fragments[index]
        }
        guard key.count == 64, hexData(key)?.count == 32 else { throw ComciError.malformedResponse }
        return key
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
    init?(searchRow: Any, fields layout: ComciProtocolConfig.SchoolFields = ComciProtocolConfig.bundled.school) {
        guard let fields = searchRow as? [Any], !fields.isEmpty,
              [layout.markerIndex, layout.regionIndex, layout.nameIndex].allSatisfy({ fields.indices.contains($0) }),
              let marker = fields[layout.markerIndex] as? NSNumber,
              let region = fields[layout.regionIndex] as? String, let name = fields[layout.nameIndex] as? String,
              marker.intValue >= 0 else { return nil }
        let (index, overflow) = (marker.intValue / layout.codeDivisor).addingReportingOverflow(layout.codeOffset)
        guard !overflow else { return nil }
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
