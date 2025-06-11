//
//  SwiftStomp.swift
//  SwiftStomp
//
//  Created by Ahmad Daneshvar on 5/16/20.
//  Copyright © 2020 Ahmad Daneshvar. All rights reserved.
//

import Combine
import Foundation
import Network
import OSLog
import Reachability

/// A high-level STOMP (Simple Text Oriented Messaging Protocol) client built on top of WebSockets using `URLSessionWebSocketTask`.
///
/// `SwiftStomp` provides full STOMP 1.1/1.2 protocol support, with built-in connection state management,
/// reconnection logic, ping/heartbeat monitoring, and message/event/receipt publishing streams via Combine.
///
/// This class is designed for robust messaging scenarios in iOS/macOS apps using STOMP brokers like ActiveMQ, RabbitMQ, or similar.
///
/// ### Key Features:
/// - Asynchronous message handling using Combine publishers
/// - Automatic reconnection with retry logic
/// - Optional auto-ping with configurable interval
/// - Network reachability tracking using `Reachability`
/// - Callback execution on a configurable dispatch queue
/// - Custom HTTP and STOMP headers during handshake
/// - Logging support for debugging protocol activity
public class SwiftStomp: NSObject {
    private enum Constants {
        /// The heartbeat signal (`\n`) is a single newline character used by both the server and client
        /// as a lightweight ping mechanism to maintain the STOMP connection's liveness.
        ///
        /// - The client **sends** this symbol periodically to the server as part of the heartbeat mechanism.
        static let heartbeatSymbol = "\n"

        static let heartbeatHeaderKey = StompCommonHeader.heartBeat.rawValue

        /// The default interval (in milliseconds) for sending heartbeats to the server,
        /// used when the server does not provide specific heartbeat settings.
        static let defaultHeartbeatInterval = 10_000
    }
    
    private enum Default {
        static let reconnectSchedulerInterval: TimeInterval = 3
    }

    /// The WebSocket endpoint (STOMP broker URL)
    fileprivate var host: URL
    /// HTTP headers to include during the initial WebSocket handshake
    fileprivate var httpConnectionHeaders: [String: String]
    /// STOMP-specific headers used during the STOMP CONNECT frame
    fileprivate var stompConnectionHeaders: [String: String]

    /// WebSocket infrastructure using URLSession
    fileprivate var urlSession: URLSession?
    fileprivate var webSocketTask: URLSessionWebSocketTask?

    /// Supported STOMP protocol versions sent during CONNECT
    fileprivate var acceptVersion = "1.1,1.2"
    /// Current connection status of the STOMP client
    fileprivate var status: StompConnectionStatus = .socketDisconnected

    fileprivate var reconnectScheduler: Timer?
    /// Time interval for automatic reconnect attempts. Can be set externally before calling `connect()`.
    public var reconnectSchedulerInterval = Default.reconnectSchedulerInterval

    fileprivate var reachability: Reachability?
    fileprivate var hostIsReachabile = true

    // MARK: Heartbeat peroperties

    /// Determines whether the client should automatically send heartbeat pings to the server using a timer
    private var isAutoHeartbeatEnable = false

    /// The interval (in seconds) at which the client *wants* to send heartbeat pings to the server.
    /// This value is negotiated during the STOMP handshake.
    private var heartbeatClientIntervalSeconds: TimeInterval = 0

    /// The interval (in seconds) at which the server *expects* heartbeat pings from the client.
    /// This value is provided by the server during the STOMP handshake.
    private var heartbeatServerIntervalSeconds: TimeInterval = 0

    /// The actual interval at which the client will send heartbeat pings to the server.
    /// This is determined as the **maximum** of `heartbeatClientIntervalSeconds` and `heartbeatServerIntervalSeconds`.
    private var heartbeatToServerInterval: TimeInterval {
        max(heartbeatClientIntervalSeconds, heartbeatServerIntervalSeconds)
    }

    /// The timer responsible for triggering automatic heartbeat pings from the client to the server
    private var heartbeatTimer: Timer?

    // MARK: Auto ping peroperties

    fileprivate var pingTimer: Timer?
    fileprivate var pingInterval: TimeInterval = 10 //< 10 Seconds
    fileprivate var autoPingEnabled = false

    /// Delegate for handling STOMP client events
    public weak var delegate: SwiftStompDelegate?
    
    // MARK: Streams

    fileprivate var _eventsUpstream = PassthroughSubject<StompUpstreamEvent, Never>()
    fileprivate var _messagesUpstream = PassthroughSubject<StompUpstreamMessage, Never>()
    fileprivate var _receiptsUpstream = PassthroughSubject<String, Never>()
    
    public var eventsUpstream: AnyPublisher<StompUpstreamEvent, Never> {
        _eventsUpstream.eraseToAnyPublisher()
    }
    
    public var messagesUpstream: AnyPublisher<StompUpstreamMessage, Never> {
        _messagesUpstream.eraseToAnyPublisher()
    }
    
    public var receiptUpstream: AnyPublisher<String, Never> {
        _receiptsUpstream.eraseToAnyPublisher()
    }

    // MARK: Configurations
    
    public var enableLogging = false
    public var isConnected: Bool {
        return self.status == .fullyConnected
    }
    public var connectionStatus: StompConnectionStatus{
        return self.status
    }

    // Private storage for the callbacksThread, not directly accessible outside of this class
    private var _callbacksThread: DispatchQueue?

    // Public computed property
    public var callbacksThread: DispatchQueue {
        // Getter returns _callbacksThread if it's not nil, otherwise returns DispatchQueue.main
        get {
            return _callbacksThread ?? DispatchQueue.main
        }
        // Setter allows external code to set _callbacksThread
        set {
            _callbacksThread = newValue
        }
    }

    public var autoReconnect = false

    /// Creates a new STOMP client with the given host and optional headers
    @available(iOS, deprecated: 17, message: "Use init(host:headers:httpConnectionHeaders:proxyMode:) instead")
    public convenience init (
        host: URL,
        headers: [String: String] = [:],
        httpConnectionHeaders: [String: String] = [:]
    ) {
        self.init(host: host, headers: headers, httpConnectionHeaders: httpConnectionHeaders, proxy: .disable)
    }

    /// Creates a new STOMP client with the given host, optional headers and proxy
    @available(iOS 17, *)
    public convenience init (
        host: URL,
        headers: [String: String] = [:],
        httpConnectionHeaders: [String: String] = [:],
        proxyMode: DebugProxyMode = .disable
    ) {
        self.init(host: host, headers: headers, httpConnectionHeaders: httpConnectionHeaders, proxy: proxyMode)
    }

    /// Centralized private initializer
    private init(host: URL, headers: [String: String], httpConnectionHeaders: [String: String], proxy proxyMode: DebugProxyMode) {
        self.host = host
        self.stompConnectionHeaders = headers
        self.httpConnectionHeaders = httpConnectionHeaders
        super.init()

        self.urlSession = URLSession(configuration: makeSessionConfiguration(proxyMode: proxyMode), delegate: self, delegateQueue: nil)
        self.initReachability()
    }
    
    deinit {
        disconnect(force: true)
    }

    private func makeSessionConfiguration(proxyMode: DebugProxyMode) -> URLSessionConfiguration {
        let sessionConfig = URLSessionConfiguration.default
        
        if #available(iOS 17.0, *) {
            switch proxyMode {
            case .proxyman(let host, let port):
                let socksv5Proxy = NWEndpoint.hostPort(
                    host: NWEndpoint.Host(host),
                    port: NWEndpoint.Port(integerLiteral: NWEndpoint.Port.IntegerLiteralType(port))
                )
                let proxyConfig = ProxyConfiguration(socksv5Proxy: socksv5Proxy)
                sessionConfig.proxyConfigurations = [proxyConfig]
            case .disable:
                break
            }
        }

        return sessionConfig
    }

    private func initReachability() {
        if let reachability = try? Reachability(queueQoS: .utility, targetQueue: DispatchQueue(label: "swiftStomp.reachability"), notificationQueue: .global()) {
            reachability.whenReachable = { [weak self] _ in
                self?.stompLog(type: .info, message: "Network IS reachable")
                self?.hostIsReachabile = true
            }
            reachability.whenUnreachable = { [weak self] _ in
                self?.stompLog(type: .info, message: "Network IS NOT reachable")
                self?.hostIsReachabile = false
            }
            self.reachability = reachability
        } else {
            self.stompLog(type: .info, message: "Unable to create Reachability")
        }
    }
}

/// Public Operating functions
public extension SwiftStomp {
    func connect(timeout: TimeInterval = 5, acceptVersion: String, autoReconnect: Bool = false) {

        self.stompLog(type: .info, message: "Connecting...  autoReconnect: \(autoReconnect)")

        self.autoReconnect = autoReconnect

        //** If socket is connected now, just needs to connect to the Stomp
        if self.status == .socketConnected {
            self.stompConnect()
            return
        }

        var urlRequest = URLRequest(url: self.host)

        //** Accept Version
        self.acceptVersion = acceptVersion

        //** Time interval
        urlRequest.timeoutInterval = timeout

        for header in httpConnectionHeaders {
            urlRequest.addValue(header.value, forHTTPHeaderField: header.key)
        }

        self.webSocketTask = urlSession?.webSocketTask(with: urlRequest)
        self.webSocketTask?.resume()

        listen()

        self.status = .connecting
    }

    func disconnect(force: Bool = false) {

        self.autoReconnect = false
        self.disableAutoPing()
        self.invalidateConnector()

        if !force{ //< Send disconnect first over STOMP
            self.stompDisconnect()
        } else { //< Disconnect socket directly! (Not recommended until you have to do it!)
            handleDisconnect()
        }
    }

    func subscribe(to destination: String, mode: StompAckMode = .auto, headers: [String: String]? = nil) {
        var headersToSend = StompHeaderBuilder
            .add(key: .destination, value: destination)
            .add(key: .id, value: destination)
            .add(key: .ack, value: mode.rawValue)
            .get

        //** Append extra headers
        headers?.forEach({ hEntry in
            headersToSend[hEntry.key] = hEntry.value
        })

        self.sendFrame(frame: StompFrame(name: .subscribe, headers: headersToSend))
    }

    func unsubscribe(from destination: String, mode: StompAckMode = .auto, headers: [String: String]? = nil) {
        var headersToSend = StompHeaderBuilder
            .add(key: .id, value: destination)
            .get

        //** Append extra headers
        headers?.forEach({ hEntry in
            headersToSend[hEntry.key] = hEntry.value
        })

        self.sendFrame(frame: StompFrame(name: .unsubscribe, headers: headersToSend))
    }

    func send(body: String, to: String, receiptId: String? = nil, headers: [String: String]? = nil) {
        let headers = prepareHeadersForSend(to: to, receiptId: receiptId, headers: headers)

        self.sendFrame(frame: StompFrame(name: .send, headers: headers, stringBody: body))
    }

    func send(body: Data, to: String, receiptId: String? = nil, headers: [String: String]? = nil) {
        let headers = prepareHeadersForSend(to: to, receiptId: receiptId, headers: headers)

        self.sendFrame(frame: StompFrame(name: .send, headers: headers, dataBody: body))
    }

    func send <T: Encodable> (body: T, to: String, receiptId: String? = nil, headers: [String: String]? = nil, jsonDateEncodingStrategy: JSONEncoder.DateEncodingStrategy = .iso8601) {
        let headers = prepareHeadersForSend(to: to, receiptId: receiptId, headers: headers)

        self.sendFrame(frame: StompFrame(name: .send, headers: headers, encodableBody: body, jsonDateEncodingStrategy: jsonDateEncodingStrategy))
    }

    func ack(messageId: String, transaction: String? = nil) {
        let headerBuilder = StompHeaderBuilder
            .add(key: .id, value: messageId)

        if let transaction = transaction{
            _ = headerBuilder.add(key: .transaction, value: transaction)
        }

        let headers = headerBuilder.get

        self.sendFrame(frame: StompFrame(name: .ack, headers: headers))
    }

    func nack(messageId: String, transaction: String? = nil) {
        let headerBuilder = StompHeaderBuilder
            .add(key: .id, value: messageId)

        if let transaction = transaction{
            _ = headerBuilder.add(key: .transaction, value: transaction)
        }

        let headers = headerBuilder.get

        self.sendFrame(frame: StompFrame(name: .nack, headers: headers))
    }

    func begin(transactionName: String) {
        let headers = StompHeaderBuilder
            .add(key: .transaction, value: transactionName)
            .get

        self.sendFrame(frame: StompFrame(name: .begin, headers: headers))
    }

    func commit(transactionName: String) {
        let headers = StompHeaderBuilder
            .add(key: .transaction, value: transactionName)
            .get

        self.sendFrame(frame: StompFrame(name: .commit, headers: headers))
    }

    func abort(transactionName: String) {
        let headers = StompHeaderBuilder
            .add(key: .transaction, value: transactionName)
            .get

        self.sendFrame(frame: StompFrame(name: .abort, headers: headers))
    }


    /// Send ping command to keep connection alive
    /// - Parameters:
    ///   - data: Date to send over Web socket
    ///   - completion: Completion block
    func ping(data: Data = Data(), completion: (() -> Void)? = nil) {

        //** Check socket status
        guard let webSocketTask, self.status == .fullyConnected || self.status == .socketConnected else {
            self.stompLog(type: .info, message: "Stomp: Unable to send `ping`. Socket is not connected!")
            return
        }

        webSocketTask.sendPing() { _ in
            completion?()
        }

        self.stompLog(type: .info, message: "Stomp: Ping sent!")

        //** Reset ping timer
        self.resetPingTimer()
    }


    /// Enable auto ping command to ensure connection will keep alive and prevent connection to stay idle
    /// - Notice: Please be care if you used `disconnect`, you have to re-enable the timer again.
    /// - Parameter pingInterval: Ping command send interval
    func enableAutoPing(pingInterval: TimeInterval = 10) {
        self.pingInterval = pingInterval
        self.autoPingEnabled = true

        //** Reset ping timer
        self.resetPingTimer()
    }


    /// Disable auto ping function
    func disableAutoPing() {
        self.autoPingEnabled = false
        self.pingTimer?.invalidate()
    }

    /// Toggles automatic heartbeat pings to the server.
    /// If enabled, a timer sends heartbeats at the negotiated interval.
    func toggleAutoHeartbeat(_ enabled: Bool) {
        stompLog(type: .info, message: "Auto Heartbeat sending set to: \(enabled)")
        isAutoHeartbeatEnable = enabled
        if !enabled {
            heartbeatTimer?.invalidate()
        }
        resetHeartbeatTimer()
    }
}

/// Helper functions
fileprivate extension SwiftStomp {
    func stompLog(type: StompLogType, message: String) {
        guard enableLogging else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let timestamp = formatter.string(from: Date())
        os_log(type == .info ? .info: .error, "%s SwiftStomp [%s]: %s", timestamp, type.rawValue, message)
    }

    func prepareHeadersForSend(to: String, receiptId: String? = nil, headers: [String: String]? = nil) -> [String: String]{

        let headerBuilder = StompHeaderBuilder
        .add(key: .destination, value: to)

        if let receiptId = receiptId{
            _ = headerBuilder.add(key: .receipt, value: receiptId)
        }

        var headersToSend = headerBuilder.get

        //** Append user headers
        if let headers = headers{
            for (hKey, hVal) in headers{
                headersToSend[hKey] = hVal
            }
        }

        return headersToSend
    }

    /// Schedules a timer to attempt automatic reconnection to the STOMP server
    func scheduleConnector() {
        self.stompLog(type: .info, message: "Scheduling connector")

        if let scheduler = self.reconnectScheduler, scheduler.isValid{
            scheduler.invalidate()
            reconnectScheduler = nil
        }

        try? self.reachability?.startNotifier()

        DispatchQueue.main.async { [weak self] in
            self?.reconnectScheduler = Timer.scheduledTimer(
                withTimeInterval: self?.reconnectSchedulerInterval ?? Default.reconnectSchedulerInterval,
                repeats: true
            ) { [weak self] timer in
                guard let self = self else {
                    return
                }

                self.stompLog(type: .info, message: "Reconnect scheduler running")

                if !self.hostIsReachabile{
                    self.stompLog(type: .info, message: "Network is not reachable. Ignore connecting!")
                    return
                }

                self.connect(acceptVersion: self.acceptVersion, autoReconnect: self.autoReconnect)
            }
        }
    }

    func invalidateConnector() {
        self.stompLog(type: .info, message: "Invalidating connector")

        if let connector = self.reconnectScheduler, connector.isValid{
            connector.invalidate()
        }

        self.reachability?.stopNotifier()
    }

}

/// Back-Operating functions
private extension SwiftStomp {
    func stompConnect() {

        //** Add headers
        var headers = StompHeaderBuilder
            .add(key: .acceptVersion, value: self.acceptVersion)
            .get

        //** Append connection headers
        for (hKey, hVal) in stompConnectionHeaders{
            headers[hKey] = hVal
        }

        saveHeartbeatClientSettings(connectedHeaders: stompConnectionHeaders)

        self.sendFrame(frame: StompFrame(name: .connect, headers: headers))
    }

    func stompDisconnect() {
        //** Add headers
        let headers = StompHeaderBuilder
            .add(key: .receipt, value: "disconnect/safe")
            .get

        self.sendFrame(frame: StompFrame(name: .disconnect, headers: headers))
    }

    func processReceivedSocketText(text: String) {
        var frame: StompFrame<StompResponseFrame>

        //** Deserialize frame
        do{
            frame = try StompFrame(withSerializedString: text)
        }catch {
            stompLog(type: .stompError, message: "Process frame error: \(error.localizedDescription)")
            return
        }

        //** Dispatch STOMP frame

        switch frame.name {
        case .message:
            stompLog(type: .info, message: "Stomp: Message received: \(String(describing: frame.body))")

            let messageId = frame.getCommonHeader(.messageId) ?? ""
            let destination = frame.getCommonHeader(.destination) ?? ""

            callbacksThread.async { [weak self] in
                guard let self else { return }
                self.delegate?.onMessageReceived(swiftStomp: self, message: frame.body, messageId: messageId, destination: destination, headers: frame.headers)
                
                // ** Broadcast through upstream
                if let stringBody = frame.body as? String {
                    self._messagesUpstream.send(
                        .text(
                            message: stringBody,
                            messageId: messageId,
                            destination: destination,
                            headers: frame.headers
                        )
                    )
                } else if let dataBody = frame.body as? Data {
                    self._messagesUpstream.send(
                        .data(
                            data: dataBody,
                            messageId: messageId,
                            destination: destination,
                            headers: frame.headers
                        )
                    )
                }
            }

        case .receipt:
            guard let receiptId = frame.getCommonHeader(.receiptId) else {
                stompLog(type: .stompError, message: "Receipt message received without `receipt-id` header: \(text)")
                return
            }


            stompLog(type: .info, message: "Receipt received: \(receiptId)")

            callbacksThread.async { [weak self] in
                guard let self else { return }
                self.delegate?.onReceipt(swiftStomp: self, receiptId: receiptId)
                self._receiptsUpstream.send(receiptId)
            }

            if receiptId == "disconnect/safe"{
                self.status = .socketConnected

                callbacksThread.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.onDisconnect(swiftStomp: self, disconnectType: .fromStomp)
                    self._eventsUpstream.send(.disconnected(type: .fromStomp))
                }

                self.webSocketTask?.cancel(with: .goingAway, reason: nil)
                self.webSocketTask = nil
            }

        case .error:
            self.status = .socketConnected

            guard let briefDescription = frame.getCommonHeader(.message) else {
                stompLog(type: .stompError, message: "Stomp error frame received without `message` header: \(text)")
                return
            }

            let fullDescription = frame.body as? String
            let receiptId = frame.getCommonHeader(.receiptId)

            stompLog(type: .stompError, message: briefDescription)

            callbacksThread.async { [weak self] in
                guard let self else { return }
                self.delegate?.onError(swiftStomp: self, briefDescription: briefDescription, fullDescription: fullDescription, receiptId: receiptId, type: .fromStomp)
                self._eventsUpstream.send(.error(error: .init(type: .fromStomp, receiptId: receiptId, localizedDescription: briefDescription)))
            }

        case .connected:
            self.status = .fullyConnected
            self.saveHeartbeatServerSettings(connectedHeaders: frame.headers)
            self.resetHeartbeatTimer()

            stompLog(type: .info, message: "Stomp: Connected")

            callbacksThread.async { [weak self] in
                guard let self else { return }
                self.delegate?.onConnect(swiftStomp: self, connectType: .toStomp)
                self._eventsUpstream.send(.connected(type: .toStomp))
            }
        default:
            stompLog(type: .info, message: "Stomp: Un-Processable content: \(text)")
        }
    }

    func sendFrame(frame: StompFrame<StompRequestFrame>, completion: (() -> ())? = nil) {
        guard let webSocketTask else {
            stompLog(type: .info, message: "Unable to send frame \(frame.name.rawValue): WebSocket is not connected!")
            return
        }

        switch self.status {
        case .socketConnected:
            if frame.name != .connect{
                stompLog(type: .info, message: "Unable to send frame \(frame.name.rawValue): Stomp is not connected!")
                return
            }
        case .socketDisconnected, .connecting:
            stompLog(type: .info, message: "Unable to send frame \(frame.name.rawValue): Invalid state: \(self.status)")
            return
        default:
            break
        }

        let rawFrameToSend = frame.serialize()

        stompLog(type: .info, message: "Stomp: Sending...\n\(rawFrameToSend)\n")

        webSocketTask.send(.string(rawFrameToSend)) { error in
            if let error = error {
                self.stompLog(type: .stompError, message: "Error sending frame: \(error)")
            }

            completion?()
        }

        //** Reset ping timer
        self.resetPingTimer()
    }

    func resetPingTimer() {
        if !autoPingEnabled{
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            //** Invalidate if timer is valid
            if let t = self.pingTimer, t.isValid{
                t.invalidate()
            }

            //** Schedule the ping timer
            self.pingTimer = Timer.scheduledTimer(withTimeInterval: self.pingInterval, repeats: true) { [weak self] _ in
                self?.ping()
            }
        }
    }

    /// Resets the heartbeat timer if auto-heartbeat is enabled and the connection status is `.fullyConnected`.
    /// Ensures only one valid timer is active. When triggered, the timer will send heartbeat signals at a regular interval.
    func resetHeartbeatTimer() {
        guard isAutoHeartbeatEnable else {
            stompLog(type: .info, message: "Heartbeat timer not restarted because auto-heartbeat is disabled")
            return
        }

        guard status == .fullyConnected else {
            stompLog(type: .info, message: "Heartbeat timer not restarted because connection is not fullyConnected")
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            if let heartbeatTimer = self.heartbeatTimer, heartbeatTimer.isValid {
                heartbeatTimer.invalidate()
            }

            stompLog(type: .info, message: "Heartbeat timer started")
            self.heartbeatTimer = Timer.scheduledTimer(
                withTimeInterval: self.heartbeatToServerInterval,
                repeats: true
            ) { [weak self] _ in
                self?.sendHeartbeat()
            }
        }
    }

    /// Sends a heartbeat signal to the server.
    /// This is used to keep the connection alive and inform the server that the client is still active.
    func sendHeartbeat() {
        stompLog(type: .info, message: "Heartbeat sent to server")
        webSocketTask?.send(.string(Constants.heartbeatSymbol)) { error in
            if let error = error {
                self.stompLog(type: .stompError, message: "Error sending heartbeat: \(error)")
            }
        }
    }

    /// Parses and stores the heartbeat interval expected by the server based on the `heart-beat` header.
    /// - Parameter connectedHeaders: Dictionary containing connection headers from the server.
    func saveHeartbeatServerSettings(connectedHeaders: [String: String]) {
        guard let heartbeatValues = connectedHeaders[Constants.heartbeatHeaderKey],
              let heartbeatValueMillisecondsString = heartbeatValues.split(separator: ",").last,
              let heartbeatValueMilliseconds = Int(heartbeatValueMillisecondsString) else {
            heartbeatServerIntervalSeconds = makeSeconds(fromMilliseconds: Constants.defaultHeartbeatInterval)
            stompLog(
                type: .info,
                message: "heartbeatServerIntervalSeconds was set to default: \(Constants.defaultHeartbeatInterval) ms"
            )
            return
        }

        heartbeatServerIntervalSeconds = makeSeconds(fromMilliseconds: heartbeatValueMilliseconds)
        stompLog(
            type: .info,
            message: "New heartbeatServerIntervalSeconds set to: \(heartbeatServerIntervalSeconds) seconds"
        )
    }

    /// Saves the client-preferred heartbeat interval from the `heart-beat` header.
    /// - Parameter heartbeatHeader: The value of the `heart-beat` header, expected in format "client,server"
    func saveHeartbeatClientSettings(connectedHeaders: [String: String]) {
        guard let heartbeatValues = connectedHeaders[Constants.heartbeatHeaderKey],
              let heartbeatValueMillisecondsString = heartbeatValues.split(separator: ",").first,
              let heartbeatValueMilliseconds = Int(heartbeatValueMillisecondsString) else {
            heartbeatClientIntervalSeconds = makeSeconds(fromMilliseconds: Constants.defaultHeartbeatInterval)
            stompLog(
                type: .info,
                message: "heartbeatClientIntervalSeconds set to default: \(Constants.defaultHeartbeatInterval) ms"
            )
            return
        }

        heartbeatClientIntervalSeconds = makeSeconds(fromMilliseconds: heartbeatValueMilliseconds)
        stompLog(
            type: .info,
            message: "heartbeatClientIntervalSeconds updated from header: \(heartbeatValueMilliseconds) ms"
        )
    }

    /// Converts milliseconds to seconds as `TimeInterval`.
    @inline(__always)
    func makeSeconds(fromMilliseconds milliseconds: Int) -> TimeInterval {
        TimeInterval(milliseconds) / 1000
    }
}

/// Web socket delegate
extension SwiftStomp {
    private func listen() {
        self.stompLog(type: .info, message: "Listening.")
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .failure(let error):
                self?.stompLog(type: .socketError, message: "Socket listen: Error: \(error)")
                
                self?.callbacksThread.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.onError(swiftStomp: self, briefDescription: "Stomp Error", fullDescription: error.localizedDescription, receiptId: nil, type: .fromStomp)
                }
                
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.stompLog(type: .info, message: "Socket: Received text")
                    self?.processReceivedSocketText(text: text)
                    
                case .data(let data):
                    self?.stompLog(type: .info, message: "Socket: Received data: \(data.count)")
                    
                default:
                    break
                }
                
                // Keep listening
                self?.listen()
            }
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension SwiftStomp: URLSessionWebSocketDelegate {

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        let p = `protocol` ?? ""

        self.status = .socketConnected
        self.invalidateConnector()

        stompLog(type: .info, message: "Socket: connected, protocol: \(p)")

        callbacksThread.async { [weak self] in
            guard let self else { return }
            self.delegate?.onConnect(swiftStomp: self, connectType: .toSocketEndpoint)
            self._eventsUpstream.send(.connected(type: .toSocketEndpoint))
        }

        self.stompConnect()
    }

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        var r = ""
        if let d = reason {
            r = String(data: d, encoding: .utf8) ?? ""
        }

        stompLog(type: .info, message: "Socket: Disconnected: \(r) with code: \(closeCode.rawValue)")

        handleDisconnect()
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else {
            return
        }
        
        stompLog(type: .socketError, message: "Socket: Error: \(error.localizedDescription)")

        handleDisconnect()

        callbacksThread.async { [weak self] in
            guard let self else { return }
            self.delegate?.onError(swiftStomp: self, briefDescription: "Socket Error", fullDescription: error.localizedDescription, receiptId: nil, type: .fromSocket)
            self._eventsUpstream.send(.error(error: .init(error: error, type: .fromSocket)))
        }
    }

    private func handleDisconnect() {
        pingTimer?.invalidate()
        heartbeatTimer?.invalidate()
        self.invalidateConnector()

        self.webSocketTask?.cancel(with: .goingAway, reason: nil)
        self.webSocketTask = nil

        self.status = .socketDisconnected

        callbacksThread.async { [weak self] in
            guard let self else { return }
            self.delegate?.onDisconnect(swiftStomp: self, disconnectType: .fromSocket)
            self._eventsUpstream.send(.disconnected(type: .fromSocket))
        }

        if self.autoReconnect{
            self.scheduleConnector()
        }
    }
}

// MARK: - SwiftStomp delegate

/// A delegate protocol for receiving events from a SwiftStomp client.
public protocol SwiftStompDelegate: AnyObject {

    func onConnect(swiftStomp: SwiftStomp, connectType: StompConnectType)

    func onDisconnect(swiftStomp: SwiftStomp, disconnectType: StompDisconnectType)

    func onMessageReceived(swiftStomp: SwiftStomp, message: Any?, messageId: String, destination: String, headers: [String: String])

    func onReceipt(swiftStomp: SwiftStomp, receiptId: String)

    func onError(swiftStomp: SwiftStomp, briefDescription: String, fullDescription: String?, receiptId: String?, type: StompErrorType)
}

// MARK: - DebugProxyMode

/// Defines proxy configuration modes for the SwiftStomp client.
/// Used to optionally route network traffic through a proxy server, such as for debugging WebSocket connections.
public enum DebugProxyMode {
    /// [Capture and debug Websocket from iOS](https://docs.proxyman.com/advanced-features/websocket)
    case proxyman(host: String = "localhost", port: Int16 = 8889)
    /// Disables proxying
    case disable
}
