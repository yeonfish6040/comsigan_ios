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

        return try await withEndpoint { endpoint in
            guard let url = endpoint.searchURL(query: query) else { throw ComciError.malformedResponse }
            let data = try await fetch(url)
            guard let root = try JSONSerialization.jsonObject(with: sanitizedJSON(try endpoint.decodedResponse(data))) as? [String: Any],
                  let rows = root[endpoint.config.school.root] as? [Any] else { throw ComciError.malformedResponse }
            return rows.compactMap { School(searchRow: $0, fields: endpoint.config.school) }
        }
    }

    // MARK: - 시간표

    /// 오늘이 낀 주의 표와, 필요하면 이어지는 다음 주 표.
    /// 금요일 방과 후처럼 이번 주에 남은 수업이 `lookahead`보다 적을 때만 다음 주를 더 받아 온다.
    static func weekPair(
        school: Int,
        grade: Int,
        klass: Int,
        at date: Date = Date(),
        lookahead: Int = 3,
        forceRefresh: Bool = false
    ) async throws -> (current: Timetable, next: Timetable?) {
        // r=1이 오늘이 낀 주라는 보장이 없다. 응답의 '오늘r'을 보고 맞춘다.
        let probe = try await document(school: school, week: .first, forceRefresh: forceRefresh)
        let todayWeek = probe.todayWeek
        let currentDocument = todayWeek == ComciWeek.first.r
            ? probe
            : try await document(school: school, week: ComciWeek(r: todayWeek, label: ""), forceRefresh: forceRefresh)
        let current = try currentDocument.timetable(grade: grade, klass: klass)

        let after = current.focusPeriod(at: date) ?? .max - 1
        if current.upcoming(at: date, afterPeriod: after, limit: lookahead).count >= lookahead {
            return (current, nil)
        }

        // 학교가 다음 주를 아직 올리지 않았으면 목록에 없다.
        guard currentDocument.weeks.contains(where: { $0.r == todayWeek + 1 }),
              let nextDocument = try? await document(school: school, week: ComciWeek(r: todayWeek + 1, label: "")),
              let next = try? nextDocument.timetable(grade: grade, klass: klass),
              next.hasAnyClass else {
            return (current, nil)
        }
        return (current, next)
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
            return try await withEndpoint { endpoint in
                guard let url = endpoint.timetableURL(schoolCode: school, week: week.r) else { throw ComciError.malformedResponse }
                let clean = try endpoint.documentData(await fetch(url))
                let document = try ComciDocument(data: clean)
                guard !document.grades.isEmpty else { throw ComciError.malformedResponse }
                store(clean, school: school, week: week)
                return document
            }
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

    private static func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ComciError.malformedResponse
        }
        return data
    }

    // MARK: - 호출 상수

    private static func withEndpoint<T>(_ operation: (ComciEndpoint) async throws -> T) async throws -> T {
        var lastError: Error = ComciError.malformedResponse
        for refresh in [false, true] {
            let candidates = await ComciProtocolStore.shared.candidates(forceRefresh: refresh)
            for config in candidates {
                do {
                    let endpoint = try await endpoint(config: config, forceRefresh: refresh)
                    let value = try await operation(endpoint)
                    await ComciProtocolStore.shared.markWorking(config)
                    return value
                } catch is CancellationError { throw CancellationError() }
                catch {
                    lastError = error
                    await ComciProtocolStore.shared.rejectCandidate(config)
                }
            }
        }
        throw lastError
    }

    private static func endpoint(config: ComciProtocolConfig, forceRefresh: Bool) async throws -> ComciEndpoint {
        if !config.discovery.enabled { return config.fixedEndpoint() }
        let defaults = AppSettings.defaults
        let key = "configuredComciEndpointV1"
        if !forceRefresh, let stored = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(ComciEndpoint.self, from: stored),
           decoded.protocolConfig?.cacheID == config.cacheID,
           Date().timeIntervalSince(defaults.object(forKey: key + "CheckedAt") as? Date ?? .distantPast) < endpointLifetime {
            return decoded
        }
        let discovered = try await ComciEndpoint.discover(config: config)
        if let encoded = try? JSONEncoder().encode(discovered) {
            defaults.set(encoded, forKey: key)
            defaults.set(Date(), forKey: key + "CheckedAt")
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
