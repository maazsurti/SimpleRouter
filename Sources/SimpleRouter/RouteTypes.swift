import UIKit

/// A route that builds its own view controller.
///
/// Co-locates a route with its screen (one self-contained "level", like a
/// Codable struct per JSON level), so a navigation stack needs no central
/// `switch`.
public protocol RenderableRoute: Hashable {

    /// The view controller shown when this route is pushed or presented.
    @MainActor func makeViewController() -> UIViewController
}
