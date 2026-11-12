import UIKit
import Diagnostics

/// Type-erased box over any `Hashable` route value.
///
/// Equality and hashing defer to the wrapped value, so two boxes compare equal
/// when their underlying route values do. A box carries no rendering logic: the
/// stack that owns the route resolves its view controller through the
/// `makeViewController` closure it was created with, which lets a route that
/// needs injected dependencies be rendered by the app's own factory.
public struct AnyRoute: Hashable, CustomStringConvertible {

    /// The route value stored inside this box.
    public let base: any Hashable

    /// Hashable identity used for equality and dictionary/set membership.
    private let identity: AnyHashable

    public init(_ route: some Hashable) {
        self.base = route
        self.identity = AnyHashable(route)
    }

    public static func == (lhs: AnyRoute, rhs: AnyRoute) -> Bool {
        lhs.identity == rhs.identity
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(identity)
    }

    /// Text representation of the wrapped route, used in logs and debug output.
    public var description: String { String(describing: base) }
}

public extension AnyRoute {

    /// The wrapped route's own view controller when it renders itself
    /// (``RenderableRoute``), or `nil` for a route the app's factory renders.
    @MainActor var renderedViewController: UIViewController? {
        (base as? any RenderableRoute)?.makeViewController()
    }
}

/// Ergonomic overloads so a `NavStack<AnyRoute>` accepts route values directly,
/// without spelling `AnyRoute(...)` at every call site.
public extension NavStack where Route == AnyRoute {
    func push(_ route: some Hashable) { push(AnyRoute(route)) }
    func pop(to route: some Hashable) { pop(to: AnyRoute(route)) }
    func contains(_ route: some Hashable) -> Bool { contains(AnyRoute(route)) }
    func replace(with routes: [any Hashable]) { replace(with: routes.map { AnyRoute($0) }) }
}

/// Convenience initializer for the common case: a stack of type-erased routes.
public extension NavStack where Route == AnyRoute {

    /// Makes a stack whose routes render themselves.
    ///
    /// - Parameters:
    ///   - label: name used in log lines.
    ///   - router: router this stack's `navigator` presents and switches roots
    ///     through.
    ///   - routes: routes pushed above the stack's root.
    ///   - log: sink for navigation traces; `nil` disables logging entirely.
    ///   - onMisuse: invoked when an operation references a route that is not on
    ///     the stack, or pops past the root.
    ///
    /// Rendering falls back to the wrapped value's own
    /// ``RenderableRoute/makeViewController()``. Pass the initializer that takes
    /// a `makeViewController` closure instead when a route needs the app to
    /// build its screen.
    convenience init(
        _ label: String,
        router: AppRouter,
        routes: [AnyRoute] = [],
        log: (any Log)? = nil,
        onMisuse: @escaping @MainActor (String) -> Void = { assertionFailure($0) }
    ) {
        self.init(
            label,
            router: router,
            routes: routes,
            log: log,
            makeViewController: { route in
                guard let viewController = route.renderedViewController else {
                    preconditionFailure(
                        "AnyRoute(\(route)) is not a RenderableRoute. Use the NavStack initializer that takes a makeViewController closure."
                    )
                }
                return viewController
            },
            onMisuse: onMisuse
        )
    }
}
