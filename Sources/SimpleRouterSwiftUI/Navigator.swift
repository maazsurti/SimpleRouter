import SwiftUI

/// One navigation handle for a screen.
///
/// Pushes onto the screen's own stack, and forwards root switches and
/// presentations to the app router. The view that owns a stack injects a
/// `Navigator` into the environment, so child views use a single
/// `@Environment(Navigator.self)` instead of reaching for a `NavStack` and the
/// `AppRouter` separately.
@MainActor
@Observable
public final class Navigator {
    /// The stack this navigator pushes onto (the current screen's stack).
    public let stack: NavStack<AnyRoute>

    /// The app router for root switches and presentations.
    public let router: AppRouter

    public init(stack: NavStack<AnyRoute>, router: AppRouter) {
        self.stack = stack
        self.router = router
    }

    // MARK: - Routing

    /// Route to `route` with the given segue: push it onto the current stack
    /// (default), or present it as a sheet or cover.
    public func routeTo(_ route: some RenderableRoute, presentation: Presentation = .push) {
        switch presentation {
        case .push:
            stack.push(route)
        case .sheet, .cover:
            router.present(route, as: presentation)
        }
    }

    public func pop() { stack.pop() }
    public func pop(_ count: Int) { stack.pop(count) }
    public func popToRoot() { stack.popToRoot() }

    // MARK: - Root

    public func showRoot(
        _ root: some Hashable,
        animation: Animation = .easeInOut(duration: 0.25),
        transition: RootTransition = .fade
    ) {
        router.showRoot(root, animation: animation, transition: transition)
    }

    // MARK: - Presentations

    public func showAlert(title: String, message: String? = nil) {
        router.showAlert(title: title, message: message)
    }

    public func showConfirmationDialog(
        title: String,
        message: String? = nil,
        titleVisibility: Visibility = .automatic,
        actions: [AppDialogAction]
    ) {
        router.showConfirmationDialog(title: title, message: message, titleVisibility: titleVisibility, actions: actions)
    }

    public func dismissSheet() { router.dismissSheet() }
    public func dismissCover() { router.dismissCover() }
    public func dismissAllPresentations() { router.dismissAllPresentations() }
}
