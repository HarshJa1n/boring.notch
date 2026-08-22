//
//  RemindersEmptyState.swift
//  boringNotch
//

import SwiftUI

struct RemindersEmptyState: View {
    let message: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "checklist")
                .font(.title3)
                .foregroundColor(Color(white: 0.5))
            Text(message)
                .font(.caption2)
                .foregroundColor(Color(white: 0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

struct RemindersPermissionPrompt: View {
    let onRequestAccess: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(.title2)
                .foregroundColor(Color(white: 0.6))
            Text("Reminders access needed")
                .font(.caption)
                .foregroundColor(.white)
            Button("Grant Access", action: onRequestAccess)
                .font(.caption2)
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
                    NSWorkspace.shared.open(url)
                }
            }
            .font(.caption2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
