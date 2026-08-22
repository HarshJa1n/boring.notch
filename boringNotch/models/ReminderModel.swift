//
//  ReminderModel.swift
//  boringNotch
//

import Defaults
import Foundation

enum ReminderPriority: Int, Equatable, CaseIterable {
    case none = 0
    case low = 9
    case medium = 5
    case high = 1

    /// Maps from EKReminder.priority (0 = none, 1-4 = high, 5 = medium, 6-9 = low).
    init(ekPriority: Int) {
        switch ekPriority {
        case 1...4: self = .high
        case 5: self = .medium
        case 6...9: self = .low
        default: self = .none
        }
    }

    var symbol: String {
        switch self {
        case .none: return ""
        case .low: return "!"
        case .medium: return "!!"
        case .high: return "!!!"
        }
    }
}

struct RecurrenceSummary: Equatable {
    let text: String
}

struct ReminderModel: Identifiable, Equatable {
    let id: String
    var title: String
    var notes: String?
    var dueDate: Date?
    var hasTime: Bool
    var isCompleted: Bool
    var priority: ReminderPriority
    var list: CalendarModel
    var recurrence: RecurrenceSummary?
    var creationDate: Date?
}

struct ReminderDraft {
    var title: String
    var dueDate: Date?
    var hasTime: Bool
    var priority: ReminderPriority
    var list: CalendarModel?
    var notes: String?
    var recurrenceRuleText: String?
}

enum ReminderTimeWindow: String, CaseIterable, Defaults.Serializable {
    case today
    case tomorrow
    case next3Days
    case thisWeek
    case next2Weeks
    case month
    case all

    var days: Int? {
        switch self {
        case .today: return 1
        case .tomorrow: return 2
        case .next3Days: return 3
        case .thisWeek: return 7
        case .next2Weeks: return 14
        case .month: return 31
        case .all: return nil
        }
    }

    var label: String {
        switch self {
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .next3Days: return "Next 3 Days"
        case .thisWeek: return "This Week"
        case .next2Weeks: return "Next 2 Weeks"
        case .month: return "This Month"
        case .all: return "All"
        }
    }
}

struct ReminderQuery {
    var listIDs: Set<String>
    var window: ReminderTimeWindow
    var includeCompleted: Bool
}
