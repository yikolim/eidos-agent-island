import Foundation
import Network

// Holds open HTTP connections for /approve long-polls.
// When the user resolves, we write the JSON response and close the connection.
class ApprovalQueue {
    private var pending: [String: NWConnection] = [:]
    private let lock = NSLock()

    func register(requestID: String, connection: NWConnection) {
        lock.lock(); defer { lock.unlock() }
        pending[requestID] = connection
    }

    func resolve(requestID: String, approved: Bool, modified: Any? = nil) {
        lock.lock()
        let conn = pending.removeValue(forKey: requestID)
        lock.unlock()

        guard let conn else { return }

        var body: [String: Any] = ["approved": approved, "modified": NSNull()]
        if let m = modified { body["modified"] = m }
        let json = (try? JSONSerialization.data(withJSONObject: body)).flatMap { String(data: $0, encoding: .utf8) } ?? #"{"approved":false}"#

        let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(json.utf8.count)\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n\(json)"
        conn.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            conn.cancel()
        })
    }
}
