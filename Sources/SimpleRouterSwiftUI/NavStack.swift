import SwiftUI
import Diagnostics

/// A typed, inspectable navigation stack bound to a single `NavigationStack(path:)`.
///
/// Holds the live route array for one stack — a root's stack, or one tab's
/// stack. Every mutation is named and bounded, and misuse (popping past the
/// root, or popping to a route that is not on the stack) is logged and, in
/// debug, trapped, so a wrong route surfaces immediately instead of corrupting
/// navigation silently.
///
/// The stack is never a black box: `top`, `depth`, and `contains(_:)` read its
/// real contents, unlike a type-erased `NavigationPath`.
@MainActor
@Observable
public final class NavStack<Route: Hashable> {

    /// Identifies this stack in logs, e.g. `"auth"` or `"main.home"`.
    public let label: String

    /// The live route array. Mutated only through the methods below, or through
    /// the `path` binding that `NavigationStack` writes on system back-navigation.
    public private(set) var routes: [Route]

    /// Optional sink for stack mutation diagnostics.
    private let log: (any Log)?

    /// Handler called when a stack operation cannot be completed safely.
    private let onMisuse: @MainActor (String) -> Void

    /// - Parameters:
    ///   - label: name used in log lines.
    ///   - routes: initial contents (defaults to an empty root stack).
    ///   - log: sink for navigation traces; `nil` disables logging entirely.
    ///   - onMisuse: invoked when an operation references a route that is not on
    ///     the stack, or pops past the root. Defaults to `assertionFailure` so
    ///     wrong routes trap in debug and no-op in release. Tests can pass a
    ///     recording closure to verify detection without trapping.
    public init(
        _ label: String,
        routes: [Route] = [],
        log: (any Log)? = nil,
        onMisuse: @escaping @MainActor (String) -> Void = { assertionFailure($0) }
    ) {
        self.label = label
        self.routes = routes
        self.log = log
        self.onMisuse = onMisuse
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

    // MARK: - Mutate

    /// Push a route onto the top of the stack.
    public func push(_ route: Route) {
        routes.append(route)
        trace("push \(route) → depth \(routes.count)")
    }

    /// Pop the top route. Popping the root is a logged no-op, not a crash.
    public func pop() {
        guard let removed = routes.popLast() else {
            misuse("pop on empty '\(label)' stack — ignored")
            return
        }
        trace("pop \(removed) → depth \(routes.count)")
    }

    /// Pop `count` routes. Counts above the current depth are clamped and logged.
    public func pop(_ count: Int) {
        guard count > 0 else { return }
        if count > routes.count {
            misuse("pop(\(count)) exceeds '\(label)' depth \(routes.count) — clamped")
        }
        routes.removeLast(min(count, routes.count))
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
        trace("pop(to: \(route)) → depth \(routes.count)")
    }

    /// Pop every route back to the root.
    public func popToRoot() {
        let count = routes.count
        routes.removeAll()
        trace("popToRoot (removed \(count))")
    }

    /// Replace the whole stack in one step, e.g. after app-owned URL parsing
    /// chooses a destination.
    public func replace(with routes: [Route]) {
        self.routes = routes
        trace("replace → \(routes)")
    }

    // MARK: - NavigationStack binding

    /// Two-way binding for `NavigationStack(path:)`. The setter is how SwiftUI
    /// reports user-driven back-navigation; it logs when the system trims the
    /// stack so unexpected depth changes are visible in the trace.
    public var path: Binding<[Route]> {
        Binding(
            get: { self.routes },
            set: { newValue in
                if newValue.count != self.routes.count {
                    self.trace("system path \(self.routes.count) → \(newValue.count)")
                }
                self.routes = newValue
            }
        )
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
