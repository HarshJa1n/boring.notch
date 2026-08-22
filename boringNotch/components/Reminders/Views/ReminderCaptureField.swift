//
//  ReminderCaptureField.swift
//  boringNotch
//
//  Always-on capture field: type, press Return, it appends. No "+" button.
//

import SwiftUI

struct ReminderCaptureField: View {
    @ObservedObject var manager: RemindersManager
    @FocusState.Binding var isFocused: Bool
    @State private var text: String = ""

    private var parseResult: ReminderParseResult? {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return ReminderNLParser.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Type a reminder…", text: $text)
                .textFieldStyle(.plain)
                .font(.caption)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.08))
                )
                .focused($isFocused)
                .onSubmit(commit)

            if let parseResult, !parseResult.chips.isEmpty {
                HStack(spacing: 4) {
                    ForEach(parseResult.chips, id: \.self) { chip in
                        Text(chip)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.white.opacity(0.1)))
                            .foregroundColor(Color(white: 0.75))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(StandardAnimations.interactive, value: parseResult.chips)
            }
        }
    }

    private func commit() {
        guard let result = parseResult, !result.title.isEmpty else { return }
        let draft = ReminderDraft(
            title: result.title,
            dueDate: result.dueDate,
            hasTime: result.hasTime,
            priority: result.priority,
            list: nil,
            notes: nil,
            recurrenceRuleText: result.recurrenceText
        )
        text = ""
        Task {
            await manager.create(draft)
        }
    }
}
