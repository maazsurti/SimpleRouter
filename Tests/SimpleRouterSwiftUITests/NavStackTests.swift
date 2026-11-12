import Testing
import SwiftUI
@testable import SimpleRouterSwiftUI

// A self-rendering route, used to exercise NavStack<AnyRoute> and AnyRoute.
private struct DetailRoute: RenderableRoute {
    let id: Int
    var destination: some View { Text("Detail \(id)") }
}

@MainActor
struct NavStackTests {

    // MARK: - Inspect

    @Test func pushExposesTopDepthAndContents() {
        let stack = NavStack<Int>("test")
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
        let stack = NavStack<Int>("test", routes: [1, 2, 3])
        stack.pop()
        #expect(stack.routes == [1, 2])
    }

    @Test func popToTrimsAboveTarget() {
        let stack = NavStack<Int>("test", routes: [1, 2, 3, 4])
        stack.pop(to: 2)
        #expect(stack.routes == [1, 2])
    }

    @Test func popCountClamps() {
        // Intent: a wrong count must never crash or read out of bounds; it is
        // clamped to the available depth.
        var misuses: [String] = []
        let stack = NavStack<Int>("test", routes: [1, 2], onMisuse: { misuses.append($0) })
        stack.pop(5)
        #expect(stack.isEmpty)
        #expect(misuses.count == 1)
    }

    @Test func popToRootClears() {
        let stack = NavStack<Int>("test", routes: [1, 2, 3])
        stack.popToRoot()
        #expect(stack.isEmpty)
    }

    @Test func replaceSetsWholeStack() {
        let stack = NavStack<Int>("test", routes: [1])
        stack.replace(with: [7, 8, 9])
        #expect(stack.routes == [7, 8, 9])
    }

    // MARK: - Wrong-route detection (the explicit "loud on misuse" requirement)

    @Test func popOnEmptyIsLoggedNoOp() {
        var misuses: [String] = []
        let log = RecordingLog()
        let stack = NavStack<Int>(
            "auth",
            log: log,
            onMisuse: { misuses.append($0) }
        )
        stack.pop()
        #expect(stack.isEmpty)              // safe no-op
        #expect(misuses.count == 1)         // misuse reported
        #expect(log.messages.contains { $0.contains("⚠️") && $0.contains("auth") })
    }

    @Test func popToMissingRouteIsLoggedNoOp() {
        var misuses: [String] = []
        let stack = NavStack<Int>("test", routes: [1, 2], onMisuse: { misuses.append($0) })
        stack.pop(to: 99)
        #expect(stack.routes == [1, 2])     // unchanged — wrong route ignored
        #expect(misuses.count == 1)
        #expect(misuses[0].contains("99"))  // names the offending route
    }

    @Test func validOpsDoNotReportMisuse() {
        var misuses: [String] = []
        let stack = NavStack<Int>("test", onMisuse: { misuses.append($0) })
        stack.push(1)
        stack.pop()
        stack.push(2)
        stack.popToRoot()
        #expect(misuses.isEmpty)
    }

    // MARK: - NavigationStack binding

    @Test func pathBindingReadsAndWritesThrough() {
        let stack = NavStack<Int>("test", routes: [1])
        let binding = stack.path
        #expect(binding.wrappedValue == [1])
        binding.wrappedValue = [1, 2]             // SwiftUI back-nav style write
        #expect(stack.routes == [1, 2])
    }

    // MARK: - AnyRoute box

    @Test func anyRouteEqualityFollowsUnderlyingValue() {
        #expect(AnyRoute(DetailRoute(id: 1)) == AnyRoute(DetailRoute(id: 1)))
        #expect(AnyRoute(DetailRoute(id: 1)) != AnyRoute(DetailRoute(id: 2)))
    }

    @Test func navStackOfAnyRouteConveniences() {
        let stack = NavStack<AnyRoute>("main.home")
        stack.push(DetailRoute(id: 1))
        stack.push(DetailRoute(id: 2))
        #expect(stack.depth == 2)
        #expect(stack.contains(DetailRoute(id: 1)))
        stack.pop(to: DetailRoute(id: 1))
        #expect(stack.depth == 1)
    }
}
