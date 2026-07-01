//
//  HRMessage.swift
//  Wofoking — Load Away  (SHARED: add to BOTH iOS and watchOS targets)
//
//  Wire contract for live heart-rate messages sent Watch → iPhone over
//  WatchConnectivity.
//

import Foundation

// nonisolated: under SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor these constants
// would be MainActor-isolated, but the WCSession delegate reads them from
// nonisolated callbacks. Plain Sendable Strings — safe to mark nonisolated.
enum HRKey {
    nonisolated static let bpm = "bpm"           // Double — beats per minute
    nonisolated static let timestamp = "ts"      // TimeInterval — sample time
    nonisolated static let streaming = "stream"  // Bool — watch workout active
}
