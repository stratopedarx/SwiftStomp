//
//  StompError.swift
//  Pods
//
//  Created by Ahmad Daneshvar on 5/16/24.
//

/// A structured STOMP-specific error type with metadata
public struct StompError: Error {
    public let localizedDescription: String
    public let receiptId: String?
    public let type: StompErrorType

    /// Creates a new StompError with specific parameters
    init(type: StompErrorType, receiptId: String?, localizedDescription: String) {
        self.localizedDescription = localizedDescription
        self.receiptId = receiptId
        self.type = type
    }

    /// Wraps a generic Swift `Error` into a StompError
    init(error: Error, type: StompErrorType) {
        self.localizedDescription = error.localizedDescription
        self.receiptId = nil
        self.type = type
    }
}

// MARK: - CustomStringConvertible

extension StompError: CustomStringConvertible {
    public var description: String {
        "StompError(\(type)) [receiptId: \(String(describing: receiptId))]: \(localizedDescription)"
    }
}
