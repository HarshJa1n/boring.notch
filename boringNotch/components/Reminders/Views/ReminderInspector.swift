//
//  ReminderInspector.swift
//  boringNotch
//
//  Occupies column 3 whenever the capture field is empty and a reminder is selected.
//  Minimal tap-to-cycle controls instead of native dropdowns/pickers -- there isn't
//  room in a 200pt-wide column for a combo box to look like anything but a mistake.
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
        VStack(alignment: .leading, spacing: 8) {
            InlineTextField(text: $title, placeholder: "Title", onSubmit: save)
                .frame(height: 20)

            HStack(spacing: 6) {
                dueDateChip
                if hasDueDate {
                    timeChip
                }
                Spacer(minLength: 0)
                priorityChip
            }

            if hasDueDate {
                DatePicker("", selection: $dueDate, displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date])
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .font(.system(size: 10))
                    .fixedSize()
                    .onChange(of: dueDate) { _, _ in save() }
            }

            if manager.lists.count > 1 {
                listRow
            }

            Spacer(minLength: 0)

            Button {
                Task { await manager.delete(reminder) }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "trash")
                    Text("Delete")
                }
                .font(.system(size: 10))
                .foregroundColor(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 2)
        .onDisappear(perform: save)
        .onChange(of: reminder.id) { _, _ in
            title = reminder.title
            hasDueDate = reminder.dueDate != nil
            dueDate = reminder.dueDate ?? Date()
            hasTime = reminder.hasTime
            priority = reminder.priority
            listID = reminder.list.id
        }
    }

    // Tap cycles: no date -> today -> tomorrow's date stays editable via the DatePicker
    // that appears once a date exists; tapping again while a date is set clears it.
    private var dueDateChip: some View {
        Button {
            hasDueDate.toggle()
            if hasDueDate && dueDate < Date() {
                dueDate = Date()
            }
            save()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "calendar")
                Text(hasDueDate ? "Due" : "No date")
            }
            .chipStyle(active: hasDueDate)
        }
        .buttonStyle(.plain)
    }

    private var timeChip: some View {
        Button {
            hasTime.toggle()
            save()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "clock")
                Text(hasTime ? "Time" : "All-day")
            }
            .chipStyle(active: hasTime)
        }
        .buttonStyle(.plain)
    }

    // Single button, tap-tap-tap cycles priority: none -> low -> medium -> high -> none.
    private var priorityChip: some View {
        Button {
            priority = priority.next
            save()
        } label: {
            Text(priority == .none ? "!" : priority.symbol)
                .chipStyle(active: priority != .none, tint: .orange)
        }
        .buttonStyle(.plain)
    }

    private var listRow: some View {
        HStack(spacing: 5) {
            ForEach(manager.lists, id: \.id) { list in
                Button {
                    listID = list.id
                    save()
                } label: {
                    Circle()
                        .fill(Color(list.color))
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white, lineWidth: listID == list.id ? 1.5 : 0)
                                .padding(-2)
                        )
                }
                .buttonStyle(.plain)
                .help(list.title)
            }
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

