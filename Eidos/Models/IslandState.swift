import Foundation

enum IslandState: Equatable {
    case idle
    case mini
    case cockpit
    case approval(ApprovalRequest)
}

struct ApprovalRequest: Equatable, Identifiable, Sendable {
    let id: UUID
    let requestID: String
    let agent: String
    let task: String
    let actions: [AgentAction]

    init(id: UUID = UUID(), requestID: String, agent: String, task: String, actions: [AgentAction]) {
        self.id = id
        self.requestID = requestID
        self.agent = agent
        self.task = task
        self.actions = actions
    }
}

struct AgentAction: Equatable, Sendable {
    let op: String        // "edit" | "create" | "run" | "delete" | "read" | "open"
    let target: String
    let description: String?
}

struct ApprovalResponse {
    let approved: Bool
    let modified: [String: Any]?
}
