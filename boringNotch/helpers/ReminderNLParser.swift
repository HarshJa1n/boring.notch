//
//  ReminderNLParser.swift
//  boringNotch
//
//  Pure text -> ReminderDraft parsing. No EventKit, fully unit-testable.
//

import Foundation

struct ReminderParseResult: Equatable {
    var title: String
    var dueDate: Date?
    var hasTime: Bool
    var priority: ReminderPriority
    var recurrenceText: String?

    var chips: [String] {
        var chips: [String] = []
        if let dueDate {
            let formatter = DateFormatter()
            formatter.dateFormat = hasTime ? "EEE d MMM, h:mm a" : "EEE d MMM"
            chips.append(formatter.string(from: dueDate))
        }
        if let recurrenceText {
            chips.append(recurrenceText)
        }
        if priority != .none {
            chips.append(priority.symbol)
        }
        return chips
    }
}

enum ReminderNLParser {
    private static let dataDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    private static let priorityTokens: [(pattern: String, priority: ReminderPriority)] = [
        ("!!!", .high),
        ("!!", .medium),
        ("!", .low)
    ]

    private static let recurrencePatterns: [(regex: NSRegularExpression, label: String)] = {
        let specs: [(String, String)] = [
            (#"(?i)\bevery\s*day\b"#, "Daily"),
            (#"(?i)\bevery\s*weekday\b"#, "Every weekday"),
            (#"(?i)\bevery\s+(\d+)\s*weeks?\b"#, "Every %@ weeks"),
            (#"(?i)\bevery\s*week\b"#, "Weekly"),
            (#"(?i)\bevery\s*month\b"#, "Monthly"),
            (#"(?i)\bevery\s*year\b"#, "Yearly"),
            (#"(?i)\bdaily\b"#, "Daily"),
            (#"(?i)\bweekly\b"#, "Weekly"),
            (#"(?i)\bmonthly\b"#, "Monthly"),
            (#"(?i)\byearly\b"#, "Yearly")
        ]
        return specs.compactMap { pattern, label in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (regex, label)
        }
    }()

    private static let namedTimeTokens: [(pattern: String, hour: Int, minute: Int)] = [
        (#"(?i)\btonight\b"#, 20, 0),
        (#"(?i)\bmorning\b"#, 9, 0),
        (#"(?i)\bnoon\b"#, 12, 0),
        (#"(?i)\beod\b"#, 17, 0)
    ]

    static func parse(_ input: String, referenceDate: Date = Date()) -> ReminderParseResult {
        var remaining = input
        var priority: ReminderPriority = .none
        var recurrenceText: String?
        var dueDate: Date?
        var hasTime = false

        // 1. Priority tokens (only the strongest match wins; strip all occurrences).
        for (pattern, candidate) in priorityTokens {
            if remaining.contains(pattern) {
                priority = candidate
                remaining = remaining.replacingOccurrences(of: pattern, with: "")
                break
            }
        }

        // 2. Recurrence.
        for (regex, label) in recurrencePatterns {
            let range = NSRange(remaining.startIndex..., in: remaining)
            if let match = regex.firstMatch(in: remaining, range: range) {
                if label.contains("%@"), match.numberOfRanges > 1,
                   let numberRange = Range(match.range(at: 1), in: remaining) {
                    recurrenceText = label.replacingOccurrences(of: "%@", with: String(remaining[numberRange]))
                } else {
                    recurrenceText = label
                }
                if let matchRange = Range(match.range, in: remaining) {
                    remaining.removeSubrange(matchRange)
                }
                break
            }
        }

        // 3. Named time-of-day tokens, applied on top of whatever date NSDataDetector finds
        //    (or today, if the detector finds no date at all).
        var namedHour: (hour: Int, minute: Int)?
        for (pattern, hour, minute) in namedTimeTokens {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(remaining.startIndex..., in: remaining)
                if let match = regex.firstMatch(in: remaining, range: range),
                   let matchRange = Range(match.range, in: remaining) {
                    namedHour = (hour, minute)
                    remaining.removeSubrange(matchRange)
                    break
                }
            }
        }

        // 4. NSDataDetector date/time parse. Reject a match that swallows (almost) the whole
        //    remaining string with nothing left over -- that means there'd be no title left,
        //    which is a sign the "date" is actually the reminder's subject (e.g. a bare
        //    "January" reading list item), not a due-date token in a longer sentence.
        if let detector = dataDetector {
            let range = NSRange(remaining.startIndex..., in: remaining)
            if let match = detector.matches(in: remaining, range: range).first,
               let date = match.date,
               let matchRange = Range(match.range, in: remaining) {
                let leftover = remaining.replacingCharacters(in: matchRange, with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !leftover.isEmpty {
                    dueDate = date
                    hasTime = detectorMatchHasTime(match)
                    remaining.removeSubrange(matchRange)
                }
            }
        }

        if let namedHour {
            let base = dueDate ?? referenceDate
            dueDate = Calendar.current.date(
                bySettingHour: namedHour.hour, minute: namedHour.minute, second: 0, of: base
            )
            hasTime = true
        }

        let title = remaining
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ReminderParseResult(
            title: title,
            dueDate: dueDate,
            hasTime: hasTime,
            priority: priority,
            recurrenceText: recurrenceText
        )
    }

    private static func detectorMatchHasTime(_ match: NSTextCheckingResult) -> Bool {
        // NSDataDetector doesn't expose granularity directly; a duration or a match with an
        // associated timeZone/duration component reliably indicates a time was present.
        // Text-level check is the pragmatic signal here.
        guard let date = match.date else { return false }
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return match.duration > 0 || components.hour != 0 || components.minute != 0
    }
}
