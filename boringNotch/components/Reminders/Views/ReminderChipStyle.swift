//
//  ReminderChipStyle.swift
//  boringNotch
//
//  Shared by the inspector and the capture field's pre-save editable chips.
//

import SwiftUI

extension ReminderPriority {
    var next: ReminderPriority {
        switch self {
        case .none: return .low
        case .low: return .medium
        case .medium: return .high
        case .high: return .none
        }
    }
}

extension View {
    func chipStyle(active: Bool, tint: Color = .white) -> some View {
        self
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(active ? tint.opacity(0.25) : Color.white.opacity(0.08))
            )
            .foregroundColor(active ? tint.opacity(0.95) : Color(white: 0.65))
    }
}
