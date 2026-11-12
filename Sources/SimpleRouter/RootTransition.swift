import UIKit

/// Style of an app root swap.
public enum RootTransition: Sendable {

    /// Cross-fades from the current root to the next root.
    case fade

    /// Moves the next root in from the top edge.
    case top

    /// UIKit animator the app's root host uses to swap children for this style.
    @MainActor
    public var animator: any RootTransitionAnimator {
        switch self {
        case .fade: FadeRootTransitionAnimator()
        case .top: TopRootTransitionAnimator()
        }
    }
}

/// Swaps the app host's children for a ``RootTransition``.
///
/// An animator owns the whole visual change: it puts `incoming` into the
/// container, animates it into place, removes `outgoing` once the animation
/// finishes, and then calls `completion`. The host only owns view-controller
/// containment around that call.
@MainActor
public protocol RootTransitionAnimator {

    /// Swaps `outgoing` for `incoming` inside `container`.
    /// - Parameters:
    ///   - outgoing: the root view being replaced, or `nil` for the first root.
    ///   - incoming: the root view being shown.
    ///   - container: the host's view, which the incoming view fills.
    ///   - completion: called after the swap finishes; the host finishes
    ///     containment, so it always runs exactly once.
    func animate(
        from outgoing: UIView?,
        to incoming: UIView,
        in container: UIView,
        completion: @escaping () -> Void
    )
}

/// Cross-fades the outgoing root into the incoming one.
public struct FadeRootTransitionAnimator: RootTransitionAnimator {

    /// Duration of the cross-fade.
    private static let duration: TimeInterval = 0.25

    public init() {}

    public func animate(
        from outgoing: UIView?,
        to incoming: UIView,
        in container: UIView,
        completion: @escaping () -> Void
    ) {
        incoming.frame = container.bounds
        incoming.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(incoming)

        guard let outgoing else {
            completion()
            return
        }

        incoming.alpha = 0
        UIView.animate(
            withDuration: Self.duration,
            animations: {
                incoming.alpha = 1
                outgoing.alpha = 0
            },
            completion: { _ in
                outgoing.removeFromSuperview()
                outgoing.alpha = 1
                completion()
            }
        )
    }
}

/// Slides the incoming root in from the top edge while the outgoing one leaves
/// through the same edge.
public struct TopRootTransitionAnimator: RootTransitionAnimator {

    /// Duration of the slide.
    private static let duration: TimeInterval = 0.25

    public init() {}

    public func animate(
        from outgoing: UIView?,
        to incoming: UIView,
        in container: UIView,
        completion: @escaping () -> Void
    ) {
        let bounds = container.bounds
        incoming.frame = bounds.offsetBy(dx: 0, dy: -bounds.height)
        incoming.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(incoming)

        UIView.animate(
            withDuration: Self.duration,
            animations: {
                incoming.frame = bounds
                outgoing?.frame = bounds.offsetBy(dx: 0, dy: -bounds.height)
            },
            completion: { _ in
                outgoing?.removeFromSuperview()
                completion()
            }
        )
    }
}
