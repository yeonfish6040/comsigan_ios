import Foundation
import CryptoKit

nonisolated enum ComciProtocolError: LocalizedError {
    case invalidConfiguration
    var errorDescription: String? { "시간표 연결 설정을 해석하지 못했습니다." }
}

/// 실행 코드를 포함하지 않는 v1 설정. 지원하는 변환과 암호화 연산만 선택한다.
nonisolated struct ComciProtocolConfig: Codable, Equatable, Sendable {
    struct Discovery: Codable, Equatable, Sendable {
        var enabled: Bool
        var path: String
        var encoding: String
        var maxDepth: Int
        var wrapperPattern: String
        var patterns: [String: [String]]
        var encodedSearchPattern: String
        var splitKeyPattern: String
        var keyIndexPattern: String
        var fieldPatterns: [String: String]
    }
    struct Endpoint: Codable, Equatable, Sendable {
        var route: String
        var searchPrefix: String
        var dataPrefix: String
        var encryptionKey: String
        var responseFormat: String
        var encryptedSearch: Bool
        var fieldNames: [String: String]
    }
    struct Request: Codable, Equatable, Sendable {
        var template: String
        var variableTransforms: [String: [String]]
        var transforms: [String]

        func token(variables: [String: String]) throws -> String {
            var values = variables
            for (name, operations) in variableTransforms {
                guard let value = values[name] else { throw ComciProtocolError.invalidConfiguration }
                values[name] = try Self.apply(operations, to: value)
            }
            let regex = try NSRegularExpression(pattern: #"\{([A-Za-z]+)\}"#)
            let text = NSMutableString(string: template)
            for match in regex.matches(in: template, range: NSRange(template.startIndex..., in: template)).reversed() {
                guard let range = Range(match.range(at: 1), in: template), let value = values[String(template[range])] else {
                    throw ComciProtocolError.invalidConfiguration
                }
                text.replaceCharacters(in: match.range, with: value)
            }
            return try Self.apply(transforms, to: text as String)
        }
        private static func apply(_ operations: [String], to input: String) throws -> String {
            try operations.reduce(input) { value, operation in
                switch operation {
                case "uri":
                    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
                    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
                case "base64": return Data(value.utf8).base64EncodedString()
                case "eucKRURI":
                    guard let text = String.eucKRPercentEncoded(value) else { throw ComciProtocolError.invalidConfiguration }
                    return text
                default: throw ComciProtocolError.invalidConfiguration
                }
            }
        }
    }
    struct Response: Codable, Equatable, Sendable {
        var cipher: String
        var authentication: String
        var allowPlaintext: Bool
        var hexFormats: [String]
        var base64Formats: [String]
    }
    struct SchoolFields: Codable, Equatable, Sendable {
        var root: String
        var nameIndex: Int
        var regionIndex: Int
        var markerIndex: Int
        var codeDivisor: Int
        var codeOffset: Int
    }
    var schemaVersion: Int
    var revision: String
    var baseURL: String
    var refreshSeconds: Int
    var discovery: Discovery
    var endpoint: Endpoint
    var requests: [String: Request]
    var response: Response
    var school: SchoolFields

    static let rawURL = URL(string: "https://raw.githubusercontent.com/yeonfish6040/comsigan_ios/main/Config/comci-protocol.json")!
    static let bundled = try! decode(Data(ComciProtocolDefaults.json.utf8))
    var encoded: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try! encoder.encode(self)
    }
    var cacheID: String { SHA256.hash(data: encoded).map { String(format: "%02x", $0) }.joined() }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 256 * 1024 else { throw ComciProtocolError.invalidConfiguration }
        let config = try JSONDecoder().decode(Self.self, from: data)
        try config.validate()
        return config
    }

    func validate() throws {
        func require(_ condition: Bool) throws {
            if !condition { throw ComciProtocolError.invalidConfiguration }
        }
        try require(schemaVersion == 1 && !revision.isEmpty && revision.count <= 100)
        guard let url = URLComponents(string: baseURL), let host = url.host else { throw ComciProtocolError.invalidConfiguration }
        try require(["http", "https"].contains(url.scheme ?? "") && !host.isEmpty && url.user == nil && url.password == nil && url.query == nil && url.fragment == nil && url.path.isEmpty)
        try require(!["localhost", "127.0.0.1", "::1"].contains(host) && !host.hasSuffix(".local"))
        try require((60...86400).contains(refreshSeconds) && (1...8).contains(discovery.maxDepth))
        try require(discovery.path.hasPrefix("/") && !discovery.path.hasPrefix("//") && discovery.path.count <= 200 && !discovery.path.contains("?") && !discovery.path.contains("#"))
        try require(["utf8", "eucKR"].contains(discovery.encoding))
        try require(endpoint.encryptionKey.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil)
        for value in [endpoint.route, endpoint.searchPrefix, endpoint.dataPrefix, endpoint.responseFormat] {
            try require(!value.isEmpty && value.count <= 100 && value.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil)
        }
        let requiredFields = Set(["자료147", "자료481", "자료446", "자료492"])
        try require(requiredFields.isSubset(of: Set(endpoint.fieldNames.keys)) && endpoint.fieldNames.count <= 40)
        try require(requiredFields.isSubset(of: Set(discovery.fieldPatterns.keys)))
        var patterns = discovery.patterns.values.flatMap { $0 } + Array(discovery.fieldPatterns.values)
        patterns += [discovery.wrapperPattern, discovery.encodedSearchPattern, discovery.splitKeyPattern, discovery.keyIndexPattern]
        try require(patterns.count <= 60)
        for pattern in patterns {
            try require(!pattern.isEmpty && pattern.count <= 2048)
            _ = try NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators)
        }
        func captures(_ pattern: String, _ count: Int) throws {
            let regex = try NSRegularExpression(pattern: pattern)
            try require(regex.numberOfCaptureGroups >= count)
        }
        try captures(discovery.wrapperPattern, 2)
        try captures(discovery.splitKeyPattern, 2)
        try captures(discovery.keyIndexPattern, 1)
        for pattern in discovery.patterns.values.flatMap({ $0 }) + Array(discovery.fieldPatterns.values) { try captures(pattern, 1) }
        for name in ["route", "searchPrefix", "dataPrefix", "key", "format"] {
            try require(!(discovery.patterns[name] ?? []).isEmpty)
        }
        for name in ["search", "legacySearch", "timetable"] {
            guard let request = requests[name] else { throw ComciProtocolError.invalidConfiguration }
            try require(!request.template.isEmpty && request.template.count <= 512 && request.transforms.count <= 8)
            let remainder = request.template.replacingOccurrences(of: #"\{(?:query|school|week|format|searchPrefix|dataPrefix)\}"#, with: "", options: .regularExpression)
            try require(!remainder.contains("{") && !remainder.contains("}"))
            for (variable, operations) in request.variableTransforms {
                try require(["query", "school", "week", "format", "searchPrefix", "dataPrefix"].contains(variable) && operations.count <= 8)
            }
            for operation in request.transforms + request.variableTransforms.values.flatMap({ $0 }) {
                try require(["uri", "base64", "eucKRURI"].contains(operation))
            }
            _ = try request.token(variables: ["query": "test", "school": "1", "week": "1", "format": "enc5", "searchPrefix": "1l", "dataPrefix": "1_"])
        }
        try require(response.cipher == "aes256-cbc-pkcs7" && response.authentication == "hmac-sha256-key-sha256")
        try require(!response.hexFormats.isEmpty && !response.base64Formats.isEmpty && response.hexFormats.count + response.base64Formats.count <= 16)
        for value in response.hexFormats + response.base64Formats {
            try require(value == "{format}" || value.range(of: "^[A-Za-z0-9_-]{1,32}$", options: .regularExpression) != nil)
        }
        for index in [school.nameIndex, school.regionIndex, school.markerIndex, school.codeOffset] { try require((0...100).contains(index)) }
        try require((1...1_000_000).contains(school.codeDivisor) && !school.root.isEmpty && school.root.count <= 100)
    }

    func fixedEndpoint() -> ComciEndpoint {
        ComciEndpoint(route: endpoint.route, searchPrefix: endpoint.searchPrefix, dataPrefix: endpoint.dataPrefix,
                      encryptionKey: endpoint.encryptionKey, fieldNames: endpoint.fieldNames,
                      responseFormat: endpoint.responseFormat, encryptedSearch: endpoint.encryptedSearch, protocolConfig: self)
    }
}

/// 구조 검증을 통과한 다운로드는 후보로만 저장한다. 실제 API가 성공해야 정상 설정으로 승격한다.
actor ComciProtocolStore {
    static let shared = ComciProtocolStore()
    private let defaults: UserDefaults
    private let download: @Sendable () async throws -> Data
    private let prefix = "remoteComciProtocolV1."
    init(defaults: UserDefaults = AppSettings.defaults, download: @escaping @Sendable () async throws -> Data = { try await ComciProtocolStore.downloadRaw() }) {
        self.defaults = defaults
        self.download = download
    }
    static func downloadRaw() async throws -> Data {
        var request = URLRequest(url: ComciProtocolConfig.rawURL)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw ComciProtocolError.invalidConfiguration }
        return data
    }
    private func cached(_ key: String) -> ComciProtocolConfig? {
        defaults.data(forKey: prefix + key).flatMap { try? ComciProtocolConfig.decode($0) }
    }
    func candidates(forceRefresh: Bool = false, now: Date = Date()) async -> [ComciProtocolConfig] {
        let active = cached("active")
        let lastAttempt = defaults.object(forKey: prefix + "lastAttempt") as? Date ?? .distantPast
        let age = now.timeIntervalSince(lastAttempt)
        let interval = TimeInterval(active?.refreshSeconds ?? ComciProtocolConfig.bundled.refreshSeconds)
        if age >= (forceRefresh ? 30 : interval) {
            defaults.set(now, forKey: prefix + "lastAttempt")
            do {
                let candidate = try ComciProtocolConfig.decode(await download())
                defaults.set(candidate.encoded, forKey: prefix + "pending")
            } catch { /* 오프라인·404·HTML·알 수 없는 스키마는 마지막 정상 설정을 유지한다. */ }
        }
        var seen = Set<String>()
        return [cached("pending"), cached("active"), ComciProtocolConfig.bundled].compactMap { $0 }.filter { seen.insert($0.cacheID).inserted }
    }
    func markWorking(_ config: ComciProtocolConfig) {
        defaults.set(config.encoded, forKey: prefix + "active")
        if cached("pending")?.cacheID == config.cacheID { defaults.removeObject(forKey: prefix + "pending") }
    }
    func rejectCandidate(_ config: ComciProtocolConfig) {
        if cached("pending")?.cacheID == config.cacheID { defaults.removeObject(forKey: prefix + "pending") }
    }
}
