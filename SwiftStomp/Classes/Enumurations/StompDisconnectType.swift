//
//  StompDisconnectType.swift
//  Pods
//
//  Created by Ahmad Daneshvar on 5/16/24.
//

/// Identifies the type of the disconnection
public enum StompDisconnectType {
    /// Socket disconnected. Disconnect completed
    case fromSocket

    /// Client disconnected from stomp but socket is still connected
    case fromStomp
}
