//
//  ReminderInspector.swift
//  boringNotch
//
//  Occupies column 3 whenever the capture field is empty and a reminder is selected.
//  Minimal tap-to-cycle controls instead of native dropdowns/pickers -- there isn't
//  room in a 200pt-wide column for a combo box (or a native DatePicker's spin-arrow
//  field cluster) to look like anything but a mistake.
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
                dateStepperRow
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
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

                Spacer(minLength: 0)

                Button {
                    Task { await manager.delete(reminder) }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
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

    // Tap cycles: no date -> today; tapping again while a date is set clears it. The
    // day itself is then adjusted with the stepper below rather than a native DatePicker.
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

    // Compact day-stepper instead of a native DatePicker, which renders as a chunky
    // multi-field spin-arrow control that dwarfs everything else in a 200pt column.
    private var dateStepperRow: some View {
        HStack(spacing: 6) {
            Button { adjustDate(by: -1) } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)

            Text(formattedDate)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white)
                .frame(minWidth: 78)

            Button { adjustDate(by: 1) } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)

            if hasTime {
                Stepper("", onIncrement: { adjustTime(by: 30) }, onDecrement: { adjustTime(by: -30) })
                    .labelsHidden()
                    .scaleEffect(0.7)
            }
        }
        .foregroundColor(Color(white: 0.7))
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = hasTime ? "MMM d, h:mm a" : "MMM d, yyyy"
        return formatter.string(from: dueDate)
    }

    private func adjustDate(by days: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: days, to: dueDate) {
            dueDate = newDate
            save()
        }
    }

    private func adjustTime(by minutes: Int) {
        if let newDate = Calendar.current.date(byAdding: .minute, value: minutes, to: dueDate) {
            dueDate = newDate
            save()
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
