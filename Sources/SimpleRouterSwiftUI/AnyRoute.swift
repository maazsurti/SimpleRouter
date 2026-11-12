import SwiftUI

/// Type-erased box over a self-rendering ``RenderableRoute``.
///
/// Equality and hashing defer to the underlying route value, so two boxes wrap
/// equal routes when their underlying route values are equal. The destination
/// view comes from the wrapped route's ``RenderableRoute/destination`` property.
public struct AnyRoute: Hashable, CustomStringConvertible {

    /// The route value stored inside this box.
    public let base: any RenderableRoute

    /// Hashable identity used for equality and dictionary/set membership.
    private let identity: AnyHashable

    /// Factory that builds the wrapped route's destination view.
    private let makeView: @MainActor () -> AnyView

    public init(_ route: some RenderableRoute) {
        self.base = route
        self.identity = AnyHashable(route)
        self.makeView = { AnyView(route.destination) }
    }

    public static func == (lhs: AnyRoute, rhs: AnyRoute) -> Bool {
        lhs.identity == rhs.identity
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(identity)
    }

    /// The wrapped route's own destination view.
    @MainActor public var destination: AnyView { makeView() }

    /// Text representation of the wrapped route, used in logs and debug output.
    public var description: String { String(describing: base) }
}

/// Ergonomic overloads so a `NavStack<AnyRoute>` accepts self-rendering routes
/// directly, without spelling `AnyRoute(...)` at every call site.
public extension NavStack where Route == AnyRoute {
    func push(_ route: some RenderableRoute) { push(AnyRoute(route)) }
    func pop(to route: some RenderableRoute) { pop(to: AnyRoute(route)) }
    func contains(_ route: some RenderableRoute) -> Bool { contains(AnyRoute(route)) }
    func replace(with routes: [any RenderableRoute]) { replace(with: routes.map { AnyRoute($0) }) }
}
