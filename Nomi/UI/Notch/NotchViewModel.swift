import Foundation
import Observation

enum ModelStatusLine: Equatable {
    case notDownloaded
    case downloading(percent: Int)
    /// On disk but not in memory yet; the first question starts it.
    case installed
    case starting
    case ready
    case lookingAtScreen

    var text: String {
        switch self {
        case .notDownloaded: "Model not downloaded"
        case .downloading(let percent): "Downloading model \(percent)%"
        case .installed: "Local model installed"
        case .starting: "Starting local model"
        case .ready: "Local model ready"
        case .lookingAtScreen: "Looking at your screen"
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
    var transientStatus: String?
    var showsEscapeHint: Bool
    private let modelManager: ModelManager

    init(geometry: NotchGeometry, showsEscapeHint: Bool, modelManager: ModelManager) {
        self.geometry = geometry
        self.showsEscapeHint = showsEscapeHint
        self.modelManager = modelManager
    }

    var modelStatus: ModelStatusLine {
        modelManager.statusLine
    }

    var surfaceSize: CGSize {
        geometry.size(for: state, contentHeight: contentHeight)
    }

    var statusText: String {
        transientStatus ?? modelStatus.text
    }
}
