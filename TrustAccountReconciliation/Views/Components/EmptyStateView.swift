import SwiftUI

/// Reusable empty state view for lists and collections
struct EmptyStateView: View {
    let icon: String
    let title: String
    let description: String
    var actionTitle: String?
    var action: (() -> Void)?
    var secondaryActionTitle: String?
    var secondaryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            if let actionTitle = actionTitle, let action = action {
                VStack(spacing: 12) {
                    Button(action: action) {
                        Text(actionTitle)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    if let secondaryTitle = secondaryActionTitle, let secondaryAction = secondaryAction {
                        Button(action: secondaryAction) {
                            Text(secondaryTitle)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.top, 8)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Preset Empty States

extension EmptyStateView {
    /// Empty state for owners list
    static func owners(addAction: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            icon: "person.2.fill",
            title: "No Property Owners",
            description: "Add property owners to track their reservations, payouts, and management fees.",
            actionTitle: "Add Owner",
            action: addAction
        )
    }

    /// Empty state for properties list
    static func properties(addAction: @escaping () -> Void, syncAction: (() -> Void)? = nil) -> EmptyStateView {
        EmptyStateView(
            icon: "house.fill",
            title: "No Properties",
            description: "Add properties manually or sync from Guesty to get started.",
            actionTitle: "Add Property",
            action: addAction,
            secondaryActionTitle: syncAction != nil ? "Sync from Guesty" : nil,
            secondaryAction: syncAction
        )
    }

    /// Empty state for reservations list
    static func reservations(syncAction: @escaping () -> Void, addAction: (() -> Void)? = nil) -> EmptyStateView {
        EmptyStateView(
            icon: "calendar.badge.clock",
            title: "No Reservations",
            description: "Sync reservations from Guesty or add them manually to start tracking.",
            actionTitle: "Sync from Guesty",
            action: syncAction,
            secondaryActionTitle: addAction != nil ? "Add Manually" : nil,
            secondaryAction: addAction
        )
    }

    /// Empty state for reconciliation history
    static func reconciliationHistory(startAction: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            icon: "checkmark.circle.badge.questionmark",
            title: "No Reconciliations Yet",
            description: "Perform your first trust account reconciliation to verify your account balance.",
            actionTitle: "Start Reconciliation",
            action: startAction
        )
    }

    /// Empty state for sync history
    static func syncHistory() -> EmptyStateView {
        EmptyStateView(
            icon: "clock.arrow.circlepath",
            title: "No Sync History",
            description: "Sync with Guesty to see your sync history here.",
            actionTitle: nil,
            action: nil
        )
    }

    /// Empty state for audit log
    static func auditLog() -> EmptyStateView {
        EmptyStateView(
            icon: "doc.text.magnifyingglass",
            title: "No Audit Entries",
            description: "Actions you take in the app will be logged here for compliance tracking.",
            actionTitle: nil,
            action: nil
        )
    }

    /// Empty state for search results
    static func searchResults(query: String) -> EmptyStateView {
        EmptyStateView(
            icon: "magnifyingglass",
            title: "No Results",
            description: "No items match \"\(query)\". Try a different search term.",
            actionTitle: nil,
            action: nil
        )
    }

    /// Empty state for filtered results
    static func filteredResults(clearAction: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            icon: "line.3.horizontal.decrease.circle",
            title: "No Matching Items",
            description: "No items match your current filters.",
            actionTitle: "Clear Filters",
            action: clearAction
        )
    }
}

#Preview("Owners") {
    EmptyStateView.owners { }
}

#Preview("Properties") {
    EmptyStateView.properties(addAction: { }, syncAction: { })
}

#Preview("Reservations") {
    EmptyStateView.reservations(syncAction: { })
}

#Preview("Reconciliation History") {
    EmptyStateView.reconciliationHistory { }
}
