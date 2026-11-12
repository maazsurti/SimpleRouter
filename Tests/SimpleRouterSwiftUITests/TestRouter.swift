import SwiftUI
import Diagnostics
@testable import SimpleRouterSwiftUI

enum TestRoot: Hashable { case auth, main, tutorial }
enum TestRoute: Hashable { case detail }

/// A `Log` that records written messages so tests can assert what was logged.
final class RecordingLog: Log, @unchecked Sendable {
    private(set) var messages: [String] = []

    func write(_ message: String, level: LogLevel, category: String) {
        messages.append(message)
    }
}

struct TestPresentedRoute: RenderableRoute {
    let id: Int
    var destination: some View { Text("Presented \(id)") }
}

@MainActor
func makeTestRouter() -> AppRouter {
    AppRouter(root: TestRoot.auth)
}
