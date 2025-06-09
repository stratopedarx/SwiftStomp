//
//  StompRequestFrame.swift
//  Pods
//
//  Created by Ahmad Daneshvar on 5/16/24.
//

/// Defines STOMP protocol request frame commands sent from client to server
/// [STOMP Client Frames](https://stomp.github.io/stomp-specification-1.2.html#Client_Frames)
public enum StompRequestFrame: String {
    case connect = "CONNECT"
    case send = "SEND"
    case subscribe = "SUBSCRIBE"
    case unsubscribe = "UNSUBSCRIBE"
    case begin = "BEGIN"
    case commit = "COMMIT"
    case abort = "ABORT"
    case ack = "ACK"
    case nack = "NACK"
    case disconnect = "DISCONNECT"
}
