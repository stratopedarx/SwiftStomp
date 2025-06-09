//
//  StompAckMode.swift
//  Pods
//
//  Created by Ahmad Daneshvar on 5/16/24.
//

/// Defines acknowledgment modes for STOMP subscriptions
/// [STOMP SUBSCRIBE ack Header](https://stomp.github.io/stomp-specification-1.2.html#SUBSCRIBE_ack_Header)
public enum StompAckMode: String {
    /// Similar to `client`, but acknowledgments are not cumulative
    case clientIndividual = "client-individual"

    /// The client must explicitly acknowledge messages by sending ACK frames
    case client

    /// Messages are automatically considered acknowledged once sent by the server
    case auto
}
