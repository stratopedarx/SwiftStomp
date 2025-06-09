//
//  StompConnectType.swift
//  Pods
//
//  Created by Ahmad Daneshvar on 5/16/24.
//

/// Identifies the type of the connection
public enum StompConnectType {
    /// Connected to socket
    case toSocketEndpoint

    /// Connected to stomp
    case toStomp
}
