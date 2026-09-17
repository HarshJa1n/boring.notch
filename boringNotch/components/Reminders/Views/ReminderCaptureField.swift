//
//  ReminderCaptureField.swift
//  boringNotch
//
//  Always-on capture field: type, press Return, it appends. No "+" button.
//  Parsed date/time/priority are shown as editable chips before committing, so a
//  misread date or an unwanted default can be fixed before the reminder is created.
//

import SwiftUI

struct ReminderCaptureField: View {
    @ObservedObject var manager: RemindersManager
    @State private var text: String = ""

    @State private var dueDateOverride: Date?
    // The specific parsed date the user cleared, so a *different* date parsed from further
    // typing shows up instead of staying suppressed for the rest of the draft (a plain
    // sticky "cleared" flag couldn't tell those two situations apart).
    @State private var clearedParsedDate: Date?
    @State private var hasTimeOverride: Bool?
    @State private var priorityOverride: ReminderPriority?

    private var parseResult: ReminderParseResult? {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return ReminderNLParser.parse(text)
    }

    private var effectiveDueDate: Date? {
        if dueDateOverride == nil, let cleared = clearedParsedDate, cleared == parseResult?.dueDate {
            return nil
        }
        return dueDateOverride ?? parseResult?.dueDate
    }

    private var effectiveHasTime: Bool {
        hasTimeOverride ?? parseResult?.hasTime ?? false
    }

    private var effectivePriority: ReminderPriority {
        priorityOverride ?? parseResult?.priority ?? .none
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            InlineTextField(text: $text, placeholder: "Type a reminder…", autoFocus: true, onSubmit: commit)
                .frame(height: 26)

            if parseResult != nil {
                HStack(spacing: 6) {
                    dueDateChip
                    if effectiveDueDate != nil {
                        timeChip
                    }
                    Spacer(minLength: 0)
                    priorityChip
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(StandardAnimations.interactive, value: parseResult?.chips)

                if let recurrence = parseResult?.recurrenceText {
                    Text(recurrence)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Color(white: 0.6))
                }
            }
        }
    }

    private var dueDateChip: some View {
        Button {
            if effectiveDueDate != nil {
                clearedParsedDate = parseResult?.dueDate
                dueDateOverride = nil
            } else {
                clearedParsedDate = nil
                dueDateOverride = Date()
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "calendar")
                Text(effectiveDueDate.map(chipDateLabel) ?? "No date")
            }
            .chipStyle(active: effectiveDueDate != nil)
        }
        .buttonStyle(.plain)
    }

    private var timeChip: some View {
        Button {
            hasTimeOverride = !effectiveHasTime
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "clock")
                Text(effectiveHasTime ? "Time" : "All-day")
            }
            .chipStyle(active: effectiveHasTime)
        }
        .buttonStyle(.plain)
    }

    private var priorityChip: some View {
        Button {
            priorityOverride = effectivePriority.next
        } label: {
            Text(effectivePriority == .none ? "!" : effectivePriority.symbol)
                .chipStyle(active: effectivePriority != .none, tint: .orange)
        }
        .buttonStyle(.plain)
    }

    private func chipDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = effectiveHasTime ? "EEE d MMM, h:mm a" : "EEE d MMM"
        return formatter.string(from: date)
    }

    private func commit() {
        guard let result = parseResult, !result.title.isEmpty else { return }
        let draft = ReminderDraft(
            title: result.title,
            dueDate: effectiveDueDate,
            hasTime: effectiveHasTime,
            priority: effectivePriority,
            list: nil,
            notes: nil,
            recurrenceRuleText: result.recurrenceText
        )
        text = ""
        dueDateOverride = nil
        clearedParsedDate = nil
        hasTimeOverride = nil
        priorityOverride = nil
        Task {
            await manager.create(draft)
        }
    }
}
