//
//  StompResponseFrame.swift
//  Pods
//
//  Created by Ahmad Daneshvar on 5/16/24.
//

/// Defines STOMP response frame types received from the server
/// [Server Frames](https://stomp.github.io/stomp-specification-1.2.html#Server_Frames)
public enum StompResponseFrame: String {
    case connected = "CONNECTED"
    case message = "MESSAGE"
    case receipt = "RECEIPT"
    case error = "ERROR"
}
