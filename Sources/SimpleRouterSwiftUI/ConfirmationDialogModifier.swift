import SwiftUI

public struct ConfirmationDialogModifier: ViewModifier {
    /// Dialog state presented by the modifier.
    private let dialog: Binding<AppConfirmationDialog?>

    public init(dialog: Binding<AppConfirmationDialog?>) {
        self.dialog = dialog
    }

    public func body(content: Content) -> some View {
        content
            .confirmationDialog(
                dialog.wrappedValue?.title ?? "",
                isPresented: Binding(
                    get: { dialog.wrappedValue != nil },
                    set: { if !$0 { dialog.wrappedValue = nil } }
                ),
                titleVisibility: dialog.wrappedValue?.titleVisibility ?? .automatic,
                presenting: dialog.wrappedValue,
                actions: { d in
                    ForEach(d.actions) { action in
                        Button(action.title, role: action.role) {
                            action.handler()
                        }
                    }
                },
                message: { d in
                    if let message = d.message {

                        Text(message)
                    }
                }
            )
    }
}

public extension View {
    func routerConfirmationDialog(_ dialog: Binding<AppConfirmationDialog?>) -> some View {
        modifier(ConfirmationDialogModifier(dialog: dialog))
    }
}
