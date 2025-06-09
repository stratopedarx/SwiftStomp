//
//  StompConnectionStatus.swift
//  Pods
//
//  Created by Ahmad Daneshvar on 5/16/24.
//

/// The state of the STOMP/WebSocket connection
public enum StompConnectionStatus {
    /// Connecting to the server...
    case connecting

    /// Socket is disconnected
    case socketDisconnected

    /// Scoket is connected but STOMP as sub-protocol is not connected yet
    case socketConnected

    /// Both socket and STOMP is connected. Ready for messaging...
    case fullyConnected
}
