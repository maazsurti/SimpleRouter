import SwiftUI
import Diagnostics

/// Root container that swaps the visible root with a transition.
///
/// The app supplies the per-root content (its own `Stack`s and tab shell).
/// When initialized with an ``AppRouter``, this view owns the root-switch
/// identity, transition, and native router presentation attachment.
public struct Host<Root: Hashable, Content: View>: View {
    /// Root value used as the SwiftUI identity for the current root content.
    private let root: Root

    /// SwiftUI transition applied when `root` changes.
    private let transition: AnyTransition

    /// Router whose native presentation state should be attached, when this
    /// host is created from an `AppRouter`.
    private let router: AppRouter?

    /// Generation of the latest root change; folded into the root identity so a
    /// re-show of the same root value still rebuilds the root content.
    private let rootGeneration: Int

    /// Builder that creates the root content for the active root.
    private let content: @MainActor (Root) -> Content

    public init(
        root: Root,
        transition: AnyTransition = .opacity,
        @ViewBuilder content: @escaping @MainActor () -> Content
    ) {
        self.root = root
        self.transition = transition
        self.router = nil
        self.rootGeneration = 0
        self.content = { _ in content() }
    }

    /// Root host for the default app router. This is the normal app entry:
    /// root identity, transition, and native presentations are attached here.
    public init(
        _ router: AppRouter,
        @ViewBuilder content: @escaping @MainActor () -> Content
    ) where Root == AnyHashable {
        self.root = router.root
        self.transition = router.rootTransition.transition
        self.router = router
        self.rootGeneration = router.rootGeneration
        self.content = { _ in content() }
    }

    /// Typed root host for the default app router. Use this when root content
    /// depends on the app's concrete root enum.
    public init(
        _ router: AppRouter,
        as rootType: Root.Type = Root.self,
        default defaultRoot: Root,
        @ViewBuilder content: @escaping @MainActor (Root) -> Content
    ) {
        self.root = router.root(as: rootType) ?? defaultRoot
        self.transition = router.rootTransition.transition
        self.router = router
        self.rootGeneration = router.rootGeneration
        self.content = content
    }

    /// Root identity: the root value plus its generation, so re-showing the same
    /// root value produces a fresh identity and rebuilds the root content.
    private var rootIdentity: AnyHashable {
        AnyHashable([AnyHashable(root), AnyHashable(rootGeneration)])
    }

    /// Root content with root identity and transition applied.
    @ViewBuilder
    public var body: some View {
        let hostedContent = content(root)
            .id(rootIdentity)
            .transition(transition)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        if let router {
            hostedContent.routerPresentations(router)
        } else {
            hostedContent
        }
    }
}

public extension View {
    /// Bridges an incoming URL into app-owned routing code. Fires `handler`
    /// when `pending` becomes non-nil, then clears it. Logs receipt and
    /// clearing so unhandled URLs are visible in the trace.
    func onURL(
        _ pending: Binding<URL?>,
        log: (any Log)? = nil,
        perform handler: @escaping @MainActor (URL) -> Void
    ) -> some View {
        onChange(of: pending.wrappedValue) { _, url in
            guard let url else { return }
            log?.write("url received \(url.absoluteString)", level: .debug, category: RouterLogCategory.url.rawValue)
            handler(url)
            pending.wrappedValue = nil
            log?.write("url cleared", level: .debug, category: RouterLogCategory.url.rawValue)
        }
    }
}
