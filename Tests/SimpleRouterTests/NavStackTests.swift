import Testing
import UIKit
import Diagnostics
@testable import SimpleRouter

@MainActor
struct NavStackTests {

    // MARK: - Inspect

    @Test func pushExposesTopDepthAndContents() {
        let stack = makeIntStack()
        #expect(stack.isEmpty)
        stack.push(1)
        stack.push(2)
        #expect(stack.depth == 2)
        #expect(stack.top == 2)
        #expect(stack.contains(1))
        #expect(!stack.contains(99))
    }

    // MARK: - Mutate

    @Test func popRemovesTop() {
        let stack = makeIntStack(routes: [1, 2, 3])
        stack.pop()
        #expect(stack.routes == [1, 2])
    }

    @Test func popToTrimsAboveTarget() {
        let stack = makeIntStack(routes: [1, 2, 3, 4])
        stack.pop(to: 2)
        #expect(stack.routes == [1, 2])
    }

    @Test func popCountClamps() {
        // Intent: a wrong count must never crash or read out of bounds; it is
        // clamped to the available depth.
        var misuses: [String] = []
        let stack = makeIntStack(routes: [1, 2], onMisuse: { misuses.append($0) })
        stack.pop(5)
        #expect(stack.isEmpty)
        #expect(misuses.count == 1)
    }

    @Test func popToRootClears() {
        let stack = makeIntStack(routes: [1, 2, 3])
        stack.popToRoot()
        #expect(stack.isEmpty)
    }

    @Test func replaceSetsWholeStack() {
        let stack = makeIntStack(routes: [1])
        stack.replace(with: [7, 8, 9])
        #expect(stack.routes == [7, 8, 9])
    }

    // MARK: - Wrong-route detection (the explicit "loud on misuse" requirement)

    @Test func popOnEmptyIsLoggedNoOp() {
        var misuses: [String] = []
        let log = RecordingLog()
        let stack = makeIntStack(log: log, onMisuse: { misuses.append($0) })

        stack.pop()

        #expect(stack.isEmpty)              // safe no-op
        #expect(misuses.count == 1)         // misuse reported
        #expect(log.messages.contains { $0.contains("⚠️") && $0.contains("test") })
    }

    @Test func popToMissingRouteIsLoggedNoOp() {
        var misuses: [String] = []
        let stack = makeIntStack(routes: [1, 2], onMisuse: { misuses.append($0) })

        stack.pop(to: 99)

        #expect(stack.routes == [1, 2])     // unchanged — wrong route ignored
        #expect(misuses.count == 1)
        #expect(misuses[0].contains("99"))  // names the offending route
    }

    @Test func validOpsDoNotReportMisuse() {
        var misuses: [String] = []
        let stack = makeIntStack(onMisuse: { misuses.append($0) })

        stack.push(1)
        stack.pop()
        stack.push(2)
        stack.popToRoot()

        #expect(misuses.isEmpty)
    }

    // MARK: - Navigation controller

    // The stack is the single owner of both the routes and the navigation
    // controller, so every mutation has to keep the two in step.
    @Test func pushAndPopDriveTheNavigationController() {
        let stack = makeIntStack()
        let root = UIViewController()
        stack.setRootViewController(root)
        #expect(stack.navigationController.viewControllers == [root])

        stack.push(1)
        #expect(stack.routes == [1])
        #expect(stack.navigationController.viewControllers.count == 2)
        #expect(stack.navigationController.topViewController === stack.navigationController.viewControllers[1])

        stack.pop()
        #expect(stack.routes.isEmpty)
        #expect(stack.navigationController.viewControllers == [root])
    }

    @Test func popToRootKeepsTheRootViewController() {
        let stack = makeIntStack()
        let root = UIViewController()
        stack.setRootViewController(root)
        stack.push(1)
        stack.push(2)

        stack.popToRoot()

        #expect(stack.isEmpty)
        #expect(stack.navigationController.viewControllers == [root])
    }

    @Test func replaceRebuildsTheRoutesAboveTheRoot() {
        let stack = makeIntStack(routes: [1])
        let root = UIViewController()
        stack.setRootViewController(root)
        #expect(stack.navigationController.viewControllers.count == 2)

        stack.replace(with: [7, 8])

        #expect(stack.routes == [7, 8])
        #expect(stack.navigationController.viewControllers.first === root)
        #expect(stack.navigationController.viewControllers.count == 3)
    }

    // A swipe-back pops in UIKit without going through the stack, so the stack
    // adopts whatever the navigation controller shows once the transition lands.
    @Test func userDrivenPopIsAdoptedIntoRoutes() {
        let stack = makeIntStack()
        let root = UIViewController()
        stack.setRootViewController(root)
        stack.push(1)
        stack.push(2)
        #expect(stack.routes == [1, 2])

        let navigationController = stack.navigationController
        let remaining = Array(navigationController.viewControllers.prefix(2))
        navigationController.setViewControllers(remaining, animated: false)
        stack.navigationController(navigationController, didShow: remaining[1], animated: false)

        #expect(stack.routes == [1])
    }

    // MARK: - Navigator injection

    @Test func pushInjectsTheNavigatorIntoScreens() {
        let router = makeTestRouter()
        var screens: [TestScreenViewController] = []
        let stack = NavStack<AnyRoute>("main.home", router: router, makeViewController: { _ in
            let screen = TestScreenViewController()
            screens.append(screen)
            return screen
        })

        stack.push(TestInjectedRoute(name: "login"))

        #expect(stack.routes == [AnyRoute(TestInjectedRoute(name: "login"))])
        #expect(screens.count == 1)
        #expect(screens.first?.navigator === stack.navigator)
    }

    @Test func setRootViewControllerInjectsTheNavigator() {
        let router = makeTestRouter()
        let stack = NavStack<AnyRoute>("main.home", router: router)
        let root = TestScreenViewController()

        stack.setRootViewController(root)

        #expect(root.navigator === stack.navigator)
        #expect(stack.navigationController.viewControllers == [root])
    }

    // MARK: - AnyRoute box

    @Test func anyRouteEqualityFollowsUnderlyingValue() {
        #expect(AnyRoute(TestPresentedRoute(id: 1)) == AnyRoute(TestPresentedRoute(id: 1)))
        #expect(AnyRoute(TestPresentedRoute(id: 1)) != AnyRoute(TestPresentedRoute(id: 2)))
        #expect(AnyRoute(TestInjectedRoute(name: "a")) != AnyRoute(TestPresentedRoute(id: 1)))
    }

    @Test func navStackOfAnyRouteConveniences() {
        let router = makeTestRouter()
        let stack = NavStack<AnyRoute>("main.home", router: router)

        stack.push(TestPresentedRoute(id: 1))
        stack.push(TestPresentedRoute(id: 2))

        #expect(stack.depth == 2)
        #expect(stack.contains(TestPresentedRoute(id: 1)))

        stack.pop(to: TestPresentedRoute(id: 1))
        #expect(stack.depth == 1)
    }

    // Any Hashable route is boxable; only rendering needs the factory, which is
    // what lets a route that needs injected dependencies stay a plain value.
    @Test func anyRouteCarriesRoutesThatDoNotRenderThemselves() {
        let router = makeTestRouter()
        var rendered: [AnyRoute] = []
        let stack = NavStack<AnyRoute>("auth", router: router, makeViewController: { route in
            rendered.append(route)
            return UIViewController()
        })

        stack.push(TestInjectedRoute(name: "login"))
        stack.push(TestPresentedRoute(id: 2))

        #expect(rendered == [AnyRoute(TestInjectedRoute(name: "login")), AnyRoute(TestPresentedRoute(id: 2))])
        #expect(stack.routes == [AnyRoute(TestInjectedRoute(name: "login")), AnyRoute(TestPresentedRoute(id: 2))])
        #expect(stack.navigationController.viewControllers.count == 2)
    }

    @Test func selfRenderingRoutesRenderThroughTheBox() {
        let stack = NavStack<AnyRoute>("main.home", router: makeTestRouter())
        let boxed = AnyRoute(TestInjectedRoute(name: "login"))

        #expect(boxed.renderedViewController == nil)
        #expect(AnyRoute(TestPresentedRoute(id: 7)).renderedViewController != nil)
        #expect(stack.routes.isEmpty)
    }
}

// MARK: - Helpers

@MainActor
private func makeIntStack(
    routes: [Int] = [],
    log: (any Log)? = nil,
    onMisuse: @escaping @MainActor (String) -> Void = { assertionFailure($0) }
) -> NavStack<Int> {
    NavStack<Int>(
        "test",
        router: makeTestRouter(),
        routes: routes,
        log: log,
        makeViewController: { _ in UIViewController() },
        onMisuse: onMisuse
    )
}
