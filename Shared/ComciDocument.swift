//
//  ComciDocument.swift
//  comsigan
//
//  컴시간 원본 JSON 파서. 서버(NestJS) 구현의 getTimeTable() 로직을 그대로 옮겼다.
//

import Foundation

nonisolated struct ComciDocument {
    private let root: [String: Any]

    init(data: Data) throws {
        var bytes = data
        bytes.removeAll { $0 == 0 } // 응답에 섞여 있는 NUL 제거
        guard let object = try? JSONSerialization.jsonObject(with: bytes),
              let dictionary = object as? [String: Any] else {
            throw ComciError.malformedResponse
        }
        root = dictionary
    }

    // MARK: - 학교 정보

    var schoolName: String { root["학교명"] as? String ?? "" }
    var sourceUpdatedAt: String { root["자료244"] as? String ?? "" }
    /// 학년별 학급 수. 인덱스 0은 사용하지 않는다.
    var classCounts: [Int] {
        (root["학급수"] as? [Any] ?? []).map { Self.numeric($0) }
    }
    var grades: [Int] {
        let counts = classCounts
        guard counts.count > 1 else { return [] }
        return (1..<counts.count).filter { counts[$0] > 0 }
    }
    func classCount(grade: Int) -> Int {
        let counts = classCounts
        return counts.indices.contains(grade) ? counts[grade] : 0
    }

    private var division: Int { Self.numeric(root["분리"], fallback: 100) }
    private var usesClassroom: Bool { Self.numeric(root["강의실"]) == 1 }
    private var usesChangeNotice: Bool { Self.numeric(root["변경알림"]) == 1 }
    private var teachers: [Any] { root["자료446"] as? [Any] ?? [] }
    private var subjects: [Any] { root["자료492"] as? [Any] ?? [] }

    var periodTimes: [PeriodTime] {
        let raw = root["일과시간"] as? [Any] ?? []
        return raw.enumerated().compactMap { index, value in
            guard let text = value as? String,
                  let open = text.firstIndex(of: "("),
                  let close = text.firstIndex(of: ")"), open < close else { return nil }
            let inside = text[text.index(after: open)..<close]
            let parts = inside.split(separator: ":")
            guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
            return PeriodTime(period: index + 1, hour: hour, minute: minute)
        }
    }

    // MARK: - 시간표 생성

    private static let maxPeriod = 8
    private static let maxDay = 5

    func timetable(grade: Int, klass: Int) throws -> Timetable {
        guard klass >= 1, klass <= classCount(grade: grade) else {
            throw ComciError.classNotFound(grade: grade, klass: klass)
        }

        let div = division
        var days: [[TimetableCell]] = []
        var periodCounts: [Int] = []

        for day in 1...Self.maxDay {
            var row = [TimetableCell](repeating: .empty, count: Self.maxPeriod)
            periodCounts.append(Self.numeric(value("자료147", [grade, klass, day, 0])))

            for period in 1...Self.maxPeriod {
                let rawDaily = value("자료147", [grade, klass, day, period])
                let originalData = Self.numeric(value("자료481", [grade, klass, day, period]))
                let dailyData = Self.numeric(rawDaily)
                // 변경알림을 쓰는 학교는 ">" 접두어가 곧 변경 표시다(열람 페이지 baSplit과 동일).
                let isChanged = usesChangeNotice
                    ? ((rawDaily as? String)?.hasPrefix(">") ?? false)
                    : originalData != dailyData

                guard dailyData > 100 else {
                    row[period - 1] = TimetableCell(isChanged: isChanged)
                    continue
                }

                let teacherIndex = teacherIndex(dailyData, div)
                var subjectIndex = subjectIndex(dailyData, div)
                let timePrefix = timePrefix(subjectIndex, div)
                subjectIndex %= div

                let teacherName = Self.teacherName(
                    teachers.indices.contains(teacherIndex) ? (teachers[teacherIndex] as? String ?? "") : ""
                )
                let subjectName = subjects.indices.contains(subjectIndex)
                    ? (subjects[subjectIndex] as? String ?? "")
                    : ""
                let group = timePrefix.isEmpty
                    ? groupCode(grade: grade, klass: klass, subject: subjectIndex, day: day, period: period)
                    : timePrefix

                row[period - 1] = TimetableCell(
                    subject: subjectName,
                    teacher: teacherName,
                    room: classroom(grade: grade, klass: klass, day: day, period: period),
                    group: group,
                    isChanged: isChanged
                )
            }
            days.append(row)
        }

        return Timetable(
            schoolName: schoolName,
            grade: grade,
            klass: klass,
            days: days,
            periodCounts: periodCounts,
            periodTimes: periodTimes,
            sourceUpdatedAt: sourceUpdatedAt,
            fetchedAt: Date()
        )
    }

    // MARK: - 원본 인코딩 해석

    private func teacherIndex(_ merged: Int, _ div: Int) -> Int {
        div == 100 ? merged / div : merged % div
    }

    private func subjectIndex(_ merged: Int, _ div: Int) -> Int {
        div == 100 ? merged % div : merged / div
    }

    /// 과목 번호에 실려 있는 동시수업 그룹(A_, B_ …) 접두어.
    private func timePrefix(_ subject: Int, _ div: Int) -> String {
        guard div != 100 else { return "" }
        let group = subject / div
        guard (1...26).contains(group) else { return "" }
        return Self.groupLetter(group)
    }

    private func classroom(grade: Int, klass: Int, day: Int, period: Int) -> String {
        guard usesClassroom,
              let info = value("자료245", [grade, klass, day, period]) as? String,
              let separator = info.firstIndex(of: "_"), separator > info.startIndex else { return "" }
        let number = Int(info[info.startIndex..<separator]) ?? 0
        guard number > 0 else { return "" }
        return String(info[info.index(after: separator)...])
    }

    /// 동시수업 그룹표(동시그룹)에서 이 칸이 속한 그룹을 찾는다.
    private func groupCode(grade: Int, klass: Int, subject: Int, day: Int, period: Int) -> String {
        let div = division
        guard let groups = root["동시그룹"] as? [Any] else { return "" }
        let groupCount = Self.numeric((groups.first as? [Any])?.first)
        guard groupCount > 0 else { return "" }

        for i in 1...groupCount {
            guard groups.indices.contains(i), let inner = groups[i] as? [Any] else { continue }
            let innerCount = Self.numeric(inner.first)
            guard innerCount > 0 else { continue }

            for pass in 1...2 {
                var matched = false
                var currentGroup = 0

                for j in 1...innerCount {
                    guard inner.indices.contains(j) else { continue }
                    let groupValue = Self.numeric(inner[j])

                    let subject4 = groupValue / 1000
                    let group2 = subject4 / 1000
                    let subject2 = subject4 - group2 * 1000
                    let teacher = group2 / 100
                    let group = group2 - teacher * 100
                    let classroom = groupValue - subject4 * 1000
                    let grade2 = classroom / 100
                    let class2 = classroom - grade2 * 100

                    let rawValue = Self.numeric(value("자료147", [grade2, class2, day, period]))
                    let subject3 = rawValue / div
                    let teacher2 = rawValue - subject3 * div

                    if pass == 1 {
                        guard subject2 == subject3, teacher == teacher2 else {
                            matched = false
                            break
                        }
                        if grade == grade2, klass == class2, subject == subject2, teacher == teacher2, group > 0 {
                            matched = true
                            currentGroup = group
                        }
                    } else {
                        guard subject2 == subject3 else {
                            matched = false
                            break
                        }
                        if grade == grade2, klass == class2, subject == subject2, group > 0 {
                            matched = true
                            currentGroup = group
                        }
                    }
                }

                if matched { return Self.groupLetter(currentGroup) }
            }
        }
        return ""
    }

    /// 교사명의 별표를 떼어낸다(열람 페이지 Q성명과 동일).
    /// 이름 가운데에 별표가 있거나 "김*" 형태면 그대로 두고, 그 외에는 첫 별표만 지운다.
    private static func teacherName(_ raw: String) -> String {
        guard !raw.isEmpty else { return "" }
        let keepAsIs = (raw.contains("*") && !raw.hasPrefix("*") && !raw.hasSuffix("*"))
            || (raw.count == 2 && Array(raw)[1] == "*")
        guard !keepAsIs, let range = raw.range(of: "*") else { return raw }
        return raw.replacingCharacters(in: range, with: "")
    }

    private static func groupLetter(_ group: Int) -> String {
        guard let scalar = Unicode.Scalar(group + 64) else { return "" }
        return "\(Character(scalar))_"
    }

    // MARK: - JSON 탐색

    private func value(_ key: String, _ path: [Int]) -> Any? {
        var current: Any? = root[key]
        for index in path {
            guard let array = current as? [Any], array.indices.contains(index) else { return nil }
            current = array[index]
        }
        return current
    }

    /// 숫자 또는 ">31033" 형태의 변경 표기 문자열을 정수로 바꾼다.
    private static func numeric(_ any: Any?, fallback: Int = 0) -> Int {
        switch any {
        case let number as NSNumber:
            return number.intValue
        case let text as String:
            let trimmed = text.hasPrefix(">") ? String(text.dropFirst()) : text
            return Int(trimmed) ?? Int(Double(trimmed) ?? 0)
        default:
            return fallback
        }
    }
}
