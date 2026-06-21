import SwiftUI

struct ApprovalView: View {
    let request: ApprovalRequest
    @Environment(AgentStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header badge
            HStack(spacing: 5) {
                Circle().fill(Color(hex: "faad14")).frame(width: 5, height: 5)
                    .opacity(0.9)
                Text("APPROVAL NEEDED")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: "faad14"))
                    .tracking(0.3)
            }
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Color(hex: "faad14").opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.bottom, 10)

            Text(request.task)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.88))
            Text("\(request.agent) · \(request.actions.count) actions pending")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.bottom, 12)

            // Action preview
            VStack(alignment: .leading, spacing: 5) {
                Text("PENDING ACTIONS")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.25))
                    .tracking(0.6)
                    .padding(.bottom, 2)

                ForEach(Array(request.actions.enumerated()), id: \.offset) { _, action in
                    HStack(alignment: .top, spacing: 7) {
                        opBadge(action.op)
                        Text(action.target)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(11)
            .background(.white.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.bottom, 12)

            // Buttons
            HStack(spacing: 7) {
                Button(action: { resolve(approved: true) }) {
                    Label("Approve", systemImage: "checkmark")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "4ade80"))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Color(hex: "4ade80").opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: { resolve(approved: true) }) {  // modify = approve with note for now
                    Text("Modify")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: { resolve(approved: false) }) {
                    Text("Reject")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }

    func opBadge(_ op: String) -> some View {
        let (label, color): (String, Color) = switch op {
        case "edit":   ("edit",   Color(hex: "7c6fff"))
        case "create": ("create", Color(hex: "4ade80"))
        case "run":    ("run",    Color(hex: "faad14"))
        case "delete": ("delete", Color(hex: "f87171"))
        default:       (op,       .white.opacity(0.4))
        }
        return Text(label)
            .font(.system(size: 9))
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    func resolve(approved: Bool) {
        store.resolveApproval(id: request.requestID, approved: approved)
        NotificationCenter.default.post(
            name: .approvalResolved,
            object: nil,
            userInfo: ["requestID": request.requestID, "approved": approved]
        )
    }
}

extension Notification.Name {
    static let approvalResolved = Notification.Name("approvalResolved")
}
