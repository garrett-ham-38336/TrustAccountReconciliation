import SwiftUI
import CoreData

struct ReconciliationHistoryView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ReconciliationSnapshot.reconciliationDate, ascending: false)],
        animation: .default
    )
    private var reconciliations: FetchedResults<ReconciliationSnapshot>

    @State private var selectedReconciliation: ReconciliationSnapshot?
    @State private var showingNewReconciliation = false

    var body: some View {
        HSplitView {
            // List
            listView
                .frame(minWidth: 300, maxWidth: 400)

            // Detail
            if let reconciliation = selectedReconciliation {
                ReconciliationDetailView(reconciliation: reconciliation)
            } else {
                emptyDetailView
            }
        }
        .navigationTitle("Reconciliation History")
        .toolbar {
            ToolbarItem {
                Button(action: { showingNewReconciliation = true }) {
                    Label("New Reconciliation", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewReconciliation) {
            ReconciliationWizardView()
                .environment(\.managedObjectContext, viewContext)
        }
    }

    private var listView: some View {
        VStack(spacing: 0) {
            // Summary header
            if let latest = reconciliations.first {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Latest Status")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    HStack {
                        Image(systemName: latest.isBalanced ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(latest.isBalanced ? .green : .orange)
                        Text(latest.isBalanced ? "Balanced" : "Variance: \((latest.variance as Decimal? ?? 0).asCurrency)")
                            .font(.subheadline)
                    }

                    Text(latest.reconciliationDate?.formatted(date: .abbreviated, time: .shortened) ?? "")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(latest.isBalanced ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))

                Divider()
            }

            if reconciliations.isEmpty {
                emptyListView
            } else {
                List(reconciliations, selection: $selectedReconciliation) { reconciliation in
                    ReconciliationListRow(reconciliation: reconciliation)
                        .tag(reconciliation)
                }
                .listStyle(.sidebar)
            }
        }
    }

    private var emptyListView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Reconciliations")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Run your first reconciliation to start tracking your trust account balance.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Start Reconciliation") {
                showingNewReconciliation = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var emptyDetailView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("Select a Reconciliation")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("Choose a reconciliation from the list to view its details.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ReconciliationListRow: View {
    @ObservedObject var reconciliation: ReconciliationSnapshot

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Image(systemName: reconciliation.isBalanced ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(reconciliation.isBalanced ? .green : .orange)

            VStack(alignment: .leading, spacing: 4) {
                Text(reconciliation.reconciliationDate?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(reconciliation.isBalanced ? "Balanced" : "Variance")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !reconciliation.isBalanced {
                Text((reconciliation.variance as Decimal? ?? 0).asCurrency)
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ReconciliationDetailView: View {
    @ObservedObject var reconciliation: ReconciliationSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                header

                Divider()

                // Summary
                summarySection

                Divider()

                // Breakdown
                breakdownSection

                // Drill-down data if available
                if hasDrillDownData {
                    Divider()
                    drillDownSection
                }

                // Notes
                if let notes = reconciliation.notes, !notes.isEmpty {
                    Divider()
                    notesSection(notes)
                }
            }
            .padding()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Reconciliation")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: reconciliation.isBalanced ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    Text(reconciliation.isBalanced ? "Balanced" : "Variance Detected")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(reconciliation.isBalanced ? .green : .orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background((reconciliation.isBalanced ? Color.green : Color.orange).opacity(0.15))
                .cornerRadius(8)
            }

            Text(reconciliation.reconciliationDate?.formatted(date: .complete, time: .shortened) ?? "Unknown Date")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Summary")
                .font(.headline)

            HStack(spacing: 24) {
                VStack(alignment: .leading) {
                    Text("Expected Balance")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text((reconciliation.expectedBalance as Decimal? ?? 0).asCurrency)
                        .font(.title3)
                        .fontWeight(.semibold)
                }

                VStack(alignment: .leading) {
                    Text("Actual Balance")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text((reconciliation.actualBalance as Decimal? ?? 0).asCurrency)
                        .font(.title3)
                        .fontWeight(.semibold)
                }

                VStack(alignment: .leading) {
                    Text("Variance")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text((reconciliation.variance as Decimal? ?? 0).asCurrency)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(reconciliation.isBalanced ? .green : .red)
                }
            }
        }
    }

    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Calculation Breakdown")
                .font(.headline)

            VStack(spacing: 12) {
                BreakdownRow(
                    label: "Future Reservation Deposits",
                    value: reconciliation.futureDeposits as Decimal? ?? 0,
                    count: Int(reconciliation.futureReservationCount)
                )

                BreakdownRow(
                    label: "Stripe Holdback",
                    value: reconciliation.stripeHoldback as Decimal? ?? 0,
                    isSubtraction: true
                )

                BreakdownRow(
                    label: "Unpaid Owner Payouts",
                    value: reconciliation.unpaidOwnerPayouts as Decimal? ?? 0,
                    count: Int(reconciliation.unpaidPayoutCount)
                )

                BreakdownRow(
                    label: "Unpaid Taxes",
                    value: reconciliation.unpaidTaxes as Decimal? ?? 0,
                    count: Int(reconciliation.unpaidTaxReservationCount)
                )

                Divider()

                HStack {
                    Text("Expected Trust Balance")
                        .fontWeight(.semibold)
                    Spacer()
                    Text((reconciliation.expectedBalance as Decimal? ?? 0).asCurrency)
                        .fontWeight(.semibold)
                }
                .font(.subheadline)

                Divider()

                HStack {
                    Text("Bank Balance Entered")
                    Spacer()
                    Text((reconciliation.bankBalance as Decimal? ?? 0).asCurrency)
                }
                .font(.subheadline)

                HStack {
                    Text("+ Stripe Holdback")
                    Spacer()
                    Text((reconciliation.stripeHoldback as Decimal? ?? 0).asCurrency)
                }
                .font(.subheadline)
                .foregroundColor(.secondary)

                HStack {
                    Text("= Actual Balance")
                        .fontWeight(.semibold)
                    Spacer()
                    Text((reconciliation.actualBalance as Decimal? ?? 0).asCurrency)
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    private var hasDrillDownData: Bool {
        reconciliation.futureReservationsData != nil ||
        reconciliation.unpaidPayoutsData != nil ||
        reconciliation.unpaidTaxesData != nil
    }

    private var drillDownSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Detail Data")
                .font(.headline)

            Text("Drill-down data available from this reconciliation snapshot.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notes")
                .font(.headline)

            Text(notes)
                .font(.subheadline)
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
        }
    }
}

struct BreakdownRow: View {
    let label: String
    let value: Decimal
    var count: Int? = nil
    var isSubtraction: Bool = false

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                if isSubtraction {
                    Text("-").foregroundColor(.red)
                } else {
                    Text("+").foregroundColor(.green)
                }
                Text(label)
                if let count = count {
                    Text("(\(count))")
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Text(value.asCurrency)
        }
        .font(.subheadline)
    }
}

#Preview {
    ReconciliationHistoryView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
