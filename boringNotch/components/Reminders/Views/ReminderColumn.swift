//
//  ReminderColumn.swift
//  boringNotch
//

import SwiftUI

struct ReminderColumn<Content: View>: View {
    let title: String
    let count: Int?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(white: 0.6))
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color(white: 0.6))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    content()
                }
            }
            .scrollIndicators(.never)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct ReminderColumnDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(white: 0.18))
            .frame(width: 1)
    }
}
