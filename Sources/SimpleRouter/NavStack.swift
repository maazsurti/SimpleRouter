import UIKit
import Diagnostics

/// The navigation controller a ``NavStack`` owns.
///
/// Every screen in this design draws its own chrome, so the system bar is hidden
/// here once, for the whole stack: a screen that wants it back can still call
/// `setNavigationBarHidden(false)`.
///
/// The interactive pop gesture is re-enabled with an explicit `nil` delegate,
/// because UIKit disables swipe-back while the bar is hidden (and while its own
/// delegate is installed) — which would otherwise break swipe-back behind a custom
/// back button.
private final class BarlessNavigationController: UINavigationController {

    override func viewDidLoad() {
        super.viewDidLoad()
        setNavigationBarHidden(true, animated: false)
        interactivePopGestureRecognizer?.delegate = nil
    }
}

/// A typed, inspectable navigation stack bound to one `UINavigationController`.
///
/// Holds the live route array for one stack — a root's stack, or one screen's own
/// stack — and drives its own navigation controller. Every mutation is named and
/// bounded, and misuse (popping past the root, or popping to a route that is not
/// on the stack) is logged and, in debug, trapped, so a wrong route surfaces
/// immediately instead of corrupting navigation silently.
///
/// The stack is never a black box: `top`, `depth`, and `contains(_:)` read its
/// real contents. The navigation controller is owned here too, so a stack is the
/// single place that knows both the routes and the view controllers behind them.
/// That controller also hides the system navigation bar (screens draw their own
/// chrome) and keeps the interactive pop gesture usable behind a custom back
/// button.
///
/// - Important: The stack is the navigation controller's delegate, which UIKit
///   holds weakly. Keep a reference to the stack (or to a pushed screen's
///   ``Navigator``) for as long as its navigation controller is in use. An app
///   that installs its own delegate must forward `didShow` to the stack, or
///   user-driven pops stop updating ``routes``.
@MainActor
public final class NavStack<Route: Hashable>: NSObject, UINavigationControllerDelegate {

    /// Identifies this stack in logs, e.g. `"auth"` or `"main.home"`.
    public let label: String

    /// Navigation controller this stack drives and pushes onto.
    public let navigationController: UINavigationController

    /// The live route array: the routes pushed above the stack's root. Mutated
    /// only through the methods below, or by adopting a user-driven pop.
    public private(set) var routes: [Route]

    /// The navigator that pushes onto this stack.
    ///
    /// Only `NavStack<AnyRoute>` stacks own one, because a navigator handles
    /// type-erased routes.
    public var navigator: Navigator {
        guard let navigatorStorage else {
            preconditionFailure(
                "NavStack<\(Route.self)> does not own a Navigator; only NavStack<AnyRoute> stacks do."
            )
        }
        return navigatorStorage
    }

    /// Optional sink for stack mutation diagnostics.
    private let log: (any Log)?

    /// Handler called when a stack operation cannot be completed safely.
    private let onMisuse: @MainActor (String) -> Void

    /// Called after any navigation transition lands, so a host (the tab shell)
    /// can react to the depth changing without re-implementing the stack's rules.
    public var onDidShow: (@MainActor () -> Void)?

    /// Builds the view controller for a route this stack owns.
    private let makeViewController: @MainActor (Route) -> UIViewController

    /// Router this stack's navigator forwards presentations to.
    private let router: AppRouter

    /// Set for `NavStack<AnyRoute>` stacks, whose routes a navigator drives.
    private var navigatorStorage: Navigator?

    /// The route behind each view controller this stack pushed, so a user-driven
    /// pop can be adopted into ``routes``.
    private var routeForController: [ObjectIdentifier: Route] = [:]

    /// - Parameters:
    ///   - label: name used in log lines.
    ///   - router: router this stack's `navigator` presents and switches roots
    ///     through.
    ///   - routes: routes pushed above the stack's root. Their view controllers
    ///     are built and installed immediately.
    ///   - log: sink for navigation traces; `nil` disables logging entirely.
    ///   - makeViewController: builds the screen for a route. Routes that render
    ///     themselves return their own view controller; the app's factory handles
    ///     the rest.
    ///   - onMisuse: invoked when an operation references a route that is not on
    ///     the stack, or pops past the root. Defaults to `assertionFailure`, so
    ///     wrong routes trap in debug and no-op in release. Tests can pass a
    ///     recording closure to verify detection without trapping.
    public init(
        _ label: String,
        router: AppRouter,
        routes: [Route] = [],
        log: (any Log)? = nil,
        makeViewController: @escaping @MainActor (Route) -> UIViewController,
        onMisuse: @escaping @MainActor (String) -> Void = { assertionFailure($0) }
    ) {
        self.label = label
        self.router = router
        self.routes = routes
        self.log = log
        self.makeViewController = makeViewController
        self.onMisuse = onMisuse
        self.navigationController = BarlessNavigationController()
        super.init()

        navigationController.delegate = self
        if let anyRouteStack = self as? NavStack<AnyRoute> {
            navigatorStorage = Navigator(stack: anyRouteStack, router: router)
        }
        buildInitialRoutes()
    }

    // MARK: - Inspect

    /// The top route, or `nil` at the root.
    public var top: Route? { routes.last }

    /// Number of pushed routes above the root.
    public var depth: Int { routes.count }

    /// `true` when sitting at the root with nothing pushed.
    public var isEmpty: Bool { routes.isEmpty }

    /// Whether `route` is currently anywhere on the stack.
    public func contains(_ route: Route) -> Bool { routes.contains(route) }

    // MARK: - Root

    /// Installs the stack's root view controller and rebuilds the current
    /// ``routes`` above it. Call this once, when the screen that owns the stack is
    /// created; the root receives the stack's ``Navigator``.
    public func setRootViewController(_ rootViewController: UIViewController, animated: Bool = false) {
        (rootViewController as? NavigatorProviding)?.navigator = navigatorStorage

        var controllers = [rootViewController]
        for route in routes {
            controllers.append(makeController(for: route))
        }
        navigationController.setViewControllers(controllers, animated: animated)
    }

    // MARK: - Mutate

    /// Push a route onto the top of the stack.
    public func push(_ route: Route) {
        let controller = makeController(for: route)
        routes.append(route)
        navigationController.pushViewController(controller, animated: true)
        trace("push \(route) → depth \(routes.count)")
    }

    /// Pop the top route. Popping the root is a logged no-op, not a crash.
    public func pop() {
        guard let removed = routes.popLast() else {
            misuse("pop on empty '\(label)' stack — ignored")
            return
        }
        popViewControllers(to: routes.count)
        trace("pop \(removed) → depth \(routes.count)")
    }

    /// Pop `count` routes. Counts above the current depth are clamped and logged.
    public func pop(_ count: Int) {
        guard count > 0 else { return }
        if count > routes.count {
            misuse("pop(\(count)) exceeds '\(label)' depth \(routes.count) — clamped")
        }
        routes.removeLast(min(count, routes.count))
        popViewControllers(to: routes.count)
        trace("pop \(count) → depth \(routes.count)")
    }

    /// Pop back until `route` is the top. A no-op (logged) if `route` is not on
    /// the stack — this is the classic "wrong route" case and surfaces loudly.
    public func pop(to route: Route) {
        guard let index = routes.lastIndex(of: route) else {
            misuse("pop(to:) \(route) not on '\(label)' stack \(routes) — ignored")
            return
        }
        routes.removeSubrange(routes.index(after: index)...)
        popViewControllers(to: routes.count)
        trace("pop(to: \(route)) → depth \(routes.count)")
    }

    /// Pop every route back to the root.
    public func popToRoot() {
        let count = routes.count
        routes.removeAll()
        popViewControllers(to: 0)
        trace("popToRoot (removed \(count))")
    }

    /// Replace the whole stack in one step, e.g. after app-owned URL parsing
    /// chooses a destination, or when a root's payload seeds the pushed routes.
    /// Fresh view controllers are built for every incoming route.
    public func replace(with routes: [Route]) {
        let rootControllers = untrackedControllers()
        routeForController.removeAll()
        self.routes = routes

        var controllers = rootControllers
        for route in routes {
            controllers.append(makeController(for: route))
        }
        navigationController.setViewControllers(controllers, animated: false)
        trace("replace → \(routes)")
    }

    // MARK: - UINavigationControllerDelegate

    /// Adopts a navigation change UIKit made on its own — an interactive
    /// swipe-back or a system pop — into ``routes``.
    public func navigationController(
        _ navigationController: UINavigationController,
        didShow viewController: UIViewController,
        animated: Bool
    ) {
        syncRoutes()
        onDidShow?()
    }

    // MARK: - Building

    /// Builds the view controller for `route`, with the stack's handles injected.
    private func makeController(for route: Route) -> UIViewController {
        let controller = makeViewController(route)
        (controller as? NavigatorProviding)?.navigator = navigatorStorage
        routeForController[ObjectIdentifier(controller)] = route
        return controller
    }

    private func buildInitialRoutes() {
        guard !routes.isEmpty else { return }
        var controllers: [UIViewController] = []
        for route in routes {
            controllers.append(makeController(for: route))
        }
        navigationController.setViewControllers(controllers, animated: false)
    }

    /// Pops the navigation controller back to `depth` pushed routes.
    ///
    /// The pop APIs are used instead of `setViewControllers(_:animated:)` because
    /// UIKit only applies an *animated* `setViewControllers` to the controller
    /// array when the transition runs; a pop has to be reflected the moment the
    /// mutation returns, so the model and the controller never disagree.
    private func popViewControllers(to depth: Int) {
        var remaining = untrackedControllers()
        remaining.append(contentsOf: trackedControllers().prefix(depth))

        if let destination = remaining.last,
           navigationController.viewControllers.contains(destination),
           destination !== navigationController.viewControllers.last {
            navigationController.popToViewController(destination, animated: true)
        }

        // Safety net: if UIKit has not reflected the pop yet (or the stack was
        // installed in a different order), make the controller match the model.
        guard navigationController.viewControllers != remaining else { return }
        navigationController.setViewControllers(remaining, animated: false)
    }

    /// View controllers below every route this stack pushed — the root, plus
    /// anything an enclosing screen installed.
    private func untrackedControllers() -> [UIViewController] {
        navigationController.viewControllers.filter { routeForController[ObjectIdentifier($0)] == nil }
    }

    /// View controllers this stack pushed, in stack order.
    private func trackedControllers() -> [UIViewController] {
        navigationController.viewControllers.filter { routeForController[ObjectIdentifier($0)] != nil }
    }

    /// Adopts the navigation controller's current contents as the pushed routes.
    ///
    /// Only a shrinking stack is adopted: this stack owns every push, so a
    /// controller that looks longer than the model is UIKit mid-transition, not a
    /// change to follow. A user-driven pop (interactive swipe-back) shrinks, which
    /// is what this exists for.
    private func syncRoutes() {
        let live = navigationController.viewControllers
        let liveIdentifiers = Set(live.map(ObjectIdentifier.init))
        routeForController = routeForController.filter { liveIdentifiers.contains($0.key) }

        let pushed = live.compactMap { routeForController[ObjectIdentifier($0)] }
        guard pushed.count < routes.count else { return }

        trace("system stack \(routes.count) → \(pushed.count)")
        routes = pushed
    }

    // MARK: - Diagnostics

    private func trace(_ message: String) {
        log?.write("[\(label)] \(message)", level: .debug, category: RouterLogCategory.router.rawValue)
    }

    private func misuse(_ message: String) {
        log?.write("⚠️ [\(label)] \(message)", level: .warning, category: RouterLogCategory.router.rawValue)
        onMisuse(message)
    }
}
