import Foundation
import CryptoKit

@main
struct Checks {
    static func main() async throws {
        let fixtures = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let html = try String(contentsOf: fixtures.appendingPathComponent("student-page.html"), encoding: .utf8)
        let endpoint = try ComciEndpoint.parse(html: html)
        precondition(endpoint.route == "937001")
        precondition(endpoint.fieldNames?["자료147"] == "자료139")
        let bytes = try Data(contentsOf: fixtures.appendingPathComponent("timetable-enc2.txt"))
        let document = try ComciDocument(data: endpoint.documentData(bytes))
        let timetable = try document.timetable(grade: 1, klass: 1)
        precondition(timetable.hasAnyClass)
        precondition(timetable.days.flatMap { $0 }.contains { !$0.teacher.isEmpty })
        print("Recorded enc2: school=\(document.schoolName), Monday=\(timetable.days[0].map(\.displaySubject))")
        var parts = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\0")).components(separatedBy: ":")
        parts[3] = Data(repeating: 0, count: 32).base64EncodedString()
        do { _ = try endpoint.documentData(Data(parts.joined(separator: ":").utf8)); fatalError("Tampered HMAC accepted") }
        catch { print("Tampered HMAC rejected") }
        let keyHex = endpoint.encryptionKey!
        let key = Data(stride(from: 0, to: keyHex.count, by: 2).map { i in
            let start = keyHex.index(keyHex.startIndex, offsetBy: i)
            return UInt8(keyHex[start..<keyHex.index(start, offsetBy: 2)], radix: 16)!
        })
        parts = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\0")).components(separatedBy: ":")
        parts[0] = "enc1"
        for i in 1...2 { parts[i] = Data(base64Encoded: parts[i])!.map { String(format: "%02x", $0) }.joined() }
        parts[3] = HMAC<SHA256>.authenticationCode(for: Data(parts.prefix(3).joined(separator: ":").utf8), using: SymmetricKey(data: SHA256.hash(data: key))).map { String(format: "%02x", $0) }.joined()
        let hexDocument = try ComciDocument(data: endpoint.documentData(Data(parts.joined(separator: ":").utf8)))
        let hexTimetable = try hexDocument.timetable(grade: 1, klass: 1)
        precondition(hexTimetable.days == timetable.days)
        precondition(School(searchRow: [19041, "경기", "학교", 70989, 18320, 29175])?.code == 29175)
        precondition(School(searchRow: [6347, "경기", "학교", 29175, 10219, 25708])?.code == 29175)
        print("enc1 and rotating school-code columns passed")
        // OpenSSL AES + Python HMAC으로 따로 만든 고정 벡터도 같은 결과여야 한다.
        for mode in ["enc1", "enc2"] {
            let vector = try Data(contentsOf: fixtures.appendingPathComponent("vector-\(mode).txt"))
            let vectorDocument = try ComciDocument(data: endpoint.documentData(vector))
            let vectorTimetable = try vectorDocument.timetable(grade: 1, klass: 1)
            precondition(vectorTimetable.cell(day: 0, period: 1).subject == "국어")
            precondition(vectorTimetable.cell(day: 0, period: 1).teacher == "교사")
        }
        do {
            _ = try endpoint.documentData(Data(#"{"학급수":[0,1]}"#.utf8))
            fatalError("Incomplete schema accepted")
        } catch { print("Incomplete schema rejected; independent encrypted vectors passed") }
        guard CommandLine.arguments.contains("--live") else { return }
        let live = try await ComciEndpoint.discover()
        let (search, _) = try await URLSession.shared.data(from: live.searchURL(query: "디지털미디어")!)
        let root = try JSONSerialization.jsonObject(with: search) as! [String: Any]
        let schools = (root["학교검색"] as! [Any]).compactMap { School(searchRow: $0) }
        precondition(schools.first?.code == 29175)
        let (response, _) = try await URLSession.shared.data(from: live.timetableURL(schoolCode: schools[0].code)!)
        let liveDocument = try ComciDocument(data: live.documentData(response))
        let liveTimetable = try liveDocument.timetable(grade: 1, klass: 1)
        precondition(liveTimetable.hasAnyClass)
        print("Live discovery → search → encrypted response → populated timetable passed")
    }
}
