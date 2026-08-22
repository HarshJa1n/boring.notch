//
//  RemindersSettingsView.swift
//  boringNotch
//

import Defaults
import EventKit
import SwiftUI

struct RemindersSettings: View {
    @ObservedObject private var remindersManager = RemindersManager.shared
    @Default(.enableRemindersTab) var enableRemindersTab
    @Default(.reminderTimeWindow) var reminderTimeWindow
    @Default(.showCompletedReminders) var showCompletedReminders
    @Default(.defaultReminderList) var defaultReminderList
    @Default(.openRemindersTabByDefault) var openRemindersTabByDefault

    var body: some View {
        Form {
            Defaults.Toggle(key: .enableRemindersTab) {
                Text("Show Reminders tab")
            }
            Defaults.Toggle(key: .showCompletedReminders) {
                Text("Show completed reminders")
            }
            Defaults.Toggle(key: .openRemindersTabByDefault) {
                Text("Open notch to Reminders by default")
            }

            Picker("Upcoming window", selection: $reminderTimeWindow) {
                ForEach(ReminderTimeWindow.allCases, id: \.self) { window in
                    Text(window.label).tag(window)
                }
            }

            if !remindersManager.lists.isEmpty {
                Picker("Default list for new reminders", selection: Binding(
                    get: { defaultReminderList ?? remindersManager.lists.first?.id ?? "" },
                    set: { defaultReminderList = $0 }
                )) {
                    ForEach(remindersManager.lists, id: \.id) { list in
                        Text(list.title).tag(list.id)
                    }
                }
            }

            Section(header: Text("Quick add syntax")) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Type dates naturally: \"tomorrow 3pm\", \"next friday\", \"in 2 hours\"")
                    Text("Recurrence: \"every day\", \"every monday\", \"every 2 weeks\"")
                    Text("Priority: ! low, !! medium, !!! high")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Section(header: Text("Access")) {
                if remindersManager.authorizationStatus != .fullAccess {
                    Text("Reminders access is denied. Please enable it in System Settings.")
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("Open Reminders Settings") {
                        if let settingsURL = URL(
                            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
                        ) {
                            NSWorkspace.shared.open(settingsURL)
                        }
                    }
                } else {
                    Text("Reminders access granted (\(remindersManager.lists.count) lists)")
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            Task { await remindersManager.refresh() }
        }
    }
}

#Preview {
    RemindersSettings()
}
