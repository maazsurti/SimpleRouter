import UIKit
import Diagnostics
@testable import SimpleRouter

enum TestRoot: Hashable { case auth, main, tutorial }

/// A route that renders itself, so the router and the stacks can build its screen
/// without an app factory.
struct TestPresentedRoute: RenderableRoute {
    let id: Int

    @MainActor
    func makeViewController() -> UIViewController {
        TestScreenViewController()
    }
}

/// A route with no rendering of its own: the app's factory builds its screen.
struct TestInjectedRoute: Hashable {
    let name: String
}

/// A screen that records the navigator its stack injected.
@MainActor
final class TestScreenViewController: UIViewController, NavigatorProviding {
    var navigator: Navigator?
}

/// A `Log` that records written messages so tests can assert what was logged.
final class RecordingLog: Log, @unchecked Sendable {
    private(set) var messages: [String] = []

    func write(_ message: String, level: LogLevel, category: String) {
        messages.append(message)
    }
}

/// The view controller a router presents from during a test.
///
/// Presentations stay state-only here: this controller's view belongs to no window,
/// so UIKit ends the presentation with its standard "not in the window hierarchy"
/// notice. What these tests assert is the router's presentation *state*; the demo's
/// UI test covers a modal actually appearing on screen.
@MainActor
final class TestPresentationHost {
    let rootViewController = UIViewController()
}

/// A router whose presentations have a presenter.
@MainActor
func makeTestRouter() -> AppRouter {
    makeTestRouter(host: TestPresentationHost())
}

/// A router wired to `host`.
///
/// The provider captures the host strongly, so a host a test passes inline stays
/// alive as the presenter for as long as the router does.
@MainActor
func makeTestRouter(host: TestPresentationHost) -> AppRouter {
    let router = AppRouter(root: TestRoot.auth)
    router.presentingViewControllerProvider = { host.rootViewController }
    return router
}
