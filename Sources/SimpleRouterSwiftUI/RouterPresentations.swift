import SwiftUI

/// Centralized native presentation attachments for router-owned state.
///
/// Push navigation is intentionally absent: pushes belong to ``Stack`` because
/// they are native `NavigationStack(path:)` mutations. This modifier is only
/// for transient native surfaces attached once above the app host.
public struct RouterPresentations<
    SheetContent: View,
    CoverContent: View
>: ViewModifier {
    /// Sheet binding read by `.sheet(item:)`.
    @Binding private var sheet: SheetPresentation?

    /// Full-screen cover binding read by `.fullScreenCover(item:)`.
    @Binding private var cover: CoverPresentation?

    /// Alert binding shared by the root, sheet, and cover presentation contexts.
    @Binding private var alert: AppAlert?

    /// Confirmation dialog binding attached to the root content.
    @Binding private var confirmationDialog: AppConfirmationDialog?

    /// Builder that creates sheet content for the active sheet item.
    private let sheetContent: @MainActor (AnyRoute) -> SheetContent

    /// Builder that creates cover content for the active cover item.
    private let coverContent: @MainActor (AnyRoute) -> CoverContent

    public init(
        sheet: Binding<SheetPresentation?>,
        cover: Binding<CoverPresentation?>,
        alert: Binding<AppAlert?>,
        confirmationDialog: Binding<AppConfirmationDialog?>,
        @ViewBuilder sheetContent: @escaping @MainActor (AnyRoute) -> SheetContent,
        @ViewBuilder coverContent: @escaping @MainActor (AnyRoute) -> CoverContent
    ) {
        self._sheet = sheet
        self._cover = cover
        self._alert = alert
        self._confirmationDialog = confirmationDialog
        self.sheetContent = sheetContent
        self.coverContent = coverContent
    }

    /// Wrapped content with native SwiftUI presentation modifiers attached.
    public func body(content: Content) -> some View {
        content
            .sheet(item: $sheet) { sheet in
                sheetContent(sheet.destination)
                    .presentationDetents(sheet.options.detents)
                    .presentationDragIndicator(sheet.options.dragIndicator)
                    .presentationCornerRadius(sheet.options.cornerRadius)
                    .interactiveDismissDisabled(sheet.options.interactiveDismissDisabled)
                    .alert(item: alertBinding, content: makeAlert)
            }
            .fullScreenCover(item: $cover) { cover in
                coverContent(cover.destination)
                    .alert(item: alertBinding, content: makeAlert)
            }
            .alert(item: rootAlertBinding, content: makeAlert)
            .routerConfirmationDialog($confirmationDialog)
    }

    /// Plain binding to the alert, used by presented sheets/covers.
    private var alertBinding: Binding<AppAlert?> {
        Binding(get: { alert }, set: { alert = $0 })
    }

    /// Root yields while another surface is on top, so only the topmost
    /// presentation context presents the alert.
    private var rootAlertBinding: Binding<AppAlert?> {
        Binding(
            get: { sheet == nil && cover == nil ? alert : nil },
            set: { alert = $0 }
        )
    }

    /// Builds a SwiftUI alert from router alert state.
    private func makeAlert(_ alert: AppAlert) -> Alert {
        Alert(
            title: Text(alert.title),
            message: alert.message.map { Text($0) },
            dismissButton: .default(Text("OK")) { self.alert = nil }
        )
    }
}

public extension View {
    /// Attaches router-owned sheets, full-screen covers, alerts, and
    /// confirmation dialogs, rendering presented routes through their own
    /// `destination` views.
    func routerPresentations(_ router: AppRouter) -> some View {
        @Bindable var router = router

        return routerPresentations(
            sheet: $router.sheet,
            cover: $router.fullScreenCover,
            alert: $router.alert,
            confirmationDialog: $router.confirmationDialog
        ) { route in
            route.destination
        } coverContent: { route in
            route.destination
        }
    }

    func routerPresentations<
        SheetContent: View,
        CoverContent: View
    >(
        sheet: Binding<SheetPresentation?>,
        cover: Binding<CoverPresentation?>,
        alert: Binding<AppAlert?>,
        confirmationDialog: Binding<AppConfirmationDialog?>,
        @ViewBuilder sheetContent: @escaping @MainActor (AnyRoute) -> SheetContent,
        @ViewBuilder coverContent: @escaping @MainActor (AnyRoute) -> CoverContent
    ) -> some View {
        modifier(
            RouterPresentations(
                sheet: sheet,
                cover: cover,
                alert: alert,
                confirmationDialog: confirmationDialog,
                sheetContent: sheetContent,
                coverContent: coverContent
            )
        )
    }
}
