import Testing
import UIKit
import Diagnostics
@testable import SimpleRouter

@MainActor
struct AppRouterStateTests {

    @Test func showRootChangesRootAndTransition() {
        let router = makeTestRouter()
        #expect(router.root(as: TestRoot.self) == .auth)

        router.showRoot(TestRoot.tutorial, transition: .top)

        #expect(router.root(as: TestRoot.self) == .tutorial)
        #expect(router.rootTransition == .top)
    }

    // Re-showing the same root value must still bump the generation. A root host
    // folds the generation into its root identity, so without this a repeated
    // showRoot is a silent no-op and view-owned stacks (e.g. an auth deep-link
    // path) never re-apply. Regression guard for that bug.
    @Test func showRootBumpsGenerationEvenWhenRootValueUnchanged() {
        let router = makeTestRouter()
        let initialGeneration = router.rootGeneration

        router.showRoot(TestRoot.main)
        let afterSwitch = router.rootGeneration
        #expect(afterSwitch > initialGeneration)

        router.showRoot(TestRoot.main)
        #expect(router.root(as: TestRoot.self) == .main)
        #expect(router.rootGeneration > afterSwitch)
    }

    // The root host rebuilds its content from the published change, so every
    // showRoot must reach `onRootChange` with the root, generation, transition, and
    // animation flag.
    @Test func showRootNotifiesOnRootChange() {
        let router = makeTestRouter()
        var changes: [RootChange] = []
        router.onRootChange = { changes.append($0) }

        router.showRoot(TestRoot.main)
        router.showRoot(TestRoot.main, animated: false, transition: .top)

        #expect(changes.map(\.generation) == [1, 2])
        #expect(changes.allSatisfy { $0.root(as: TestRoot.self) == .main })
        #expect(changes.first?.transition == .fade)
        #expect(changes.first?.animated == true)
        #expect(changes.last?.transition == .top)
        #expect(changes.last?.animated == false)
    }

    @Test func showAndDismissSheet() {
        let router = makeTestRouter(host: TestPresentationHost())
        #expect(router.sheet == nil)

        router.present(TestPresentedRoute(id: 1), as: .sheet())

        #expect(router.sheet?.destination == AnyRoute(TestPresentedRoute(id: 1)))
        #expect(router.sheet?.options.detents == [.large])

        router.dismissSheet()
        #expect(router.sheet == nil)
    }

    @Test func showAndDismissCover() {
        let router = makeTestRouter(host: TestPresentationHost())

        router.present(TestPresentedRoute(id: 3), as: .cover)

        #expect(router.fullScreenCover?.destination == AnyRoute(TestPresentedRoute(id: 3)))

        router.dismissCover()
        #expect(router.fullScreenCover == nil)
    }

    // Single slot: a second sheet replaces the first instead of queueing behind it.
    @Test func secondPresentationReplacesTheFirst() {
        let router = makeTestRouter(host: TestPresentationHost())

        router.present(TestPresentedRoute(id: 1), as: .sheet())
        router.present(TestPresentedRoute(id: 2), as: .sheet(SheetOptions(detents: [.medium, .large])))

        #expect(router.sheet?.destination == AnyRoute(TestPresentedRoute(id: 2)))
        #expect(router.sheet?.options.detents == [.medium, .large])

        router.present(TestPresentedRoute(id: 3), as: .cover)
        #expect(router.fullScreenCover?.destination == AnyRoute(TestPresentedRoute(id: 3)))
    }

    @Test func dismissAllPresentationsClearsEverything() {
        let router = makeTestRouter(host: TestPresentationHost())
        router.present(TestPresentedRoute(id: 1), as: .sheet())
        router.showAlert(title: "T")
        router.showConfirmationDialog(title: "D", actions: [])

        router.dismissAllPresentations()

        #expect(router.sheet == nil)
        #expect(router.fullScreenCover == nil)
        #expect(router.alert == nil)
        #expect(router.confirmationDialog == nil)
    }

    @Test func showAndDismissAlertAndDialog() {
        let router = makeTestRouter(host: TestPresentationHost())

        router.showAlert(title: "Saved", message: "Your changes were saved.")
        #expect(router.alert?.title == "Saved")
        #expect(router.alert?.message == "Your changes were saved.")

        router.showConfirmationDialog(title: "Delete?", actions: [AppDialogAction(title: "Delete", role: .destructive) {}])
        #expect(router.confirmationDialog?.title == "Delete?")
        #expect(router.confirmationDialog?.actions.count == 1)

        router.dismissConfirmationDialog()
        #expect(router.confirmationDialog == nil)
    }

    // A route with no rendering of its own is built by the app's factory.
    @Test func presentingARouteThatDoesNotRenderItselfUsesTheFactory() {
        let router = makeTestRouter(host: TestPresentationHost())
        let screen = UIViewController()
        router.makeViewController = { _ in screen }

        router.present(TestInjectedRoute(name: "loginSheet"), as: .sheet())

        #expect(router.sheet?.destination == AnyRoute(TestInjectedRoute(name: "loginSheet")))
    }

    // MARK: - Navigator

    @Test func navigatorPushesOntoInjectedStack() {
        let router = makeTestRouter()
        let stack = NavStack<AnyRoute>("test", router: router)
        let navigator = Navigator(stack: stack, router: router)

        navigator.routeTo(TestPresentedRoute(id: 4))

        #expect(stack.routes == [AnyRoute(TestPresentedRoute(id: 4))])
        #expect(router.sheet == nil)
        #expect(router.fullScreenCover == nil)
    }

    @Test func navigatorForwardsRootSwitchesAndPresentationsToRouter() {
        let router = makeTestRouter(host: TestPresentationHost())
        let stack = NavStack<AnyRoute>("test", router: router)
        let navigator = Navigator(stack: stack, router: router)

        navigator.routeTo(TestPresentedRoute(id: 5), presentation: .sheet())
        navigator.routeTo(TestPresentedRoute(id: 6), presentation: .cover)
        navigator.showRoot(TestRoot.main, transition: .top)

        #expect(stack.isEmpty)
        #expect(router.sheet?.destination == AnyRoute(TestPresentedRoute(id: 5)))
        #expect(router.fullScreenCover?.destination == AnyRoute(TestPresentedRoute(id: 6)))
        #expect(router.root(as: TestRoot.self) == .main)
        #expect(router.rootTransition == .top)
    }

    // MARK: - SheetOptions mapping

    // The SwiftUI sheet configuration has UIKit equivalents; the mapping is the
    // only place the two detent vocabularies meet.
    @Test func sheetOptionsMapToUIKitSheetConfiguration() {
        let options = SheetOptions(
            detents: [.medium, .large],
            dragIndicator: .visible,
            cornerRadius: 24,
            interactiveDismissDisabled: true
        )

        #expect(options.uiDetents.map(\.identifier) == [.medium, .large])
        #expect(options.prefersGrabberVisible)
        #expect(options.cornerRadius == 24)
        #expect(options.interactiveDismissDisabled)
    }

    @Test func singleDetentSheetHidesTheGrabberByDefault() {
        #expect(SheetOptions().uiDetents.map(\.identifier) == [.large])
        #expect(!SheetOptions().prefersGrabberVisible)

        #expect(SheetOptions(detents: [.large], dragIndicator: .hidden).uiDetents.map(\.identifier) == [.large])
        #expect(!SheetOptions(detents: [.large], dragIndicator: .hidden).prefersGrabberVisible)

        #expect(SheetOptions.bottom.detents == [.medium, .large])
    }
}
