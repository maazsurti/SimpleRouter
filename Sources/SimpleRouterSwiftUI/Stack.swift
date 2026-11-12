import SwiftUI

/// A `NavigationStack` bound to a ``NavStack``.
///
/// The caller supplies the root content; pushed routes resolve through a single
/// native `navigationDestination(for:)`.
public struct Stack<Route: Hashable, Root: View, Destination: View>: View {
    /// Navigation state rendered by this `NavigationStack`.
    private let stack: NavStack<Route>

    /// Root view shown when the stack has no pushed route.
    private let root: @MainActor () -> Root

    /// Builder that maps each pushed route value to a destination view.
    private let destination: @MainActor (Route) -> Destination

    /// Navigator injected across the whole `NavigationStack` when present, so
    /// pushed destinations inherit it. `nil` for stacks that supply their own.
    ///
    /// Held in `@State`: a `NavigationStack` renders its destinations through
    /// the environment object, so building a fresh navigator on every body pass
    /// would re-identify them mid-transition and restart the push animation.
    @State private var navigator: Navigator?

    public init(
        _ stack: NavStack<Route>,
        @ViewBuilder root: @escaping @MainActor () -> Root,
        @ViewBuilder destination: @escaping @MainActor (Route) -> Destination
    ) {
        self.init(stack, navigator: nil, root: root, destination: destination)
    }

    init(
        _ stack: NavStack<Route>,
        navigator: Navigator?,
        @ViewBuilder root: @escaping @MainActor () -> Root,
        @ViewBuilder destination: @escaping @MainActor (Route) -> Destination
    ) {
        self.stack = stack
        self.root = root
        self.destination = destination
        self._navigator = State(initialValue: navigator)
    }

    /// Native `NavigationStack` bound to the route array in `stack`. When a
    /// `navigator` is owned, it is injected on the `NavigationStack` so pushed
    /// destinations inherit it.
    public var body: some View {
        let content = NavigationStack(path: stack.path) {
            root()
                .navigationDestination(for: Route.self) { route in
                    destination(route)
                }
        }

        if let navigator {
            content.environment(navigator)
        } else {
            content
        }
    }
}

/// Convenience for self-rendering routes: each ``AnyRoute`` renders its own
/// view, so no destination switch is needed at the call site.
public extension Stack where Route == AnyRoute, Destination == AnyView {
    init(_ stack: NavStack<AnyRoute>, @ViewBuilder root: @escaping @MainActor () -> Root) {
        self.init(stack, navigator: nil, root: root, destination: { $0.destination })
    }

    /// Makes a navigable stack: builds a ``Navigator`` over `stack` + `router`
    /// and injects it across the whole `NavigationStack`, so pushed destinations
    /// inherit it. This is the supported way to give a stack a `Navigator`.
    init(_ stack: NavStack<AnyRoute>, router: AppRouter, @ViewBuilder root: @escaping @MainActor () -> Root) {
        self.init(stack, navigator: Navigator(stack: stack, router: router), root: root, destination: { $0.destination })
    }
}
