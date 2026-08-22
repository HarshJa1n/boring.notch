//
//  ReminderInspector.swift
//  boringNotch
//
//  Occupies column 3 whenever the capture field is empty and a reminder is selected.
//

import SwiftUI

struct ReminderInspector: View {
    @ObservedObject var manager: RemindersManager
    let reminder: ReminderModel

    @State private var title: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var hasTime: Bool
    @State private var priority: ReminderPriority
    @State private var listID: String

    init(manager: RemindersManager, reminder: ReminderModel) {
        self.manager = manager
        self.reminder = reminder
        _title = State(initialValue: reminder.title)
        _hasDueDate = State(initialValue: reminder.dueDate != nil)
        _dueDate = State(initialValue: reminder.dueDate ?? Date())
        _hasTime = State(initialValue: reminder.hasTime)
        _priority = State(initialValue: reminder.priority)
        _listID = State(initialValue: reminder.list.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Title", text: $title)
                .textFieldStyle(.plain)
                .font(.caption)
                .foregroundColor(.white)
                .onSubmit(save)

            Toggle("Due date", isOn: $hasDueDate)
                .toggleStyle(.checkbox)
                .font(.system(size: 10))

            if hasDueDate {
                DatePicker("", selection: $dueDate, displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date])
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .font(.system(size: 10))

                Toggle("Include time", isOn: $hasTime)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 10))
            }

            Picker("Priority", selection: $priority) {
                Text("None").tag(ReminderPriority.none)
                Text("Low !").tag(ReminderPriority.low)
                Text("Medium !!").tag(ReminderPriority.medium)
                Text("High !!!").tag(ReminderPriority.high)
            }
            .font(.system(size: 10))

            if manager.lists.count > 1 {
                Picker("List", selection: $listID) {
                    ForEach(manager.lists, id: \.id) { list in
                        Text(list.title).tag(list.id)
                    }
                }
                .font(.system(size: 10))
            }

            Spacer(minLength: 0)

            HStack {
                Button("Delete", role: .destructive) {
                    Task { await manager.delete(reminder) }
                }
                .font(.system(size: 10))

                Spacer()

                Button("Save", action: save)
                    .font(.system(size: 10, weight: .semibold))
            }
        }
        .padding(.top, 2)
        .onChange(of: reminder.id) { _, _ in
            title = reminder.title
            hasDueDate = reminder.dueDate != nil
            dueDate = reminder.dueDate ?? Date()
            hasTime = reminder.hasTime
            priority = reminder.priority
            listID = reminder.list.id
        }
    }

    private func save() {
        guard let list = manager.lists.first(where: { $0.id == listID }) ?? Optional(reminder.list) else { return }
        var updated = reminder
        updated.title = title
        updated.dueDate = hasDueDate ? dueDate : nil
        updated.hasTime = hasDueDate && hasTime
        updated.priority = priority
        updated.list = list
        Task { await manager.update(updated) }
    }
}
