//
//  ComciService.swift
//  comsigan
//
//  컴시간 학교 검색 / 시간표 요청 + 디스크 캐시.
//

import Foundation

nonisolated enum ComciService {
    /// 캐시 유효 시간.
    static let cacheLifetime: TimeInterval = 30 * 60
    /// 호출 상수 재확인 주기.
    static let endpointLifetime: TimeInterval = 24 * 60 * 60

    // MARK: - 학교 검색

    static func searchSchools(name: String) async throws -> [School] {
        let query = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return [] }

        let endpoint = await endpoint()
        guard let url = endpoint.searchURL(query: query) else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, _) = try await URLSession.shared.data(for: request)

        guard let object = try? JSONSerialization.jsonObject(with: sanitizedJSON(data)),
              let root = object as? [String: Any],
              let rows = root["학교검색"] as? [Any] else {
            throw ComciError.malformedResponse
        }

        // 한 줄이 [내부코드, 지역, 학교명, 학교코드] 형태다.
        return rows.compactMap { row in
            guard let fields = row as? [Any], fields.count >= 4,
                  let region = fields[1] as? String,
                  let schoolName = fields[2] as? String,
                  let code = (fields[3] as? NSNumber)?.intValue else { return nil }
            return School(code: code, name: schoolName, region: region)
        }
    }

    // MARK: - 시간표

    static func timetable(
        school: Int,
        grade: Int,
        klass: Int,
        week: ComciWeek = .first,
        forceRefresh: Bool = false
    ) async throws -> Timetable {
        let document = try await document(school: school, week: week, forceRefresh: forceRefresh)
        return try document.timetable(grade: grade, klass: klass)
    }

    static func document(
        school: Int,
        week: ComciWeek = .first,
        forceRefresh: Bool = false
    ) async throws -> ComciDocument {
        if !forceRefresh, let cached = cachedData(school: school, week: week) {
            return try ComciDocument(data: cached)
        }

        do {
            let endpoint = await endpoint()
            guard let url = endpoint.timetableURL(schoolCode: school, week: week.r) else {
                throw ComciError.malformedResponse
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw ComciError.malformedResponse
            }
            let clean = sanitizedJSON(data)
            let document = try ComciDocument(data: clean) // 파싱에 성공한 것만 캐시한다
            store(clean, school: school, week: week)
            return document
        } catch {
            // 네트워크가 끊겼으면 기한이 지난 캐시라도 쓴다.
            if let stale = cachedData(school: school, week: week, ignoringAge: true) {
                return try ComciDocument(data: stale)
            }
            throw error
        }
    }

    /// NUL을 걷어내고 마지막 '}' 뒤의 잡음을 잘라낸다(열람 페이지도 같은 처리를 한다).
    static func sanitizedJSON(_ data: Data) -> Data {
        var bytes = data
        bytes.removeAll { $0 == 0 }
        if let end = bytes.lastIndex(of: UInt8(ascii: "}")) {
            return bytes[...end]
        }
        return bytes
    }

    // MARK: - 호출 상수

    private static func endpoint() async -> ComciEndpoint {
        let defaults = AppSettings.defaults
        if let stored = defaults.data(forKey: "endpoint"),
           let decoded = try? JSONDecoder().decode(ComciEndpoint.self, from: stored),
           Date().timeIntervalSince(defaults.object(forKey: "endpointCheckedAt") as? Date ?? .distantPast) < endpointLifetime {
            return decoded
        }

        guard let discovered = try? await ComciEndpoint.discover() else {
            return ComciEndpoint.fallback
        }
        if let encoded = try? JSONEncoder().encode(discovered) {
            defaults.set(encoded, forKey: "endpoint")
            defaults.set(Date(), forKey: "endpointCheckedAt")
        }
        return discovered
    }

    // MARK: - 디스크 캐시

    /// App Group 컨테이너에 두어 앱이 받아온 자료를 위젯도 그대로 쓴다.
    private static func cacheURL(school: Int, week: ComciWeek) -> URL? {
        // r=1 캐시는 기존 파일명을 유지해 위젯이 쓰던 자료를 그대로 이어 쓴다.
        let name = week.r == 1 ? "comci-\(school).json" : "comci-\(school)-r\(week.r).json"
        if let shared = AppSettings.containerURL {
            let directory = shared.appendingPathComponent("Caches", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory.appendingPathComponent(name)
        }
        guard let directory = try? FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        return directory.appendingPathComponent(name)
    }

    private static func cachedData(school: Int, week: ComciWeek, ignoringAge: Bool = false) -> Data? {
        guard let url = cacheURL(school: school, week: week),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date else { return nil }
        if !ignoringAge, Date().timeIntervalSince(modified) > cacheLifetime { return nil }
        return try? Data(contentsOf: url)
    }

    private static func store(_ data: Data, school: Int, week: ComciWeek) {
        guard let url = cacheURL(school: school, week: week) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
