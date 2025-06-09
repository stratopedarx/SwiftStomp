//
//  StompUpstreamEvent.swift
//  Pods
//
//  Created by Ahmad Daneshvar on 5/16/24.
//

/// Defines the types of upstream events passed from the STOMP client to the user layer
public enum StompUpstreamEvent {
    /// Fired upon successful connection with connection type detail
    case connected(type: StompConnectType)

    /// Fired upon disconnection with disconnection reason detail
    case disconnected(type: StompDisconnectType)

    /// Fired when an error occurs
    case error(error: StompError)
}
