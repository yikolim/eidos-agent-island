import Foundation
import Observation

@Observable
class AgentStore {
    var agents: [AgentStatus] = []
    var islandState: IslandState = .idle
    private var approvalQueue: [ApprovalRequest] = []

    // Called from IslandServer (background thread) — must dispatch to main
    func handleEvent(_ event: AgentEvent) {
        DispatchQueue.main.async {
            self.upsert(event)
        }
    }

    private func upsert(_ event: AgentEvent) {
        if let i = agents.firstIndex(where: { $0.agentID == event.agent }) {
            agents[i].apply(event)
            if agents[i].status == "done" || agents[i].status == "disconnected" {
                // linger 4 seconds then remove
                let id = agents[i].agentID
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    self.agents.removeAll {
                        $0.agentID == id && ($0.status == "done" || $0.status == "disconnected")
                    }
                    self.recalcState()
                }
            }
        } else {
            agents.append(AgentStatus(from: event))
        }
        recalcState()
    }

    func pushApproval(_ req: ApprovalRequest) {
        DispatchQueue.main.async {
            self.approvalQueue.append(req)
            self.recalcState()
        }
    }

    func resolveApproval(id: String, approved: Bool, modified: [String: Any]? = nil) {
        DispatchQueue.main.async {
            self.approvalQueue.removeAll { $0.requestID == id }
            self.recalcState()
        }
    }

    var hasPendingApprovals: Bool { !approvalQueue.isEmpty }

    /// Set while the pointer is over the island — hovering expands it.
    var isHovered = false {
        didSet { if oldValue != isHovered { recalcState() } }
    }

    func recalcState() {
        if let next = approvalQueue.first {
            islandState = .approval(next)
            return
        }
        let running = agents.filter { $0.status == "running" || $0.status == "paused" }
        // Hovering expands the island to reveal more — like the Dynamic Island.
        if isHovered {
            islandState = running.isEmpty ? .mini : .cockpit
            return
        }
        switch running.count {
        case 0:  islandState = .idle
        case 1:  islandState = .mini
        default: islandState = .cockpit
        }
    }

    func cycleState() {
        switch islandState {
        case .idle:     islandState = .mini
        case .mini:     islandState = agents.isEmpty ? .idle : .cockpit
        case .cockpit:  islandState = .mini
        case .approval: islandState = .cockpit
        }
    }
}
