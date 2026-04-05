import Foundation
import UIKit
import Observation

@Observable
final class WebSocketManager {
    enum ConnectionState {
        case disconnected
        case connecting
        case reconnecting
        case live
    }

    var state: ConnectionState = .disconnected
    var currentFrame: UIImage?
    var reconnectAttempt: Int = 0
    var shouldAutoReconnect: Bool = true
    var isAppBackgrounded: Bool = false

    private var task: URLSessionWebSocketTask?
    private var reconnectTask: Task<Void, Never>?
    private let url: URL

    private static let backoffIntervals: [TimeInterval] = [1, 2, 4, 8, 16, 30]

    init(url: URL) {
        self.url = url
    }

    func connect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        shouldAutoReconnect = true
        state = .connecting
        var request = URLRequest(url: url)
        request.setValue("true", forHTTPHeaderField: "ngrok-skip-browser-warning")
        task = URLSession.shared.webSocketTask(with: request)
        task?.resume()
        state = .live
        reconnectAttempt = 0
        receiveLoop()
    }

    func disconnect() {
        shouldAutoReconnect = false
        reconnectTask?.cancel()
        reconnectTask = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        state = .disconnected
        currentFrame = nil
    }

    func scheduleReconnect() {
        guard state == .disconnected else { return }
        let delay = Self.backoffIntervals[min(reconnectAttempt, Self.backoffIntervals.count - 1)]
        reconnectAttempt += 1
        state = .reconnecting
        reconnectTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await MainActor.run { connect() }
        }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(.data(let data)):
                let image = UIImage(data: data)
                Task { @MainActor in self.currentFrame = image }
                self.receiveLoop()
            case .success(.string):
                self.receiveLoop()
            case .failure:
                Task { @MainActor in
                    self.state = .disconnected
                    if self.isAppBackgrounded {
                        NotificationManager.postDisconnectNotification()
                    }
                    if self.shouldAutoReconnect {
                        self.scheduleReconnect()
                    }
                }
            @unknown default:
                break
            }
        }
    }
}
