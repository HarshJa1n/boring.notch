//
//  RemindersServiceProviding.swift
//  boringNotch
//

import Foundation
@preconcurrency import EventKit

protocol RemindersServiceProviding {
    func requestAccess() async throws -> Bool
    func lists() async -> [CalendarModel]
    func reminders(matching query: ReminderQuery) async -> [ReminderModel]
    func create(_ draft: ReminderDraft, defaultList: CalendarModel?) async throws -> ReminderModel
    func update(_ reminder: ReminderModel) async throws
    func setCompleted(id: String, completed: Bool) async throws
    func delete(id: String) async throws
}

final class RemindersService: RemindersServiceProviding {
    private let store = EventStoreProvider.shared

    @MainActor
    func requestAccess() async throws -> Bool {
        if #available(macOS 14.0, *) {
            return try await store.requestFullAccessToReminders()
        } else {
            return try await store.requestAccess(to: .reminder)
        }
    }

    private func hasAccess() -> Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if #available(macOS 14.0, *) {
            return status == .fullAccess
        } else {
            return status == .authorized
        }
    }

    func lists() async -> [CalendarModel] {
        guard hasAccess() else { return [] }
        return store.calendars(for: .reminder).map { CalendarModel(from: $0) }
    }

    func reminders(matching query: ReminderQuery) async -> [ReminderModel] {
        guard hasAccess() else { return [] }

        let allLists = store.calendars(for: .reminder)
        let targetLists = query.listIDs.isEmpty
            ? allLists
            : allLists.filter { query.listIDs.contains($0.calendarIdentifier) }

        guard !targetLists.isEmpty else { return [] }

        let now = Date()
        let windowEnd: Date? = query.window.days.flatMap {
            Calendar.current.date(byAdding: .day, value: $0, to: now)
        }

        return await withCheckedContinuation { continuation in
            let predicate = self.store.predicateForReminders(in: targetLists)
            self.store.fetchReminders(matching: predicate) { ekReminders in
                let filtered = (ekReminders ?? []).filter { reminder in
                    if reminder.isCompleted && !query.includeCompleted {
                        return false
                    }
                    guard let windowEnd else { return true }
                    guard let due = reminder.dueDateComponents?.date else {
                        // Undated reminders always show; they aren't tied to the window.
                        return true
                    }
                    return due <= windowEnd
                }
                let models = filtered.compactMap { ReminderModel(from: $0) }
                continuation.resume(returning: models)
            }
        }
    }

    func create(_ draft: ReminderDraft, defaultList: CalendarModel?) async throws -> ReminderModel {
        guard hasAccess() else { throw RemindersServiceError.noAccess }

        let ekReminder = EKReminder(eventStore: store)
        ekReminder.title = draft.title
        ekReminder.notes = draft.notes
        ekReminder.priority = draft.priority.rawValue

        if let dueDate = draft.dueDate {
            var components: Set<Calendar.Component> = [.year, .month, .day]
            if draft.hasTime {
                components.formUnion([.hour, .minute])
            }
            ekReminder.dueDateComponents = Calendar.current.dateComponents(components, from: dueDate)
            if draft.hasTime {
                ekReminder.addAlarm(EKAlarm(absoluteDate: dueDate))
            }
        }

        let targetList = draft.list ?? defaultList
        guard let ekCalendar = store.calendars(for: .reminder).first(where: { $0.calendarIdentifier == targetList?.id })
            ?? store.defaultCalendarForNewReminders()
            ?? store.calendars(for: .reminder).first
        else {
            throw RemindersServiceError.noList
        }
        ekReminder.calendar = ekCalendar

        try store.save(ekReminder, commit: true)

        guard let model = ReminderModel(from: ekReminder) else {
            throw RemindersServiceError.saveFailed
        }
        return model
    }

    func update(_ reminder: ReminderModel) async throws {
        guard hasAccess() else { throw RemindersServiceError.noAccess }
        guard let ekReminder = store.calendarItem(withIdentifier: reminder.id) as? EKReminder else {
            throw RemindersServiceError.notFound
        }

        ekReminder.title = reminder.title
        ekReminder.notes = reminder.notes
        ekReminder.priority = reminder.priority.rawValue
        ekReminder.isCompleted = reminder.isCompleted

        if let dueDate = reminder.dueDate {
            var components: Set<Calendar.Component> = [.year, .month, .day]
            if reminder.hasTime {
                components.formUnion([.hour, .minute])
            }
            ekReminder.dueDateComponents = Calendar.current.dateComponents(components, from: dueDate)
        } else {
            ekReminder.dueDateComponents = nil
        }

        if let ekList = store.calendars(for: .reminder).first(where: { $0.calendarIdentifier == reminder.list.id }) {
            ekReminder.calendar = ekList
        }

        try store.save(ekReminder, commit: true)
    }

    func setCompleted(id: String, completed: Bool) async throws {
        guard let ekReminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw RemindersServiceError.notFound
        }
        ekReminder.isCompleted = completed
        try store.save(ekReminder, commit: true)
    }

    func delete(id: String) async throws {
        guard let ekReminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw RemindersServiceError.notFound
        }
        try store.remove(ekReminder, commit: true)
    }
}

enum RemindersServiceError: Error {
    case noAccess
    case noList
    case notFound
    case saveFailed
}

// MARK: - Model conversion

extension ReminderModel {
    init?(from reminder: EKReminder) {
        guard let calendar = reminder.calendar else { return nil }

        let dueDate = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
        let hasTime = reminder.dueDateComponents?.hour != nil

        self.init(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            notes: reminder.notes,
            dueDate: dueDate,
            hasTime: hasTime,
            isCompleted: reminder.isCompleted,
            priority: .init(ekPriority: reminder.priority),
            list: .init(from: calendar),
            recurrence: reminder.hasRecurrenceRules ? RecurrenceSummary(text: "Repeats") : nil,
            creationDate: reminder.creationDate
        )
    }
}
