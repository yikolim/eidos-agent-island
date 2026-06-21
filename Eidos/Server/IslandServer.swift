import Foundation
import Network

class IslandServer {
    private var listener: NWListener?
    private let store: AgentStore
    private let queue = DispatchQueue(label: "com.eidos.server", qos: .userInitiated)
    let approvalQueue = ApprovalQueue()

    init(store: AgentStore) {
        self.store = store
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(approvalResolved(_:)),
            name: .approvalResolved,
            object: nil
        )
    }

    func start() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: 7799)
            listener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("IslandServer listening on :7799")
                case .failed(let error):
                    print("IslandServer failed: \(error)")
                default:
                    break
                }
            }
            listener?.newConnectionHandler = { [weak self] conn in
                self?.handle(conn)
            }
            listener?.start(queue: queue)
        } catch {
            print("IslandServer start error: \(error)")
        }
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        receiveHTTP(conn, buffer: Data())
    }

    // Accumulates bytes until the full HTTP request (headers + Content-Length
    // body) has been received, then routes it. This is more robust than a
    // single receive, since the body can arrive in a separate TCP segment.
    private func receiveHTTP(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            var buffer = buffer
            if let data, !data.isEmpty {
                buffer.append(data)
            }

            if let parsed = self.parseRequest(buffer) {
                self.route(method: parsed.method, path: parsed.path, body: parsed.body, conn: conn)
                return
            }

            if isComplete || error != nil {
                // Connection ended before a complete request arrived.
                conn.cancel()
                return
            }

            // Need more bytes — keep reading.
            self.receiveHTTP(conn, buffer: buffer)
        }
    }

    private struct ParsedRequest {
        let method: String
        let path: String
        let body: Data
    }

    /// Returns a ParsedRequest only when headers and the full Content-Length
    /// body are present in `buffer`; otherwise nil (need more data).
    private func parseRequest(_ buffer: Data) -> ParsedRequest? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = buffer.range(of: separator) else { return nil }

        let headerData = buffer[..<headerEnd.lowerBound]
        guard let headerStr = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerStr.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }
        let method = parts[0]
        let path = parts[1]

        // Find Content-Length (case-insensitive).
        var contentLength = 0
        for line in lines.dropFirst() {
            let comps = line.split(separator: ":", maxSplits: 1).map(String.init)
            if comps.count == 2, comps[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                contentLength = Int(comps[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }

        let bodyStart = headerEnd.upperBound
        let available = buffer.distance(from: bodyStart, to: buffer.endIndex)
        if available < contentLength {
            return nil // body not fully received yet
        }

        let body = buffer[bodyStart..<buffer.index(bodyStart, offsetBy: contentLength)]
        return ParsedRequest(method: method, path: path, body: Data(body))
    }

    private func route(method: String, path: String, body: Data, conn: NWConnection) {
        switch (method, path) {
        case ("POST", "/event"):
            handleEvent(body: body)
            respond(conn: conn, status: 200, body: #"{"ok":true}"#)

        case ("POST", "/approve"):
            handleApprove(body: body, conn: conn)  // does NOT respond immediately

        case ("POST", "/notify"):
            handleNotify(body: body)               // transient, auto-dismissing card
            respond(conn: conn, status: 200, body: #"{"ok":true}"#)

        case ("GET", "/status"):
            let agents = store.agents.map { ["agent": $0.agentID, "status": $0.status] }
            let json = try? JSONSerialization.data(withJSONObject: ["running": !agents.isEmpty, "agents": agents])
            respond(conn: conn, status: 200, body: String(data: json ?? Data(), encoding: .utf8) ?? "{}")

        default:
            respond(conn: conn, status: 404, body: #"{"error":"not found"}"#)
        }
    }

    private func handleEvent(body: Data) {
        guard let event = try? JSONDecoder().decode(AgentEvent.self, from: body) else { return }
        store.handleEvent(event)
    }

    private func handleApprove(body: Data, conn: NWConnection) {
        guard let dto = try? JSONDecoder().decode(ApprovalRequestDTO.self, from: body) else {
            respond(conn: conn, status: 400, body: #"{"error":"bad request"}"#)
            return
        }
        let reqID = dto.requestID ?? UUID().uuidString
        let actions = dto.actions.map { AgentAction(op: $0.op, target: $0.target, description: $0.description) }
        let req = ApprovalRequest(requestID: reqID, agent: dto.agent, task: dto.task ?? dto.agent, actions: actions)

        // Register the connection so we can respond when the user decides.
        approvalQueue.register(requestID: reqID, connection: conn)
        store.pushApproval(req)
        // Connection stays open — ApprovalQueue resumes it via approvalResolved(_:).
    }

    // Surfaces a Claude Code attention/approval request as a centered approval
    // card that the user can acknowledge, or that auto-dismisses after a few
    // seconds. Unlike /approve it does NOT hold the connection or gate anything
    // — the terminal stays authoritative, so Claude is never blocked on a tap.
    private func handleNotify(body: Data) {
        guard let dto = try? JSONDecoder().decode(ApprovalRequestDTO.self, from: body) else { return }
        let reqID = dto.requestID ?? UUID().uuidString
        let actions = dto.actions.map { AgentAction(op: $0.op, target: $0.target, description: $0.description) }
        let req = ApprovalRequest(requestID: reqID, agent: dto.agent, task: dto.task ?? dto.agent, actions: actions)
        store.pushApproval(req)

        // Auto-dismiss if the user doesn't acknowledge it.
        queue.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.store.resolveApproval(id: reqID, approved: false)
        }
    }

    @objc private func approvalResolved(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reqID = info["requestID"] as? String,
              let approved = info["approved"] as? Bool else { return }
        approvalQueue.resolve(requestID: reqID, approved: approved)
    }

    func respond(conn: NWConnection, status: Int, body: String) {
        let reason = status == 200 ? "OK" : (status == 404 ? "Not Found" : "Bad Request")
        let response = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n\(body)"
        conn.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            conn.cancel()
        })
    }
}
