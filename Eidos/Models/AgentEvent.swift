import Foundation

struct AgentEvent: Codable, Sendable {
    let agent: String
    let status: String
    let task: String?
    let progress: Double?
    let elapsed: Int?
}

struct ApprovalRequestDTO: Codable, Sendable {
    let agent: String
    let task: String?
    let actions: [ActionDTO]
    let requestID: String?

    struct ActionDTO: Codable, Sendable {
        let op: String
        let target: String
        let description: String?
    }
}
