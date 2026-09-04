import Foundation
import Observation

enum ModelStatusLine: Equatable {
    case notDownloaded
    case downloading(percent: Int)
    case starting
    case ready

    var text: String {
        switch self {
        case .notDownloaded: "Model not downloaded"
        case .downloading(let percent): "Downloading model \(percent)%"
        case .starting: "Starting local model"
        case .ready: "Local model ready"
        }
    }
}

/// State the notch surface renders. The controller mutates it; the SwiftUI view observes it.
@Observable
final class NotchViewModel {
    var state: NotchState = .idle
    var geometry: NotchGeometry
    /// Height the open content wants, measured by the view. Zero until first layout.
    var contentHeight: CGFloat = 0
    var isContentVisible = false
    var input = ""
    var modelStatus: ModelStatusLine = .notDownloaded
    var transientStatus: String?
    var showsEscapeHint: Bool

    init(geometry: NotchGeometry, showsEscapeHint: Bool) {
        self.geometry = geometry
        self.showsEscapeHint = showsEscapeHint
    }

    var surfaceSize: CGSize {
        geometry.size(for: state, contentHeight: contentHeight)
    }

    var statusText: String {
        transientStatus ?? modelStatus.text
    }
}
