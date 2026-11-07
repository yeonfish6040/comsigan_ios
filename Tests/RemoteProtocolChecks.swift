import Foundation

actor ConfigFixture {
    var data: Data
    var fails = false
    init(_ config: ComciProtocolConfig) { data = config.encoded }
    func set(_ bytes: Data, fails: Bool = false) { data = bytes; self.fails = fails }
    func get() throws -> Data {
        if fails { throw URLError(.notConnectedToInternet) }
        return data
    }
}

@main
struct RemoteProtocolChecks {
    static func main() async throws {
        let file = URL(fileURLWithPath: CommandLine.arguments[1])
        let bundled = try ComciProtocolConfig.decode(Data(contentsOf: file))
        precondition(bundled == .bundled)
        var configured = bundled
        configured.revision = "remote-test"
        configured.discovery.enabled = false
        configured.baseURL = "https://api.example.com"
        configured.endpoint.route = "replacement"
        configured.requests["search"]!.template = "{query}_{searchPrefix}"
        var schoolLayout = configured.school
        schoolLayout.nameIndex = 1
        schoolLayout.regionIndex = 2
        schoolLayout.codeDivisor = 1_000_000
        schoolLayout.codeOffset = 0
        precondition(School(searchRow: [29175, "학교", "경기"], fields: schoolLayout)?.code == 29175)
        let endpoint = configured.fixedEndpoint()
        let token = endpoint.searchURL(query: "한국디")!.query!.removingPercentEncoding!
        let payload = String(decoding: Data(base64Encoded: token)!, as: UTF8.self)
        precondition(payload == "%ED%95%9C%EA%B5%AD%EB%94%94_21326l")
        precondition(endpoint.searchURL(query: "한국디")!.host == "api.example.com")

        var extraction = bundled
        extraction.discovery.patterns["route"] = ["routeOverride=([A-Za-z0-9]+)"]
        let html = try String(contentsOf: file.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Tests/Fixtures/student-page-enc5.html"), encoding: .utf8)
        let discovered = try ComciEndpoint.parse(html: html + " routeOverride=replaced", config: extraction)
        precondition(discovered.route == "replaced")

        configured.endpoint.fieldNames = ["자료147": "daily", "자료481": "original", "자료446": "teachers", "자료492": "subjects", "학급수": "grades", "자료244": "stamp"]
        let day: [Any] = [1, 101]
        let klass: [Any] = [0, day, day, day, day, day]
        let grade: [Any] = [0, klass]
        let table: [Any] = [0, grade]
        let response: [String: Any] = ["grades": [0, 1], "daily": table, "original": table,
                                       "teachers": ["", "교사"], "subjects": ["", "국어"], "stamp": "test"]
        let bytes = try JSONSerialization.data(withJSONObject: response)
        let document = try ComciDocument(data: configured.fixedEndpoint().documentData(bytes))
        let timetable = try document.timetable(grade: 1, klass: 1)
        precondition(timetable.cell(day: 0, period: 1).subject == "국어")
        precondition(timetable.cell(day: 0, period: 1).teacher == "교사")

        for mutation in 0..<6 {
            var invalid = bundled
            switch mutation {
            case 0: invalid.schemaVersion = 2
            case 1: invalid.requests["search"]!.transforms = ["eval"]
            case 2: invalid.response.cipher = "unknown"
            case 3: invalid.discovery.wrapperPattern = "no-capture"
            case 4: invalid.baseURL = "file:///tmp/data"
            default: invalid.requests["search"]!.template = "{unknown}"
            }
            do { _ = try ComciProtocolConfig.decode(invalid.encoded); fatalError("Invalid config accepted") }
            catch {}
        }
        do { _ = try ComciProtocolConfig.decode(Data("<html>404</html>".utf8)); fatalError("HTML accepted") } catch {}

        let suite = "comsigan.remote.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let fixture = ConfigFixture(configured)
        let store = ComciProtocolStore(defaults: defaults, download: { try await fixture.get() })
        let now = Date(timeIntervalSince1970: 1_000_000)
        let first = await store.candidates(now: now)
        precondition(first.first?.cacheID == configured.cacheID)
        precondition(defaults.data(forKey: "remoteComciProtocolV1.active") == nil)
        await store.markWorking(configured)
        await fixture.set(Data("<html>404</html>".utf8))
        let invalidRemote = await store.candidates(forceRefresh: true, now: now.addingTimeInterval(60))
        precondition(invalidRemote.first?.cacheID == configured.cacheID)
        var badAPI = configured
        badAPI.revision = "bad-api"
        await fixture.set(badAPI.encoded)
        let pending = await store.candidates(forceRefresh: true, now: now.addingTimeInterval(120))
        precondition(pending.first?.cacheID == badAPI.cacheID)
        await store.rejectCandidate(badAPI)
        let rolledBack = await store.candidates(now: now.addingTimeInterval(120))
        precondition(rolledBack.first?.cacheID == configured.cacheID)
        await fixture.set(Data(), fails: true)
        let offline = await store.candidates(forceRefresh: true, now: now.addingTimeInterval(180))
        precondition(offline.first?.cacheID == configured.cacheID)
        print("Remote request/rule/field overrides, validation, promotion, rollback and offline checks passed")
        if CommandLine.arguments.contains("--live") {
            let remote = try ComciProtocolConfig.decode(await ComciProtocolStore.downloadRaw())
            precondition(remote == bundled)
            print("GitHub Raw download passed: \(remote.revision)")
        }
    }
}
