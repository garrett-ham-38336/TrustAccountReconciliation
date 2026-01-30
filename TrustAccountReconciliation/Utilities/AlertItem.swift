import Foundation
import SwiftUI

/// Alert item for presenting alerts in SwiftUI views
struct AlertItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let dismissButton: Alert.Button
    var primaryButton: Alert.Button?

    /// Creates a simple informational alert
    static func info(title: String, message: String) -> AlertItem {
        AlertItem(
            title: title,
            message: message,
            dismissButton: .default(Text("OK"))
        )
    }

    /// Creates a success alert
    static func success(message: String) -> AlertItem {
        AlertItem(
            title: "Success",
            message: message,
            dismissButton: .default(Text("OK"))
        )
    }

    /// Creates an error alert
    static func error(message: String) -> AlertItem {
        AlertItem(
            title: "Error",
            message: message,
            dismissButton: .default(Text("OK"))
        )
    }

    /// Creates an error alert from a Swift Error
    static func error(_ error: Error) -> AlertItem {
        AlertItem(
            title: "Error",
            message: error.localizedDescription,
            dismissButton: .default(Text("OK"))
        )
    }

    /// Creates a warning alert
    static func warning(title: String = "Warning", message: String) -> AlertItem {
        AlertItem(
            title: title,
            message: message,
            dismissButton: .default(Text("OK"))
        )
    }

    /// Creates a confirmation alert with cancel option
    static func confirmation(
        title: String,
        message: String,
        confirmTitle: String = "Confirm",
        confirmAction: @escaping () -> Void
    ) -> AlertItem {
        AlertItem(
            title: title,
            message: message,
            dismissButton: .cancel(),
            primaryButton: .default(Text(confirmTitle), action: confirmAction)
        )
    }

    /// Creates a destructive confirmation alert
    static func destructiveConfirmation(
        title: String,
        message: String,
        destructiveTitle: String = "Delete",
        destructiveAction: @escaping () -> Void
    ) -> AlertItem {
        AlertItem(
            title: title,
            message: message,
            dismissButton: .cancel(),
            primaryButton: .destructive(Text(destructiveTitle), action: destructiveAction)
        )
    }

    /// Builds the Alert view
    func buildAlert() -> Alert {
        if let primaryButton = primaryButton {
            return Alert(
                title: Text(title),
                message: Text(message),
                primaryButton: primaryButton,
                secondaryButton: dismissButton
            )
        } else {
            return Alert(
                title: Text(title),
                message: Text(message),
                dismissButton: dismissButton
            )
        }
    }
}

// MARK: - View Extension for Alert Binding

extension View {
    /// Presents an alert using an AlertItem binding
    func alert(item: Binding<AlertItem?>) -> some View {
        self.alert(item: item) { alertItem in
            alertItem.buildAlert()
        }
    }
}

// MARK: - Toast/Banner Notification

/// A toast notification for brief messages
struct ToastItem: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let type: ToastType
    let duration: TimeInterval

    enum ToastType {
        case success
        case error
        case warning
        case info

        var color: Color {
            switch self {
            case .success: return .green
            case .error: return .red
            case .warning: return .orange
            case .info: return .blue
            }
        }

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            }
        }
    }

    static func success(_ message: String, duration: TimeInterval = 3) -> ToastItem {
        ToastItem(message: message, type: .success, duration: duration)
    }

    static func error(_ message: String, duration: TimeInterval = 5) -> ToastItem {
        ToastItem(message: message, type: .error, duration: duration)
    }

    static func warning(_ message: String, duration: TimeInterval = 4) -> ToastItem {
        ToastItem(message: message, type: .warning, duration: duration)
    }

    static func info(_ message: String, duration: TimeInterval = 3) -> ToastItem {
        ToastItem(message: message, type: .info, duration: duration)
    }

    static func == (lhs: ToastItem, rhs: ToastItem) -> Bool {
        lhs.id == rhs.id
    }
}

/// Toast view component
struct ToastView: View {
    let toast: ToastItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.type.icon)
                .foregroundColor(.white)
                .font(.title3)

            Text(toast.message)
                .foregroundColor(.white)
                .font(.subheadline)

            Spacer()
        }
        .padding()
        .background(toast.type.color)
        .cornerRadius(10)
        .shadow(radius: 5)
        .padding(.horizontal)
    }
}

// MARK: - Toast Modifier

struct ToastModifier: ViewModifier {
    @Binding var toast: ToastItem?

    func body(content: Content) -> some View {
        ZStack {
            content

            if let toast = toast {
                VStack {
                    Spacer()
                    ToastView(toast: toast)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + toast.duration) {
                                withAnimation {
                                    self.toast = nil
                                }
                            }
                        }
                }
                .animation(.easeInOut, value: toast)
            }
        }
    }
}

extension View {
    /// Shows a toast notification
    func toast(_ toast: Binding<ToastItem?>) -> some View {
        self.modifier(ToastModifier(toast: toast))
    }
}
