//
//  RemindersManager.swift
//  boringNotch
//

import Defaults
import EventKit
import SwiftUI

@MainActor
final class RemindersManager: ObservableObject {
    static let shared = RemindersManager()

    @Published var reminders: [ReminderModel] = []
    @Published var lists: [CalendarModel] = []
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var isLoading: Bool = false
    @Published var selectedID: String?

    private let service: RemindersServiceProviding = RemindersService()
    private var eventStoreChangedObserver: NSObjectProtocol?
    private var refreshTask: Task<Void, Never>?
    private var refreshDebounce: Task<Void, Never>?

    private init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
        setupEventStoreChangedObserver()
        if authorizationStatus == .fullAccess || authorizationStatus == .authorized {
            Task { await refresh() }
        }
    }

    deinit {
        if let observer = eventStoreChangedObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupEventStoreChangedObserver() {
        eventStoreChangedObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.scheduleDebouncedRefresh()
            }
        }
    }

    private func scheduleDebouncedRefresh() {
        refreshDebounce?.cancel()
        refreshDebounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    func requestAccess() async {
        do {
            let granted = try await service.requestAccess()
            authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
            if granted {
                await refresh()
            }
        } catch {
            authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
        }
    }

    func refresh() async {
        guard authorizationStatus == .fullAccess || authorizationStatus == .authorized else { return }
        isLoading = true
        defer { isLoading = false }

        lists = await service.lists()

        let selectedLists = Defaults[.reminderListSelection]
        let listIDs: Set<String>
        switch selectedLists {
        case .all:
            listIDs = []
        case .selected(let ids):
            listIDs = ids
        }

        let query = ReminderQuery(
            listIDs: listIDs,
            window: Defaults[.reminderTimeWindow],
            includeCompleted: Defaults[.showCompletedReminders]
        )
        reminders = await service.reminders(matching: query).sorted(by: Self.sortOrder)
    }

    private static func sortOrder(_ lhs: ReminderModel, _ rhs: ReminderModel) -> Bool {
        if lhs.isCompleted != rhs.isCompleted {
            return !lhs.isCompleted
        }
        switch (lhs.dueDate, rhs.dueDate) {
        case (nil, nil): return creationOrder(lhs, rhs)
        case (nil, _): return false
        case (_, nil): return true
        case let (l?, r?): return l == r ? creationOrder(lhs, rhs) : l < r
        }
    }

    private static func creationOrder(_ lhs: ReminderModel, _ rhs: ReminderModel) -> Bool {
        switch (lhs.creationDate, rhs.creationDate) {
        case let (l?, r?): return l < r
        case (nil, nil): return lhs.title < rhs.title
        case (nil, _): return false
        case (_, nil): return true
        }
    }

    // MARK: - Focus / Upcoming derivations for the three-column layout

    var focusItems: [ReminderModel] {
        let calendar = Calendar.current
        return reminders.filter { reminder in
            guard !reminder.isCompleted else { return false }
            guard let due = reminder.dueDate else { return false }
            return due < calendar.startOfDay(for: Date().addingTimeInterval(86400))
        }
    }

    var upcomingSections: [(day: Date, items: [ReminderModel])] {
        let calendar = Calendar.current
        let focusIDs = Set(focusItems.map(\.id))
        let upcoming = reminders.filter { !focusIDs.contains($0.id) }

        let grouped = Dictionary(grouping: upcoming) { reminder -> Date in
            guard let due = reminder.dueDate else { return .distantFuture }
            return calendar.startOfDay(for: due)
        }

        return grouped.keys.sorted().map { day in
            (day: day, items: (grouped[day] ?? []).sorted(by: Self.sortOrder))
        }
    }

    // MARK: - Mutations

    func toggleCompleted(_ reminder: ReminderModel) async {
        guard let index = reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        let newValue = !reminders[index].isCompleted
        reminders[index].isCompleted = newValue

        do {
            try await service.setCompleted(id: reminder.id, completed: newValue)
        } catch {
            reminders[index].isCompleted = !newValue
        }
    }

    func create(_ draft: ReminderDraft) async {
        let defaultListID = Defaults[.defaultReminderList]
        let defaultList = lists.first { $0.id == defaultListID } ?? lists.first
        do {
            let created = try await service.create(draft, defaultList: defaultList)
            reminders.append(created)
            reminders.sort(by: Self.sortOrder)
        } catch {
            // Surfaced via isLoading/authorizationStatus state; a toast is added in the UI layer.
        }
    }

    func update(_ reminder: ReminderModel) async {
        guard let index = reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        let previous = reminders[index]
        reminders[index] = reminder
        do {
            try await service.update(reminder)
        } catch {
            reminders[index] = previous
        }
    }

    func delete(_ reminder: ReminderModel) async {
        guard let index = reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        let removed = reminders.remove(at: index)
        do {
            try await service.delete(id: reminder.id)
        } catch {
            reminders.insert(removed, at: min(index, reminders.count))
        }
    }
}
