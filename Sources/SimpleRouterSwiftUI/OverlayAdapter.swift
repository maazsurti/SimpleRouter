import SwiftUI

/// Adapter hook for app-owned overlay systems such as toasts or loading.
///
/// The adapter receives overlay state and returns the view rendered above the
/// wrapped content.
public protocol OverlayAdapter {
    /// State value that drives the overlay.
    associatedtype State

    /// SwiftUI view rendered above the wrapped content.
    associatedtype Body: View

    @MainActor
    @ViewBuilder
    func body(state: Binding<State>) -> Body
}

/// Adapter that renders no overlay.
public struct EmptyOverlayAdapter<State>: OverlayAdapter {
    public init() {}

    public func body(state: Binding<State>) -> EmptyView {

        EmptyView()
    }
}

public struct OverlayAttachment<Adapter: OverlayAdapter>: ViewModifier {
    /// Overlay state passed to the adapter as a binding.
    @Binding private var state: Adapter.State

    /// Renderer that turns overlay state into a SwiftUI view.
    private let adapter: Adapter

    public init(state: Binding<Adapter.State>, adapter: Adapter) {
        self._state = state
        self.adapter = adapter
    }

    public func body(content: Content) -> some View {
        content.overlay {
            adapter.body(state: $state)
        }
    }
}

public extension View {
    func overlayAdapter<Adapter: OverlayAdapter>(
        _ state: Binding<Adapter.State>,
        adapter: Adapter
    ) -> some View {
        modifier(OverlayAttachment(state: state, adapter: adapter))
    }
}
