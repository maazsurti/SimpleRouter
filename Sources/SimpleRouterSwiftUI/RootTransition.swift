import SwiftUI

public enum RootTransition {
    /// Cross-fades from the current root to the next root.
    case fade

    /// Moves the next root in from the top edge.
    case top

    /// SwiftUI transition used by `Host` when the root changes.
    public var transition: AnyTransition {
        switch self {
        case .fade:
            .opacity
        case .top:
            .move(edge: .top)
        }
    }
}
