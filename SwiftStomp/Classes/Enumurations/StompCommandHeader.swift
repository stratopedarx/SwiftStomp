//
//  StompCommandHeader.swift
//  Pods
//
//  Created by Ahmad Daneshvar on 5/16/24.
//

/// Common headers used in STOMP communication frames
/// [STOMP Headers](https://stomp.github.io/stomp-specification-1.2.html#Frames_and_Headers)
public enum StompCommonHeader: String {
    case id
    case host
    case receipt
    case session
    case receiptId = "receipt-id"
    case messageId = "message-id"
    case destination
    case contentLength = "content-length"
    case contentType = "content-type"
    case ack
    case transaction
    case subscription
    case disconnected
    case heartBeat = "heart-beat"
    case acceptVersion = "accept-version"
    case message
}
