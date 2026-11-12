import UIKit
import Diagnostics

/// Presents router-owned modals and alerts from the app's top-most view
/// controller.
///
/// ``AppRouter`` owns the presentation *state*; this type owns the UIKit
/// mechanics: resolving the view controller to present from, keeping a single
/// modal slot (presenting over an active modal dismisses it first), anchoring
/// action sheets so iPad does not trap, and reporting surfaces the user
/// dismissed so the router can clear its state.
@MainActor
final class PresentationCoordinator: NSObject, UISheetPresentationControllerDelegate {

    /// Resolves the view controller the router presents from. `nil` means the app
    /// has not configured one; the caller logs and asserts.
    var presenterViewProvider: @MainActor () -> UIViewController? = { nil }

    /// Called when the user dismissed the modal (sheet or cover).
    var onModalDismissed: @MainActor (UIViewController) -> Void = { _ in }

    /// Called when the user dismissed the alert or confirmation dialog.
    var onAlertDismissed: @MainActor (UIViewController) -> Void = { _ in }

    /// The modal (sheet or cover) on screen, if any.
    private weak var modal: UIViewController?

    /// The alert or confirmation dialog on screen, if any.
    private weak var alertController: UIViewController?

    // MARK: - Modals

    /// Presents `controller` as the router's single modal, dismissing whichever
    /// modal is on screen first.
    func presentModal(_ controller: UIViewController, animated: Bool) {
        guard let presenter = resolvePresenter() else { return }
        observeDismissal(of: controller)
        if let existing = presented(modal) {
            modal = nil
            existing.dismiss(animated: animated) { [weak self] in
                guard let self else { return }
                presenter.present(controller, animated: animated)
                self.modal = controller
            }
        } else {
            presenter.present(controller, animated: animated)
            modal = controller
        }
    }

    /// Dismisses the modal on screen, if any.
    func dismissModal(animated: Bool = true) {
        guard let existing = presented(modal) else {
            modal = nil
            return
        }
        modal = nil
        existing.dismiss(animated: animated)
    }

    // MARK: - Alerts

    /// Presents `controller` on top of whatever is on screen — an alert belongs
    /// over a sheet, so it does not dismiss the modal below it.
    func presentAlertController(_ controller: UIAlertController) {
        guard let presenter = resolvePresenter() else { return }
        observeDismissal(of: controller)
        anchorPopover(controller, to: presenter)
        if let existing = presented(alertController) {
            alertController = nil
            existing.dismiss(animated: false) { [weak self] in
                guard let self, let presenter = self.resolvePresenter() else { return }
                presenter.present(controller, animated: true)
                self.alertController = controller
            }
        } else {
            presenter.present(controller, animated: true)
            alertController = controller
        }
    }

    /// Dismisses the alert on screen, if any.
    func dismissAlertController(animated: Bool = false) {
        guard let existing = presented(alertController) else {
            alertController = nil
            return
        }
        alertController = nil
        existing.dismiss(animated: animated)
    }

    /// Dismisses every surface the router owns.
    func dismissAll() {
        dismissAlertController()
        dismissModal()
    }

    // MARK: - Resolution

    /// The top-most view controller in the presentation chain starting at the
    /// controller the app provides.
    static func topViewController(from controller: UIViewController) -> UIViewController {
        var top = controller
        while true {
            if let navigation = top as? UINavigationController,
               let visible = navigation.visibleViewController, visible !== top {
                top = visible
                continue
            }
            if let tabs = top as? UITabBarController,
               let selected = tabs.selectedViewController, selected !== top {
                top = selected
                continue
            }
            if let presented = top.presentedViewController {
                top = presented
                continue
            }
            return top
        }
    }

    private func resolvePresenter() -> UIViewController? {
        guard let base = presenterViewProvider() else { return nil }
        return Self.topViewController(from: base)
    }

    /// Only a controller UIKit is actually presenting counts as on screen; a
    /// dismissed one must not block the next presentation.
    private func presented(_ controller: UIViewController?) -> UIViewController? {
        guard let controller, controller.presentingViewController != nil else { return nil }
        return controller
    }

    /// Observes a modal the user can dismiss without the router — a swipe down or a
    /// tap outside — so its state can be cleared.
    ///
    /// Alerts are excluded: UIKit owns an alert's presentation controller and
    /// asserts (`_UIAlertControllerPresentationController setDelegate:`) if its
    /// delegate is replaced. An alert or action sheet clears its state through the
    /// action handler that ran, ``AppRouter/dismissConfirmationDialog()``, or
    /// ``AppRouter/dismissAllPresentations()``.
    private func observeDismissal(of controller: UIViewController) {
        guard !(controller is UIAlertController) else { return }
        controller.presentationController?.delegate = self
        controller.sheetPresentationController?.delegate = self
    }

    /// A confirmation dialog becomes a popover on iPad, which needs a source.
    private func anchorPopover(_ controller: UIAlertController, to presenter: UIViewController) {
        guard let popover = controller.popoverPresentationController else { return }
        popover.sourceView = presenter.view
        popover.sourceRect = CGRect(
            x: presenter.view.bounds.midX,
            y: presenter.view.bounds.maxY,
            width: 0,
            height: 0
        )
    }

    // MARK: - UIAdaptivePresentationControllerDelegate

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        // By the time this runs the controller may no longer be attached, so
        // compare against the stored references rather than re-checking UIKit.
        let dismissed = presentationController.presentedViewController
        if dismissed === alertController {
            alertController = nil
            onAlertDismissed(dismissed)
        } else if dismissed === modal {
            modal = nil
            onModalDismissed(dismissed)
        }
    }
}
