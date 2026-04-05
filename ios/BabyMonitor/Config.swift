import Foundation

enum Config {
    static let serverName = "Baby Monitor"
    static let streamURL = URL(string: "ws://192.168.0.71:8765/stream")!
    static let healthURL = URL(string: "http://192.168.0.71:8765/health")!
}
