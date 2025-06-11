//
//  StompUpstreamMessage.swift
//  Pods
//
//  Created by Ahmad Daneshvar on 5/16/24.
//

import Foundation

/// Represents a message received from the server
public enum StompUpstreamMessage {
    /// Message received as plain text
    case text(message: String, messageId: String, destination: String, headers: [String: String])

    /// Message received as binary data
    case data(data: Data, messageId: String, destination: String, headers: [String: String])
}
