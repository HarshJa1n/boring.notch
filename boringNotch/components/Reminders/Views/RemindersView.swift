//
//  RemindersView.swift
//  boringNotch
//
//  Three-column Reminders tab: Focus | Upcoming | Capture & Inspector.
//

import EventKit
import SwiftUI
import SwiftUIIntrospect

struct RemindersView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var manager = RemindersManager.shared
    @ObservedObject var sharing = SharingStateManager.shared
    @FocusState private var isCaptureFocused: Bool
    @State private var hostWindow: NSWindow?

    private var selectedReminder: ReminderModel? {
        guard let id = manager.selectedID else { return nil }
        return manager.reminders.first { $0.id == id }
    }

    var body: some View {
        Group {
            if manager.authorizationStatus == .fullAccess || manager.authorizationStatus == .authorized {
                mainLayout
            } else {
                RemindersPermissionPrompt {
                    Task { await manager.requestAccess() }
                }
            }
        }
        .introspect(.window, on: .macOS(.v14, .v15)) { window in
            hostWindow = window
        }
        .onAppear {
            Task { await manager.refresh() }
            DispatchQueue.main.async {
                isCaptureFocused = true
            }
        }
        .onDisappear {
            vm.isHoveringCalendar = false
        }
        .onChange(of: isCaptureFocused) { _, focused in
            if focused {
                sharing.beginInteraction()
            } else {
                sharing.endInteraction()
            }
        }
        // The notch panel is deliberately non-key so it never steals focus from whatever
        // app the user is using. A text field can't accept keystrokes in a non-key window,
        // so while any Reminders text entry is active we flip the panel key just for that
        // window (it's a nonactivating panel, so this doesn't foreground the app), then
        // hand key status back the moment entry ends.
        .onChange(of: sharing.preventNotchClose) { _, wantsKey in
            guard let panel = hostWindow as? BoringNotchSkyLightWindow else { return }
            if wantsKey {
                panel.wantsKeyForTextInput = true
                panel.makeKey()
            } else {
                panel.resignKey()
                panel.wantsKeyForTextInput = false
            }
        }
        // Scrolling inside these columns fires the same scroll-wheel monitor used to
        // detect the swipe-up-to-close gesture (see ContentView.handleUpGesture); the
        // calendar view on the Home tab guards it the same way with isHoveringCalendar.
        .onHover { hovering in
            vm.isHoveringCalendar = hovering
        }
    }

    private var mainLayout: some View {
        HStack(spacing: 0) {
            ReminderColumn(title: "Today", count: manager.focusItems.count) {
                if manager.focusItems.isEmpty {
                    RemindersEmptyState(message: "Nothing due today")
                        .frame(height: 100)
                } else {
                    ForEach(manager.focusItems) { reminder in
                        ReminderRow(
                            reminder: reminder,
                            isSelected: manager.selectedID == reminder.id,
                            onToggle: { Task { await manager.toggleCompleted(reminder) } },
                            onSelect: { manager.selectedID = reminder.id },
                            onDelete: { Task { await manager.delete(reminder) } }
                        )
                    }
                }
            }
            .padding(.trailing, 6)

            ReminderColumnDivider()

            ReminderColumn(title: "Upcoming", count: nil) {
                if manager.upcomingSections.isEmpty {
                    RemindersEmptyState(message: "Nothing upcoming")
                        .frame(height: 100)
                } else {
                    ForEach(manager.upcomingSections, id: \.day) { section in
                        Text(sectionLabel(section.day))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Color(white: 0.5))
                            .padding(.top, 4)
                            .padding(.horizontal, 6)
                        ForEach(section.items) { reminder in
                            ReminderRow(
                                reminder: reminder,
                                isSelected: manager.selectedID == reminder.id,
                                onToggle: { Task { await manager.toggleCompleted(reminder) } },
                                onSelect: { manager.selectedID = reminder.id },
                                onDelete: { Task { await manager.delete(reminder) } }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 6)

            ReminderColumnDivider()

            VStack(alignment: .leading, spacing: 8) {
                ReminderCaptureField(manager: manager, isFocused: $isCaptureFocused)

                Divider().background(Color(white: 0.18))

                if let selectedReminder {
                    ReminderInspector(manager: manager, reminder: selectedReminder)
                } else {
                    RemindersEmptyState(message: "Select a reminder to edit")
                }
            }
            .padding(.leading, 6)
            .frame(width: 200)
        }
        .padding(.horizontal, 4)
    }

    private func sectionLabel(_ day: Date) -> String {
        if day == .distantFuture { return "No Date" }
        let calendar = Calendar.current
        if calendar.isDateInTomorrow(day) { return "Tomorrow" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: day)
    }
}
