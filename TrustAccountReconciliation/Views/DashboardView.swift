import SwiftUI
import CoreData

struct DashboardView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var viewModel = DashboardViewModel()

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ReconciliationSnapshot.reconciliationDate, ascending: false)],
        animation: .default
    )
    private var reconciliations: FetchedResults<ReconciliationSnapshot>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Owner.name, ascending: true)],
        predicate: NSPredicate(format: "isActive == YES")
    )
    private var owners: FetchedResults<Owner>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Reservation.checkInDate, ascending: true)],
        predicate: NSPredicate(format: "checkInDate > %@ AND isCancelled == NO", Date() as NSDate)
    )
    private var futureReservations: FetchedResults<Reservation>

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header with last reconciliation status
                headerSection

                // Quick Summary Cards
                summaryCardsSection

                // Alerts Section
                if !alerts.isEmpty {
                    alertsSection
                }

                // Quick Actions
                quickActionsSection

                // Upcoming Reservations Preview
                upcomingReservationsSection
            }
            .padding()
        }
        .navigationTitle("Dashboard")
        .onAppear {
            viewModel.loadData(context: viewContext)
        }
        .toolbar {
            ToolbarItem {
                Button(action: { viewModel.showingReconciliation = true }) {
                    Label("Reconcile", systemImage: "checkmark.circle")
                }
            }
        }
        .sheet(isPresented: $viewModel.showingReconciliation) {
            ReconciliationWizardView()
                .environment(\.managedObjectContext, viewContext)
        }
        .sheet(isPresented: $viewModel.showingSync) {
            GuestySyncView()
                .environment(\.managedObjectContext, viewContext)
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Trust Account Status")
                        .font(.title2)
                        .fontWeight(.bold)

                    if let lastRecon = reconciliations.first {
                        Text("Last reconciled: \(lastRecon.reconciliationDate?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown")")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text("No reconciliations yet")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Status indicator
                if let lastRecon = reconciliations.first {
                    statusBadge(for: lastRecon)
                }
            }

            // Variance display if exists
            if let lastRecon = reconciliations.first {
                HStack(spacing: 24) {
                    VStack(alignment: .leading) {
                        Text("Expected Balance")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text((lastRecon.expectedBalance as Decimal? ?? 0).asCurrency)
                            .font(.title3)
                            .fontWeight(.semibold)
                    }

                    VStack(alignment: .leading) {
                        Text("Actual Balance")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text((lastRecon.actualBalance as Decimal? ?? 0).asCurrency)
                            .font(.title3)
                            .fontWeight(.semibold)
                    }

                    VStack(alignment: .leading) {
                        Text("Variance")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text((lastRecon.variance as Decimal? ?? 0).asCurrency)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(lastRecon.isBalanced ? .green : .red)
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func statusBadge(for reconciliation: ReconciliationSnapshot) -> some View {
        HStack(spacing: 6) {
            Image(systemName: reconciliation.isBalanced ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            Text(reconciliation.isBalanced ? "Balanced" : "Variance")
        }
        .font(.subheadline)
        .fontWeight(.medium)
        .foregroundColor(reconciliation.isBalanced ? .green : .orange)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background((reconciliation.isBalanced ? Color.green : Color.orange).opacity(0.15))
        .cornerRadius(8)
    }

    // MARK: - Summary Cards

    private var summaryCardsSection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            SummaryCard(
                title: "Future Deposits",
                value: viewModel.totalFutureDeposits.asCurrency,
                subtitle: "\(futureReservations.count) reservations",
                icon: "calendar.badge.clock",
                color: .blue
            )

            SummaryCard(
                title: "Stripe Holdback",
                value: viewModel.stripeHoldback.asCurrency,
                subtitle: viewModel.stripeLastSync != nil ? "Pending + Reserve" : "Not synced",
                icon: "creditcard",
                color: .indigo
            )

            SummaryCard(
                title: "Unpaid Payouts",
                value: viewModel.totalUnpaidPayouts.asCurrency,
                subtitle: "\(viewModel.unpaidPayoutCount) stays",
                icon: "dollarsign.arrow.circlepath",
                color: .orange
            )

            SummaryCard(
                title: "Unpaid Taxes",
                value: viewModel.totalUnpaidTaxes.asCurrency,
                subtitle: "\(viewModel.unpaidTaxCount) stays",
                icon: "doc.text",
                color: .purple
            )
        }
    }

    private var daysSinceLastReconciliation: Int {
        guard let lastRecon = reconciliations.first,
              let date = lastRecon.reconciliationDate else {
            return 999
        }
        return Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
    }

    // MARK: - Alerts Section

    private var alerts: [DashboardAlert] {
        var alertList: [DashboardAlert] = []

        // Check for overdue reconciliation
        if daysSinceLastReconciliation > 7 {
            alertList.append(DashboardAlert(
                type: .warning,
                title: "Reconciliation Overdue",
                message: "Last reconciliation was \(daysSinceLastReconciliation) days ago",
                action: "Reconcile Now"
            ))
        }

        // Check for variance
        if let lastRecon = reconciliations.first, !lastRecon.isBalanced {
            let variance = lastRecon.variance as Decimal? ?? 0
            alertList.append(DashboardAlert(
                type: .error,
                title: "Trust Account Variance",
                message: "Variance of \(variance.asCurrency) detected",
                action: "Review"
            ))
        }

        // Check for owners needing payout
        let ownersNeedingPayout = owners.filter { owner in
            if let lastPayout = owner.lastPayoutDate {
                let daysSince = Calendar.current.dateComponents([.day], from: lastPayout, to: Date()).day ?? 0
                return daysSince > 30
            }
            return true
        }
        if !ownersNeedingPayout.isEmpty {
            alertList.append(DashboardAlert(
                type: .info,
                title: "Payouts Due",
                message: "\(ownersNeedingPayout.count) owner(s) may need payouts",
                action: "View"
            ))
        }

        return alertList
    }

    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Alerts")
                .font(.headline)

            ForEach(alerts.indices, id: \.self) { index in
                AlertRow(alert: alerts[index])
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)

            HStack(spacing: 16) {
                QuickActionButton(
                    title: "Reconcile",
                    icon: "checkmark.circle",
                    color: .blue
                ) {
                    viewModel.showingReconciliation = true
                }

                QuickActionButton(
                    title: "Sync Guesty",
                    icon: "arrow.triangle.2.circlepath",
                    color: .green
                ) {
                    viewModel.showingSync = true
                }

                QuickActionButton(
                    title: viewModel.isSyncingStripe ? "Syncing..." : "Sync Stripe",
                    icon: viewModel.isSyncingStripe ? "arrow.triangle.2.circlepath" : "creditcard",
                    color: .indigo
                ) {
                    Task {
                        await viewModel.syncStripe(context: viewContext)
                    }
                }

                QuickActionButton(
                    title: "Owner Payouts",
                    icon: "dollarsign.circle",
                    color: .orange
                ) {
                    // Navigate to payouts
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - Upcoming Reservations

    private var upcomingReservationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Upcoming Reservations")
                    .font(.headline)

                Spacer()

                Text("\(futureReservations.count) total")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if futureReservations.isEmpty {
                Text("No upcoming reservations")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(Array(futureReservations.prefix(5))) { reservation in
                    ReservationRow(reservation: reservation)
                    if reservation != futureReservations.prefix(5).last {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - View Model

class DashboardViewModel: ObservableObject {
    @Published var totalFutureDeposits: Decimal = 0
    @Published var totalUnpaidPayouts: Decimal = 0
    @Published var totalUnpaidTaxes: Decimal = 0
    @Published var unpaidPayoutCount: Int = 0
    @Published var unpaidTaxCount: Int = 0
    @Published var showingReconciliation = false
    @Published var showingSync = false

    // Stripe data
    @Published var stripeAvailable: Decimal = 0
    @Published var stripePending: Decimal = 0
    @Published var stripeReserve: Decimal = 0
    @Published var stripeLastSync: Date?
    @Published var showingStripeSync = false
    @Published var isSyncingStripe = false

    var stripeHoldback: Decimal {
        stripePending + stripeReserve
    }

    var isStripeConfigured: Bool {
        StripeAPIService.shared.hasCredentials
    }

    func loadData(context: NSManagedObjectContext) {
        // Calculate future deposits
        let futureRequest = Reservation.futureReservationsWithDeposits()
        if let reservations = try? context.fetch(futureRequest) {
            totalFutureDeposits = reservations.reduce(Decimal(0)) {
                $0 + ($1.depositReceived as Decimal? ?? 0)
            }
        }

        // Calculate unpaid payouts (simplified - across all owners)
        let payoutRequest = Reservation.completedUnpaidPayouts(since: nil)
        if let reservations = try? context.fetch(payoutRequest) {
            totalUnpaidPayouts = reservations.reduce(Decimal(0)) {
                $0 + ($1.ownerPayout as Decimal? ?? 0)
            }
            unpaidPayoutCount = reservations.count
        }

        // Calculate unpaid taxes
        let taxRequest = Reservation.completedUnremittedTaxes(since: nil)
        if let reservations = try? context.fetch(taxRequest) {
            totalUnpaidTaxes = reservations.reduce(Decimal(0)) {
                $0 + ($1.taxAmount as Decimal? ?? 0)
            }
            unpaidTaxCount = reservations.count
        }

        // Load Stripe data from most recent snapshot
        loadStripeData(context: context)
    }

    func loadStripeData(context: NSManagedObjectContext) {
        if let snapshot = StripeSnapshot.mostRecent(in: context) {
            stripeAvailable = snapshot.availableBalance as Decimal? ?? 0
            stripePending = snapshot.pendingBalance as Decimal? ?? 0
            stripeReserve = snapshot.reserveBalance as Decimal? ?? 0
            stripeLastSync = snapshot.snapshotDate
        }
    }

    @MainActor
    func syncStripe(context: NSManagedObjectContext) async {
        guard isStripeConfigured else { return }

        isSyncingStripe = true
        do {
            let snapshot = try await StripeAPIService.shared.syncBalance(context: context)
            stripeAvailable = snapshot.availableBalance as Decimal? ?? 0
            stripePending = snapshot.pendingBalance as Decimal? ?? 0
            stripeReserve = snapshot.reserveBalance as Decimal? ?? 0
            stripeLastSync = snapshot.snapshotDate
        } catch {
            print("Stripe sync error: \(error)")
        }
        isSyncingStripe = false
    }
}

// MARK: - Supporting Views

struct SummaryCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }

            Text(value)
                .font(.title2)
                .fontWeight(.bold)

            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct DashboardAlert: Identifiable {
    let id = UUID()
    let type: AlertType
    let title: String
    let message: String
    let action: String

    enum AlertType {
        case info, warning, error

        var color: Color {
            switch self {
            case .info: return .blue
            case .warning: return .orange
            case .error: return .red
            }
        }

        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.circle.fill"
            }
        }
    }
}

struct AlertRow: View {
    let alert: DashboardAlert

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: alert.type.icon)
                .foregroundColor(alert.type.color)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(alert.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(alert.action) {
                // Handle action
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .background(alert.type.color.opacity(0.1))
        .cornerRadius(8)
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(color.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

struct ReservationRow: View {
    @ObservedObject var reservation: Reservation

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(reservation.guestName ?? "Unknown Guest")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(reservation.property?.displayName ?? "Unknown Property")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(reservation.checkInDate?.formatted(date: .abbreviated, time: .omitted) ?? "")
                    .font(.subheadline)

                Text((reservation.depositReceived as Decimal? ?? 0).asCurrency)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    DashboardView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
