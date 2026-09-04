import Foundation

/// Which risk levels need the user's approval before a tool runs.
nonisolated struct ConfirmationPolicy: Sendable, Equatable {
    /// Medium-risk actions ask by default; the user can switch that off in Settings.
    var confirmsMediumRisk = true

    func requiresConfirmation(for risk: RiskLevel) -> Bool {
        switch risk {
        case .low: false
        case .medium: confirmsMediumRisk
        case .high: true
        }
    }
}

/// A pending question for the user: exactly what will happen, and how risky it is.
nonisolated struct ConfirmationRequest: Sendable, Identifiable, Equatable {
    let id: UUID
    let text: String
    let risk: RiskLevel

    /// High risk never gets a default button, so a stray Return cannot approve it.
    var allowIsDefault: Bool { risk == .medium }
}
