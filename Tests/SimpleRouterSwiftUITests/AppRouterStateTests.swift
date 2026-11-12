import Testing
@testable import SimpleRouterSwiftUI

@MainActor
struct AppRouterStateTests {

    @Test func showRootChangesRootAndTransition() {
        let router = makeTestRouter()
        #expect(router.root(as: TestRoot.self) == .auth)

        router.showRoot(TestRoot.tutorial, transition: .top)

        #expect(router.root(as: TestRoot.self) == .tutorial)
        #expect(router.rootTransition == .top)
    }

    // Re-showing the same root value must still bump the generation. Host folds
    // the generation into the root identity, so without this a repeated showRoot
    // is a silent no-op and view-owned stacks (e.g. an auth deep-link path)
    // never re-apply. Regression guard for that bug.
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

    @Test func showAndDismissSheet() {
        let router = makeTestRouter()
        #expect(router.sheet == nil)

        router.present(TestPresentedRoute(id: 1), as: .sheet())

        #expect(router.sheet?.destination == AnyRoute(TestPresentedRoute(id: 1)))
        #expect(router.sheet?.options.detents == [.large])

        router.dismissSheet()
        #expect(router.sheet == nil)
    }

    @Test func showAndDismissCover() {
        let router = makeTestRouter()

        router.present(TestPresentedRoute(id: 3), as: .cover)

        #expect(router.fullScreenCover?.destination == AnyRoute(TestPresentedRoute(id: 3)))

        router.dismissCover()
        #expect(router.fullScreenCover == nil)
    }

    @Test func dismissAllPresentationsClearsEverything() {
        let router = makeTestRouter()
        router.present(TestPresentedRoute(id: 1), as: .sheet())
        router.present(TestPresentedRoute(id: 2), as: .cover)
        router.showAlert(title: "T")
        router.showConfirmationDialog(title: "D", actions: [])

        router.dismissAllPresentations()

        #expect(router.sheet == nil)
        #expect(router.fullScreenCover == nil)
        #expect(router.alert == nil)
        #expect(router.confirmationDialog == nil)
    }

    @Test func navigatorPushesOntoInjectedStack() {
        let router = makeTestRouter()
        let stack = NavStack<AnyRoute>("test")
        let navigator = Navigator(stack: stack, router: router)

        navigator.routeTo(TestPresentedRoute(id: 4))

        #expect(stack.routes == [AnyRoute(TestPresentedRoute(id: 4))])
        #expect(router.sheet == nil)
        #expect(router.fullScreenCover == nil)
    }

    @Test func navigatorForwardsRootSwitchesAndPresentationsToRouter() {
        let router = makeTestRouter()
        let stack = NavStack<AnyRoute>("test")
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
}
