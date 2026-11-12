import SwiftUI
import Diagnostics

/// Default root and presentation router.
///
/// Stores the current app root for ``Host`` and native presentation state for
/// sheets, covers, alerts, and confirmation dialogs. The root is type-erased;
/// read it back with ``root(as:)``. Non-generic so views inject it as a plain
/// `@Environment(AppRouter.self)`.
@MainActor
@Observable
public final class AppRouter {
    /// Root currently shown by `Host`, type-erased. Read with ``root(as:)``.
    public private(set) var root: AnyHashable

    /// Transition style applied by `Host` for the latest root change.
    public private(set) var rootTransition: RootTransition

    /// Monotonic counter bumped on every ``showRoot(_:animation:transition:)``,
    /// including re-shows of the current root value. ``Host`` folds it into the
    /// root identity so re-showing a root re-establishes it instead of silently
    /// no-opping when the value is unchanged.
    public private(set) var rootGeneration: Int = 0

    /// Active sheet destination plus configuration, or `nil` when none is shown.
    public var sheet: SheetPresentation?

    /// Active full-screen cover destination, or `nil` when none is shown.
    public var fullScreenCover: CoverPresentation?

    /// Active alert content, or `nil` when none is shown.
    public var alert: AppAlert?

    /// Active confirmation dialog content, or `nil` when none is shown.
    public var confirmationDialog: AppConfirmationDialog?

    /// Optional sink for router diagnostics.
    private let logger: (any Log)?

    public init(
        root: some Hashable,
        initialTransition: RootTransition = .fade,
        logger: (any Log)? = nil
    ) {
        self.root = AnyHashable(root)
        self.rootTransition = initialTransition
        self.logger = logger
    }

    /// The current root typed as `T`, or `nil` if a different type was shown.
    public func root<T: Hashable>(as type: T.Type) -> T? {
        root.base as? T
    }

    public func logRouterMessage(_ message: String, category: RouterLogCategory) {
        logger?.write(message, level: .debug, category: category.rawValue)
    }
}

// MARK: - Roots

public extension AppRouter {
    func showRoot(
        _ root: some Hashable,
        animation: Animation = .easeInOut(duration: 0.25),
        transition: RootTransition = .fade
    ) {
        let previous = self.root
        logRouterMessage("showRoot from \(previous) to \(root)", category: .router)

        withAnimation(animation) {
            rootTransition = transition
            rootGeneration += 1
            self.root = AnyHashable(root)
        }
    }
}

// MARK: - Route Presentations

public extension AppRouter {
    func present(_ route: some RenderableRoute, as presentation: Presentation) {
        switch presentation {
        case .push:
            assertionFailure("Use NavStack.push(_:) or Navigator.routeTo(_:) for push navigation.")
        case .sheet(let options):
            logRouterMessage("presentSheet \(route)", category: .presentation)
            sheet = SheetPresentation(destination: AnyRoute(route), options: options)
        case .cover:
            logRouterMessage("presentCover \(route)", category: .presentation)
            fullScreenCover = CoverPresentation(destination: AnyRoute(route))
        }
    }
}

// MARK: - Presentations

public extension AppRouter {
    func dismissSheet() {
        logRouterMessage("dismissSheet current=\(String(describing: sheet?.destination))", category: .presentation)
        sheet = nil
    }

    func dismissCover() {
        logRouterMessage("dismissCover current=\(String(describing: fullScreenCover?.destination))", category: .presentation)
        fullScreenCover = nil
    }

    func showAlert(title: String, message: String? = nil) {
        logRouterMessage("showAlert title=\(title)", category: .presentation)
        alert = AppAlert(title: title, message: message)
    }

    func showConfirmationDialog(
        title: String,
        message: String? = nil,
        titleVisibility: Visibility = .automatic,
        actions: [AppDialogAction]
    ) {
        logRouterMessage("showConfirmationDialog title=\(title)", category: .presentation)
        confirmationDialog = AppConfirmationDialog(
            title: title,
            message: message,
            titleVisibility: titleVisibility,
            actions: actions
        )
    }

    func dismissConfirmationDialog() {
        logRouterMessage("dismissConfirmationDialog", category: .presentation)
        confirmationDialog = nil
    }

    func dismissAllPresentations() {
        logRouterMessage("dismissAllPresentations", category: .presentation)
        sheet = nil
        fullScreenCover = nil
        alert = nil
        confirmationDialog = nil
    }
}
