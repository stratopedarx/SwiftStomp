//
//  StompErrorType.swift
//  Pods
//
//  Created by Ahmad Daneshvar on 5/16/24.
//

/// Classifies the source/type of error in the STOMP pipeline
public enum StompErrorType {
    /// WebSocket-related error
    case fromSocket

    /// STOMP protocol-level error
    case fromStomp
}
