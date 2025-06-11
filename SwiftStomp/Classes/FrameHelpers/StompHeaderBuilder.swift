//
//  StompHeaderBuilder.swift
//  Pods
//
//  Created by Ahmad Daneshvar on 5/16/24.
//

import Foundation

/// A fluent builder class for constructing STOMP headers
/// ### Usage Example:
/// ```swift
/// let headers = StompHeaderBuilder
///     .add(key: .destination, value: "/topic/chat")
///     .add(key: .contentType, value: "application/json")
///     .get
/// ```
public class StompHeaderBuilder {
    /// Stores all constructed headers
    private var headers = [String: String]()

    /// Static initializer for creating a builder instance with a single header entry
    static func add(key: StompCommonHeader, value: Any) -> StompHeaderBuilder{
        return StompHeaderBuilder(key: key.rawValue, value: value)
    }

    /// Private initializer used internally for static creation with one header
    private init(key: String, value: Any){
        self.headers[key] = "\(value)"
    }

    /// Adds or updates a header entry on the current builder instance
    func add(key: StompCommonHeader, value: Any) -> StompHeaderBuilder{
        self.headers[key.rawValue] = "\(value)"
        
        return self
    }
    
    var get: [String: String]{
        return self.headers
    }
}
