//
//  StompFrame.swift
//  Pods
//
//  Created by Ahmad Daneshvar on 5/16/24.
//

import Foundation

/// Represents a generic STOMP frame with a command, headers and body.
///
/// This structure is designed to encapsulate the full definition of a STOMP frame,
/// supporting both string and data payloads, as well as encoding from `Encodable` types.
/// [STOMP Frames](https://stomp.github.io/stomp-specification-1.2.html#STOMP_Frames)
struct StompFrame<T: RawRepresentable> where T.RawValue == String {
    /// The name of the STOMP frame (e.g., SEND, CONNECT, etc.)
    var name: T!
    var headers = [String: String]()
    var body: Any = ""

    /// Initializes a basic frame with a name and optional headers
    init(name: T, headers: [String: String] = [:]) {
        self.name = name
        self.headers = headers
    }

    /// Initializes a frame with an `Encodable` body which is JSON-encoded
    init<X: Encodable>(name: T, headers: [String: String] = [:], encodableBody: X, jsonDateEncodingStrategy: JSONEncoder.DateEncodingStrategy = .iso8601) {
        self.init(name: name, headers: headers)
        
        let jsonEncoder = JSONEncoder()
        jsonEncoder.dateEncodingStrategy = jsonDateEncodingStrategy
        
        if let jsonData = try? jsonEncoder.encode(encodableBody),
           let jsonString = String(data: jsonData, encoding: .utf8)
        {
            self.body = jsonString
            self.headers[StompCommonHeader.contentType.rawValue] = "application/json;charset=UTF-8"
        }
    }

    /// Initializes a frame with a plain text string body
    init(name: T, headers: [String: String] = [:], stringBody: String) {
        self.init(name: name, headers: headers)
        
        self.body = stringBody
        if self.headers[StompCommonHeader.contentType.rawValue] == nil {
            self.headers[StompCommonHeader.contentType.rawValue] = "text/plain"
        }
    }

    /// Initializes a frame with binary `Data` body
    init(name: T, headers: [String: String] = [:], dataBody: Data) {
        self.init(name: name, headers: headers)
        
        self.body = dataBody
    }

    /// Initializes a frame by deserializing from a serialized STOMP string
    init(withSerializedString frame: String) throws {
        try deserialize(frame: frame)
    }

    /// Serializes the current frame into a STOMP string format
    /// - Returns: A valid STOMP frame string
    func serialize() -> String {
        var frame = name.rawValue + "\n"
        
        // Append headers
        for (hKey, hVal) in headers {
            frame += "\(hKey):\(hVal)\n"
        }
        
        // Append body
        if let stringBody = body as? String, !stringBody.isEmpty {
            frame += "\n\(stringBody)"
        } else if let dataBody = body as? Data, !dataBody.isEmpty {
            let dataAsBase64 = dataBody.base64EncodedString()
            frame += "\n\(dataAsBase64)"
        } else {
            frame += "\n"
        }
        
        // End with NULL terminator
        frame += StompConstants.nullChar
        
        return frame
    }

    /// Deserializes a raw STOMP frame string into this frame
    /// - Parameter frame: A full STOMP string with command, headers, and body
    /// - Throws: If parsing the frame fails
    mutating func deserialize(frame: String) throws {
        // If the frame consists of only a single newline character "\n", interpret it as a Heartbeat from the server
        if frame == StompConstants.heartbeatSymbol {
            name = (StompResponseFrame.serverPing as! T)
            body = frame
            return
        }
        
        var lines = frame.components(separatedBy: "\n")
        
        // ** Remove first if was empty string
        if let firstLine = lines.first, firstLine.isEmpty {
            lines.removeFirst()
        }
        
        // ** Parse Command
        if let command = StompRequestFrame(rawValue: lines.first ?? "") {
            name = (command as! T)
        } else if let command = StompResponseFrame(rawValue: lines.first ?? "") {
            name = (command as! T)
        } else {
            throw InvalidStompCommandError()
        }
        
        // ** Remove Command
        lines.removeFirst()
        
        // ** Parse Headers
        while let line = lines.first, !line.isEmpty {
            let headerParts = line.components(separatedBy: ":")
            
            if headerParts.count != 2 {
                break
            }
            
            headers[headerParts[0].trimmingCharacters(in: .whitespacesAndNewlines)] = headerParts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            
            lines.removeFirst()
        }
        
        // ** Remove the blank line between the headers and body
        if let firstLine = lines.first, firstLine.isEmpty {
            lines.removeFirst()
        }
        
        // ** Parse body
        var body = lines.joined(separator: "\n")
        
        if body.hasSuffix("\0") {
            body = body.replacingOccurrences(of: "\0", with: "")
        }
        
        if let data = Data(base64Encoded: body) {
            self.body = data
        } else {
            self.body = body
        }
    }
    
    func getCommonHeader(_ header: StompCommonHeader) -> String? {
        return headers[header.rawValue]
    }
}
