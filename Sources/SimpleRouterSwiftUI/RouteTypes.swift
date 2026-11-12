import SwiftUI

/// A route that renders its own destination view.
///
/// Co-locates a route with its screen (one self-contained "level", like a
/// Codable struct per JSON level), so a tab navigation stack needs no central
/// `switch`.
public protocol RenderableRoute: Hashable {
    associatedtype Destination: View

    /// SwiftUI view shown when this route is pushed.
    @MainActor @ViewBuilder var destination: Destination { get }
}
