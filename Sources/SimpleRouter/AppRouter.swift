import UIKit
import Diagnostics

/// A root change published to ``AppRouter/onRootChange``.
public struct RootChange {

    /// The new root, type-erased. Read it typed with ``root(as:)``.
    public let root: AnyHashable

    /// Monotonic generation of this change, incremented on every
    /// ``AppRouter/showRoot(_:animated:transition:)`` — including re-shows of the
    /// current root value.
    public let generation: Int

    /// Transition the host should use for this change.
    public let transition: RootTransition

    /// Whether the host should animate the swap.
    public let animated: Bool

    public init(
        root: AnyHashable,
        generation: Int,
        transition: RootTransition,
        animated: Bool = true
    ) {
        self.root = root
        self.generation = generation
        self.transition = transition
        self.animated = animated
    }

    /// This change's root typed as `T`, or `nil` if the host shows another root
    /// type.
    public func root<T: Hashable>(as type: T.Type) -> T? {
        root.base as? T
    }
}

/// Default root and presentation router.
///
/// Owns the current app root and the presentation state for sheets, covers,
/// alerts, and confirmation dialogs. The root is type-erased; read it back typed
/// with ``root(as:)``. Non-generic, so a screen holds exactly one router.
///
/// The app wires two things once, on its root host:
/// - ``onRootChange`` — rebuild the visible root for `change.root`.
/// - ``presentingViewControllerProvider`` — the view controller modals are
///   presented from. ``AppRouter`` resolves the top-most controller from it.
///
/// And, when routes that need injected dependencies are presented by the router,
/// ``makeViewController`` resolves their screens.
@MainActor
public final class AppRouter {

    /// Root currently shown by the app's root host, type-erased.
    /// Read with ``root(as:)``.
    public private(set) var root: AnyHashable

    /// Transition applied by the root host for the latest root change.
    public private(set) var rootTransition: RootTransition

    /// Monotonic counter bumped on every ``showRoot(_:animated:transition:)``,
    /// including re-shows of the current root value. A host folds it into its
    /// root identity so re-showing a root re-establishes it instead of silently
    /// no-opping when the value is unchanged.
    public private(set) var rootGeneration: Int = 0

    /// Called after every root change, so the app's root host can swap children.
    public var onRootChange: (@MainActor (RootChange) -> Void)?

    /// Resolves the view controller presentations are made from. The router walks
    /// to its top-most controller. When unset or returning `nil`, presentations
    /// are logged and trapped (`assertionFailure`): a missing provider is an app
    /// wiring bug, not a runtime condition.
    public var presentingViewControllerProvider: (@MainActor () -> UIViewController?)?

    /// Resolves the view controller for a route the router presents itself.
    ///
    /// Defaults to `nil`, which renders routes conforming to ``RenderableRoute``
    /// and traps for any other route. Set it when the app builds screens through
    /// its own factory (routes that need injected dependencies).
    public var makeViewController: (@MainActor (AnyRoute) -> UIViewController)?

    /// Active sheet destination plus configuration, or `nil` when none is shown.
    public private(set) var sheet: SheetPresentation?

    /// Active full-screen cover destination, or `nil` when none is shown.
    public private(set) var fullScreenCover: CoverPresentation?

    /// Active alert content, or `nil` when none is shown.
    public private(set) var alert: AppAlert?

    /// Active confirmation dialog content, or `nil` when none is shown.
    public private(set) var confirmationDialog: AppConfirmationDialog?

    /// Optional sink for router diagnostics.
    private let logger: (any Log)?

    /// UIKit presentation mechanics for the four surfaces above.
    private let presentations = PresentationCoordinator()

    public init(
        root: some Hashable,
        initialTransition: RootTransition = .fade,
        logger: (any Log)? = nil
    ) {
        self.root = AnyHashable(root)
        self.rootTransition = initialTransition
        self.logger = logger

        presentations.presenterViewProvider = { [weak self] in
            guard let self else { return nil }
            guard let provider = self.presentingViewControllerProvider else {
                self.logRouterMessage(
                    "no presenting view controller provider — presentation ignored",
                    category: .presentation
                )
                assertionFailure(
                    "AppRouter.presentingViewControllerProvider must be set by the app's root host before presenting."
                )
                return nil
            }
            guard let presenter = provider() else {
                self.logRouterMessage(
                    "presenting view controller provider returned nil — presentation ignored",
                    category: .presentation
                )
                assertionFailure(
                    "AppRouter.presentingViewControllerProvider returned no view controller."
                )
                return nil
            }
            return presenter
        }

        presentations.onModalDismissed = { [weak self] controller in
            guard let self else { return }
            self.logRouterMessage("user dismissed \(controller)", category: .presentation)
            self.sheet = nil
            self.fullScreenCover = nil
        }

        presentations.onAlertDismissed = { [weak self] controller in
            guard let self else { return }
            self.logRouterMessage("user dismissed \(controller)", category: .presentation)
            self.alert = nil
            self.confirmationDialog = nil
        }
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

    /// Shows `root` by publishing a ``RootChange`` to ``onRootChange``.
    ///
    /// The generation always increments, even when `root` equals the current
    /// root, so re-showing a root re-establishes the content owned by it (an auth
    /// deep-link path, for example) instead of no-opping.
    func showRoot(
        _ root: some Hashable,
        animated: Bool = true,
        transition: RootTransition = .fade
    ) {
        logRouterMessage("showRoot from \(self.root) to \(root)", category: .router)

        let change = RootChange(
            root: AnyHashable(root),
            generation: rootGeneration + 1,
            transition: transition,
            animated: animated
        )
        rootTransition = change.transition
        rootGeneration = change.generation
        self.root = change.root
        onRootChange?(change)
    }
}

// MARK: - Route Presentations

public extension AppRouter {

    /// Presents `route` as a sheet or a cover. Pushing is not the router's job,
    /// so `.push` traps.
    func present(_ route: some Hashable, as presentation: Presentation) {
        switch presentation {
        case .push:
            assertionFailure("Use NavStack.push(_:) or Navigator.routeTo(_:) for push navigation.")
        case .sheet, .cover:
            let destination = AnyRoute(route)
            guard let viewController = makeViewController?(destination) ?? destination.renderedViewController else {
                logRouterMessage(
                    "route \(destination) does not render itself and AppRouter.makeViewController is not set",
                    category: .presentation
                )
                assertionFailure("Set AppRouter.makeViewController to present routes that do not render themselves.")
                return
            }
            show(viewController, destination: destination, as: presentation)
        }
    }

    private func show(
        _ viewController: UIViewController,
        destination: AnyRoute,
        as presentation: Presentation
    ) {
        switch presentation {
        case .push:
            assertionFailure("Use NavStack.push(_:) or Navigator.routeTo(_:) for push navigation.")

        case .sheet(let options):
            logRouterMessage("presentSheet \(destination)", category: .presentation)
            sheet = SheetPresentation(destination: destination, options: options)
            viewController.modalPresentationStyle = .pageSheet
            if let sheetController = viewController.sheetPresentationController {
                sheetController.detents = options.uiDetents
                sheetController.prefersGrabberVisible = options.prefersGrabberVisible
                if let cornerRadius = options.cornerRadius {
                    sheetController.preferredCornerRadius = cornerRadius
                }
            }
            viewController.isModalInPresentation = options.interactiveDismissDisabled
            presentations.presentModal(viewController, animated: true)

        case .cover:
            logRouterMessage("presentCover \(destination)", category: .presentation)
            fullScreenCover = CoverPresentation(destination: destination)
            viewController.modalPresentationStyle = .fullScreen
            presentations.presentModal(viewController, animated: true)
        }
    }
}

// MARK: - Presentations

public extension AppRouter {

    /// Dismisses the sheet, if one is shown. A cover is left alone.
    func dismissSheet() {
        logRouterMessage("dismissSheet current=\(String(describing: sheet?.destination))", category: .presentation)
        guard sheet != nil else { return }
        sheet = nil
        presentations.dismissModal()
    }

    /// Dismisses the full-screen cover, if one is shown. A sheet is left alone.
    func dismissCover() {
        logRouterMessage("dismissCover current=\(String(describing: fullScreenCover?.destination))", category: .presentation)
        guard fullScreenCover != nil else { return }
        fullScreenCover = nil
        presentations.dismissModal()
    }

    /// Shows a single-button alert.
    func showAlert(title: String, message: String? = nil) {
        logRouterMessage("showAlert title=\(title)", category: .presentation)
        alert = AppAlert(title: title, message: message)

        let controller = UIAlertController(title: title, message: message, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.alert = nil
        })
        presentations.presentAlertController(controller)
    }

    /// Shows an action sheet built from `actions`.
    func showConfirmationDialog(
        title: String,
        message: String? = nil,
        titleVisibility: DialogTitleVisibility = .automatic,
        actions: [AppDialogAction]
    ) {
        logRouterMessage("showConfirmationDialog title=\(title)", category: .presentation)
        confirmationDialog = AppConfirmationDialog(
            title: title,
            message: message,
            titleVisibility: titleVisibility,
            actions: actions
        )

        // UIKit action sheets always have room for a title; `.hidden` drops it.
        let controller = UIAlertController(
            title: titleVisibility == .hidden ? nil : title,
            message: message,
            preferredStyle: .actionSheet
        )
        for action in actions {
            controller.addAction(UIAlertAction(title: action.title, style: action.uiStyle) { [weak self] _ in
                action.handler()
                self?.confirmationDialog = nil
            })
        }
        presentations.presentAlertController(controller)
    }

    /// Dismisses the confirmation dialog, if one is shown.
    func dismissConfirmationDialog() {
        logRouterMessage("dismissConfirmationDialog", category: .presentation)
        guard confirmationDialog != nil else { return }
        confirmationDialog = nil
        presentations.dismissAlertController()
    }

    /// Dismisses every presentation the router owns: sheet, cover, alert, dialog.
    func dismissAllPresentations() {
        logRouterMessage("dismissAllPresentations", category: .presentation)
        sheet = nil
        fullScreenCover = nil
        alert = nil
        confirmationDialog = nil
        presentations.dismissAll()
    }
}
