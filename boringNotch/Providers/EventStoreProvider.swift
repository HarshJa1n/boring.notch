//
//  EventStoreProvider.swift
//  boringNotch
//

import Foundation
@preconcurrency import EventKit

/// Single shared EKEventStore so calendar and reminder services observe
/// and mutate the same in-memory object graph. Two separate stores would
/// each cache their own EKReminder instances, so a completion toggle made
/// through one wouldn't be reflected by the other until a full refetch.
enum EventStoreProvider {
    static let shared = EKEventStore()
}
