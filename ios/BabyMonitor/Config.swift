import Foundation

enum Config {
    static let serverName = "Baby Monitor"
    static let streamURL = URL(string: "wss://subglobous-pawky-mark.ngrok-free.dev/stream")!
    static let healthURL = URL(string: "https://subglobous-pawky-mark.ngrok-free.dev/health")!
}
