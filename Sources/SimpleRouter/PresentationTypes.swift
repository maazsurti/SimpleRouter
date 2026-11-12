import UIKit

/// How ``Navigator/routeTo(_:presentation:)`` shows a route.
public enum Presentation {
    /// Appears by pushing onto the current navigation stack. Use
    /// ``NavStack/push(_:)`` or ``Navigator/routeTo(_:presentation:)`` for this
    /// case; ``AppRouter/present(_:as:)`` asserts on it.
    case push

    /// Presents the route as a sheet, configured by ``SheetOptions``.
    case sheet(SheetOptions = SheetOptions())

    /// Presents the route full screen.
    case cover
}

/// A height a sheet offers to the user.
///
/// Replaces SwiftUI's `PresentationDetent`. UIKit sheets have the system medium
/// and large detents, and SimpleRouter maps them one to one.
public enum SheetDetent: Hashable, Sendable {

    /// Roughly half of the screen.
    case medium

    /// The full screen.
    case large
}

/// Visibility of a sheet's drag indicator.
public enum SheetDragIndicator: Sendable {

    /// Shows the indicator when the sheet is resizable, matching what SwiftUI
    /// does for `.automatic`.
    case automatic

    /// Always shows the grabber.
    case visible

    /// Never shows the grabber.
    case hidden
}

/// Visibility of a confirmation dialog's title.
///
/// UIKit action sheets always lay out a title, so `.hidden` presents the dialog
/// without one; `.automatic` and `.visible` show it.
public enum DialogTitleVisibility: Sendable {

    /// Shows the title.
    case automatic

    /// Shows the title.
    case visible

    /// Presents the dialog without a title.
    case hidden
}

/// Configuration of a presented sheet.
public struct SheetOptions {
    /// Sheet heights offered to the user.
    public var detents: Set<SheetDetent>

    /// Visibility of the sheet drag indicator.
    public var dragIndicator: SheetDragIndicator

    /// Preferred corner radius for the sheet, or `nil` for the system default.
    public var cornerRadius: CGFloat?

    /// Whether swipe-to-dismiss is disabled while the sheet is visible.
    public var interactiveDismissDisabled: Bool

    public init(
        detents: Set<SheetDetent> = [.large],
        dragIndicator: SheetDragIndicator = .automatic,
        cornerRadius: CGFloat? = nil,
        interactiveDismissDisabled: Bool = false
    ) {
        self.detents = detents
        self.dragIndicator = dragIndicator
        self.cornerRadius = cornerRadius
        self.interactiveDismissDisabled = interactiveDismissDisabled
    }

    /// Common bottom-sheet configuration with medium and large detents.
    public static var bottom: SheetOptions {
        SheetOptions(
            detents: [.medium, .large],
            dragIndicator: .visible,
            cornerRadius: 24
        )
    }
}

// MARK: - UIKit mapping

extension SheetOptions {
    /// Detents in ascending order, because UIKit uses the first one as the size
    /// the sheet opens at.
    var uiDetents: [UISheetPresentationController.Detent] {
        [SheetDetent.medium, .large]
            .filter { detents.contains($0) }
            .map { detent in
                switch detent {
                case .medium: .medium()
                case .large: .large()
                }
            }
    }

    /// UIKit has no "automatic" grabber, so `.automatic` shows the indicator for
    /// a resizable sheet and hides it otherwise — the SwiftUI behavior.
    var prefersGrabberVisible: Bool {
        switch dragIndicator {
        case .visible: true
        case .hidden: false
        case .automatic: detents.count > 1
        }
    }
}

/// The active sheet: the route shown and the configuration it was presented with.
public struct SheetPresentation: Identifiable {
    /// Stable identity of this presentation.
    public let id = UUID()

    /// Route value shown inside the sheet.
    public let destination: AnyRoute

    /// Sheet configuration applied to the native sheet.
    public let options: SheetOptions

    public init(
        destination: AnyRoute,
        options: SheetOptions
    ) {
        self.destination = destination
        self.options = options
    }
}

/// The active full-screen cover and the route it shows.
public struct CoverPresentation: Identifiable {
    /// Stable identity of this presentation.
    public let id = UUID()

    /// Route value shown inside the cover.
    public let destination: AnyRoute

    public init(destination: AnyRoute) {
        self.destination = destination
    }
}

/// The active alert's content.
public struct AppAlert: Identifiable, Hashable {
    /// Stable identity of this alert.
    public let id = UUID()

    /// Main alert text.
    public let title: String

    /// Optional secondary alert text.
    public let message: String?

    public init(title: String, message: String?) {
        self.title = title
        self.message = message
    }
}

/// The active confirmation dialog's content.
public struct AppConfirmationDialog: Identifiable {
    /// Stable identity of this dialog.
    public let id = UUID()

    /// Main dialog text.
    public let title: String

    /// Optional secondary dialog text.
    public let message: String?

    /// Whether the dialog shows its title.
    public let titleVisibility: DialogTitleVisibility

    /// Buttons shown in the dialog.
    public let actions: [AppDialogAction]

    public init(
        title: String,
        message: String?,
        titleVisibility: DialogTitleVisibility,
        actions: [AppDialogAction]
    ) {
        self.title = title
        self.message = message
        self.titleVisibility = titleVisibility
        self.actions = actions
    }
}

/// The part a confirmation dialog button plays.
public enum DialogActionRole: Sendable {

    /// An ordinary button.
    case standard

    /// A button that destroys data.
    case destructive

    /// The button that cancels the dialog.
    case cancel
}

/// One button of a confirmation dialog.
public struct AppDialogAction: Identifiable {
    /// Stable identity of this action.
    public let id = UUID()

    /// Button title shown in the dialog.
    public let title: String

    /// Optional role, such as ``DialogActionRole/destructive``.
    public let role: DialogActionRole?

    /// Work performed when the action button is tapped.
    public let handler: @MainActor () -> Void

    public init(
        title: String,
        role: DialogActionRole? = nil,
        handler: @escaping @MainActor () -> Void
    ) {
        self.title = title
        self.role = role
        self.handler = handler
    }
}

extension AppDialogAction {
    /// Button style in a `UIAlertController`.
    var uiStyle: UIAlertAction.Style {
        switch role {
        case .destructive: .destructive
        case .cancel: .cancel
        case .standard, nil: .default
        }
    }
}
