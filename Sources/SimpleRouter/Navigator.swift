import UIKit

/// One navigation handle for a screen.
///
/// Pushes onto the screen's own stack, and forwards root switches and
/// presentations to the app router. It is non-generic and drives type-erased
/// routes, so a screen holds a single handle instead of reaching for a stack and
/// the ``AppRouter`` separately.
///
/// A stack injects its navigator into the view controllers it owns (its root and
/// every pushed screen) that conform to ``NavigatorProviding``, so anything below
/// the stack's root uses `navigator` rather than plumbing one through
/// initializers.
@MainActor
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
    public func routeTo(_ route: some Hashable, presentation: Presentation = .push) {
        switch presentation {
        case .push:
            stack.push(AnyRoute(route))
        case .sheet, .cover:
            router.present(route, as: presentation)
        }
    }

    /// Push `route` onto the current stack — the default of
    /// ``routeTo(_:presentation:)``.
    public func push(_ route: some Hashable) {
        stack.push(AnyRoute(route))
    }

    public func pop() { stack.pop() }

    public func pop(_ count: Int) { stack.pop(count) }

    public func popToRoot() { stack.popToRoot() }

    // MARK: - Root

    /// Switches the app root through the router.
    public func showRoot(
        _ root: some Hashable,
        animated: Bool = true,
        transition: RootTransition = .fade
    ) {
        router.showRoot(root, animated: animated, transition: transition)
    }

    // MARK: - Presentations

    public func showAlert(title: String, message: String? = nil) {
        router.showAlert(title: title, message: message)
    }

    public func showConfirmationDialog(
        title: String,
        message: String? = nil,
        titleVisibility: DialogTitleVisibility = .automatic,
        actions: [AppDialogAction]
    ) {
        router.showConfirmationDialog(
            title: title,
            message: message,
            titleVisibility: titleVisibility,
            actions: actions
        )
    }

    public func dismissSheet() { router.dismissSheet() }

    public func dismissCover() { router.dismissCover() }

    public func dismissAllPresentations() { router.dismissAllPresentations() }
}

/// A view controller that receives the ``Navigator`` of the stack it belongs to.
///
/// Adopt it on screens that live in a stack: the stack sets `navigator` when the
/// screen is installed, so `viewDidLoad` and everything after it can navigate
/// without further plumbing. Presented screens are not part of a stack, so they
/// navigate through the ``AppRouter`` instead.
@MainActor
public protocol NavigatorProviding: AnyObject {

    /// The stack's navigator; set by the stack before the screen is shown.
    var navigator: Navigator? { get set }
}
