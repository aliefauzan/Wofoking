//
//  HRMessage.swift
//  Wofoking — Load Away  (SHARED: add to BOTH iOS and watchOS targets)
//
//  Wire contract for live heart-rate messages sent Watch → iPhone over
//  WatchConnectivity.
//

import Foundation

enum HRKey {
    static let bpm = "bpm"           // Double — beats per minute
    static let timestamp = "ts"      // TimeInterval — sample time
    static let streaming = "stream"  // Bool — watch workout active
}
