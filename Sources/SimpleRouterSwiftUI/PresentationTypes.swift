import SwiftUI

public enum Presentation {
    /// Identifies push navigation. Use ``NavStack/push(_:)`` for this case.
    case push

    /// Presents the route with SwiftUI's `sheet(item:)` modifier.
    case sheet(SheetOptions = SheetOptions())

    /// Presents the route with SwiftUI's `fullScreenCover(item:)` modifier.
    case cover
}

public struct SheetOptions {
    /// Sheet heights offered to the user.
    public var detents: Set<PresentationDetent>

    /// Visibility of the sheet drag indicator.
    public var dragIndicator: Visibility

    /// Preferred corner radius for the sheet, or `nil` for the system default.
    public var cornerRadius: CGFloat?

    /// Whether swipe-to-dismiss is disabled while the sheet is visible.
    public var interactiveDismissDisabled: Bool

    public init(
        detents: Set<PresentationDetent> = [.large],
        dragIndicator: Visibility = .automatic,
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

public struct SheetPresentation: Identifiable {
    /// Stable identity for SwiftUI's `sheet(item:)` presentation.
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

public struct CoverPresentation: Identifiable {
    /// Stable identity for SwiftUI's `fullScreenCover(item:)` presentation.
    public let id = UUID()

    /// Route value shown inside the full-screen cover.
    public let destination: AnyRoute

    public init(destination: AnyRoute) {
        self.destination = destination
    }
}

public struct AppAlert: Identifiable, Hashable {
    /// Stable identity for SwiftUI's `alert(item:)` presentation.
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

public struct AppConfirmationDialog: Identifiable {
    /// Stable identity for SwiftUI's confirmation dialog presentation.
    public let id = UUID()

    /// Main dialog text.
    public let title: String

    /// Optional secondary dialog text.
    public let message: String?

    /// Controls whether SwiftUI displays the dialog title.
    public let titleVisibility: Visibility

    /// Buttons shown in the dialog.
    public let actions: [AppDialogAction]

    public init(
        title: String,
        message: String?,
        titleVisibility: Visibility,
        actions: [AppDialogAction]
    ) {
        self.title = title
        self.message = message
        self.titleVisibility = titleVisibility
        self.actions = actions
    }
}

public struct AppDialogAction: Identifiable {
    /// Stable identity for rendering this action in a `ForEach`.
    public let id = UUID()

    /// Button title shown in the dialog.
    public let title: String

    /// Optional SwiftUI role, such as `.destructive` or `.cancel`.
    public let role: ButtonRole?

    /// Work performed when the action button is tapped.
    public let handler: @MainActor () -> Void

    public init(
        title: String,
        role: ButtonRole? = nil,
        handler: @escaping @MainActor () -> Void
    ) {
        self.title = title
        self.role = role
        self.handler = handler
    }
}
