//
//  ReminderRow.swift
//  boringNotch
//

import SwiftUI

struct ReminderRow: View {
    let reminder: ReminderModel
    let isSelected: Bool
    let onToggle: () -> Void
    let onSelect: () -> Void
    let onDelete: () -> Void

    private var isOverdue: Bool {
        guard let due = reminder.dueDate, !reminder.isCompleted else { return false }
        return due < Date()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            ReminderToggle(
                isOn: Binding(get: { reminder.isCompleted }, set: { _ in onToggle() }),
                color: Color(reminder.list.color)
            )
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(reminder.title)
                    .font(.caption)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .strikethrough(reminder.isCompleted, color: Color(white: 0.6))

                if let due = reminder.dueDate {
                    Text(due, style: reminder.hasTime ? .time : .date)
                        .font(.system(size: 9))
                        .foregroundColor(isOverdue ? .red.opacity(0.85) : Color(white: 0.6))
                }
            }

            Spacer(minLength: 0)

            if reminder.priority != .none {
                Text(reminder.priority.symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.orange.opacity(0.85))
            }
        }
        .opacity(reminder.isCompleted ? 0.4 : 1.0)
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? Color.white.opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button(reminder.isCompleted ? "Mark Incomplete" : "Mark Complete", action: onToggle)
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}

