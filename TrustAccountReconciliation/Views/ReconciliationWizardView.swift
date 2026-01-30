import SwiftUI
import CoreData

/// Step-by-step reconciliation wizard
struct ReconciliationWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    @State private var currentStep = 0
    @State private var bankBalance: Decimal = 0
    @State private var stripeHoldback: Decimal = 0
    @State private var calculation: TrustCalculationService.TrustCalculation?
    @State private var notes: String = ""
    @State private var isSyncing = false
    @State private var syncProgress: String = ""
    @State private var error: Error?
    @State private var showingError = false

    // Stripe-specific state
    @State private var isStripeConfigured = false
    @State private var stripeSyncDate: Date?
    @State private var isSyncingStripe = false
    @State private var stripeAvailable: Decimal = 0
    @State private var stripePending: Decimal = 0
    @State private var stripeReserve: Decimal = 0

    private let steps = ["Sync Data", "Bank Balance", "Stripe Holdback", "Review", "Confirm"]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Progress indicator
            progressIndicator
                .padding()

            Divider()

            // Content
            TabView(selection: $currentStep) {
                syncStep.tag(0)
                bankBalanceStep.tag(1)
                stripeHoldbackStep.tag(2)
                reviewStep.tag(3)
                confirmStep.tag(4)
            }
            .tabViewStyle(.automatic)

            Divider()

            // Navigation buttons
            navigationButtons
        }
        .frame(width: 800, height: 700)
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(error?.localizedDescription ?? "An unknown error occurred")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Trust Account Reconciliation")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Verify that your trust account balance matches expected amounts")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    // MARK: - Progress Indicator

    private var progressIndicator: some View {
        HStack {
            ForEach(0..<steps.count, id: \.self) { index in
                HStack {
                    Circle()
                        .fill(index <= currentStep ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Group {
                                if index < currentStep {
                                    Image(systemName: "checkmark")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                } else {
                                    Text("\(index + 1)")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(index <= currentStep ? .white : .secondary)
                                }
                            }
                        )

                    Text(steps[index])
                        .font(.caption)
                        .foregroundColor(index <= currentStep ? .primary : .secondary)

                    if index < steps.count - 1 {
                        Rectangle()
                            .fill(index < currentStep ? Color.blue : Color.gray.opacity(0.3))
                            .frame(height: 2)
                    }
                }
            }
        }
    }

    // MARK: - Step 1: Sync Data

    private var syncStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.blue)

            Text("Sync Reservation Data")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Pull the latest reservation data from Guesty to ensure accurate calculations.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            if isSyncing {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text(syncProgress)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                VStack(spacing: 12) {
                    Button("Sync with Guesty") {
                        syncWithGuesty()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Skip (Use Existing Data)") {
                        withAnimation { currentStep = 1 }
                    }
                    .buttonStyle(.bordered)
                }
            }

            Spacer()
        }
        .padding()
    }

    private func syncWithGuesty() {
        isSyncing = true
        syncProgress = "Connecting to Guesty..."

        Task {
            do {
                _ = try await GuestyAPIService.shared.syncReservations(
                    context: viewContext
                ) { progress in
                    Task { @MainActor in
                        syncProgress = progress
                    }
                }

                await MainActor.run {
                    isSyncing = false
                    withAnimation { currentStep = 1 }
                }
            } catch {
                await MainActor.run {
                    isSyncing = false
                    self.error = error
                    showingError = true
                }
            }
        }
    }

    // MARK: - Step 2: Bank Balance

    private var bankBalanceStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "building.columns.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)

            Text("Enter Bank Balance")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Enter the current balance from your trust account bank statement or online banking.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            VStack(spacing: 8) {
                Text("Current Trust Account Balance")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextField("Bank Balance", value: $bankBalance, format: .currency(code: "USD"))
                    .textFieldStyle(.roundedBorder)
                    .font(.title)
                    .multilineTextAlignment(.center)
                    .frame(width: 250)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)

            Spacer()
        }
        .padding()
    }

    // MARK: - Step 3: Stripe Holdback

    private var stripeHoldbackStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "creditcard.fill")
                .font(.system(size: 64))
                .foregroundColor(.purple)

            Text("Stripe Holdback")
                .font(.title2)
                .fontWeight(.semibold)

            if isStripeConfigured {
                // Stripe is configured - show sync option
                Text("Sync your Stripe balance or enter manually.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)

                // Sync button and status
                VStack(spacing: 16) {
                    Button(action: syncStripeBalance) {
                        if isSyncingStripe {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Syncing...")
                            }
                        } else {
                            Label("Sync from Stripe", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .disabled(isSyncingStripe)

                    if let syncDate = stripeSyncDate {
                        Text("Last synced: \(syncDate.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Balance breakdown (if synced)
                if stripeSyncDate != nil {
                    VStack(spacing: 12) {
                        HStack(spacing: 24) {
                            VStack(spacing: 4) {
                                Text("Available")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(stripeAvailable.asCurrency)
                                    .font(.headline)
                                    .foregroundColor(.green)
                            }

                            VStack(spacing: 4) {
                                Text("Pending")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(stripePending.asCurrency)
                                    .font(.headline)
                                    .foregroundColor(.orange)
                            }

                            if stripeReserve > 0 {
                                VStack(spacing: 4) {
                                    Text("Reserve")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(stripeReserve.asCurrency)
                                        .font(.headline)
                                        .foregroundColor(.purple)
                                }
                            }
                        }

                        Divider()

                        HStack {
                            Text("Holdback (Pending + Reserve)")
                                .font(.subheadline)
                            Spacer()
                            Text(stripeHoldback.asCurrency)
                                .font(.title3)
                                .fontWeight(.bold)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                }
            } else {
                // Stripe not configured - manual entry only
                Text("Enter the total amount Stripe is currently holding (Pending + Reserve from your Stripe dashboard).")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    Text("Configure Stripe API in Settings to auto-sync this value.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }

            // Manual entry field (always available)
            VStack(spacing: 8) {
                Text(isStripeConfigured ? "Or enter manually:" : "Stripe Holdback Amount")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextField("Stripe Holdback", value: $stripeHoldback, format: .currency(code: "USD"))
                    .textFieldStyle(.roundedBorder)
                    .font(.title)
                    .multilineTextAlignment(.center)
                    .frame(width: 250)

                Text("Pending payouts + Reserve balance from Stripe")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)

            Spacer()
        }
        .padding()
        .onAppear(perform: loadStripeData)
    }

    private func loadStripeData() {
        isStripeConfigured = StripeAPIService.shared.hasCredentials

        // Load from most recent snapshot
        if let snapshot = StripeSnapshot.mostRecent(in: viewContext) {
            stripeSyncDate = snapshot.snapshotDate
            stripeAvailable = snapshot.availableBalance as Decimal? ?? 0
            stripePending = snapshot.pendingBalance as Decimal? ?? 0
            stripeReserve = snapshot.reserveBalance as Decimal? ?? 0

            // Auto-populate holdback if we have data
            stripeHoldback = stripePending + stripeReserve
        }
    }

    private func syncStripeBalance() {
        isSyncingStripe = true

        Task {
            do {
                let snapshot = try await StripeAPIService.shared.syncBalance(context: viewContext)

                await MainActor.run {
                    stripeSyncDate = snapshot.snapshotDate
                    stripeAvailable = snapshot.availableBalance as Decimal? ?? 0
                    stripePending = snapshot.pendingBalance as Decimal? ?? 0
                    stripeReserve = snapshot.reserveBalance as Decimal? ?? 0
                    stripeHoldback = stripePending + stripeReserve
                    isSyncingStripe = false
                }
            } catch {
                await MainActor.run {
                    isSyncingStripe = false
                    self.error = error
                    showingError = true
                }
            }
        }
    }

    // MARK: - Step 4: Review

    private var reviewStep: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let calc = calculation {
                    // Summary header
                    VStack(spacing: 8) {
                        Image(systemName: calc.isBalanced ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(calc.isBalanced ? .green : .orange)

                        Text(calc.isBalanced ? "Account Balanced!" : "Variance Detected")
                            .font(.title2)
                            .fontWeight(.bold)

                        if !calc.isBalanced {
                            Text("Variance: \(calc.variance.asCurrency)")
                                .font(.title3)
                                .foregroundColor(.orange)
                        }
                    }
                    .padding()

                    // Calculation breakdown
                    calculationBreakdown(calc)

                    // Drill-down sections
                    drillDownSections(calc)

                } else {
                    ProgressView("Calculating...")
                }
            }
            .padding()
        }
        .onAppear {
            performCalculation()
        }
    }

    private func calculationBreakdown(_ calc: TrustCalculationService.TrustCalculation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Trust Balance Calculation")
                .font(.headline)

            VStack(spacing: 12) {
                CalculationRow(
                    label: "Future Reservation Deposits",
                    value: calc.futureDeposits,
                    count: calc.futureReservationCount,
                    isPositive: true
                )

                CalculationRow(
                    label: "Less: Stripe Holdback",
                    value: calc.stripeHoldback,
                    isSubtraction: true
                )

                CalculationRow(
                    label: "Plus: Unpaid Owner Payouts",
                    value: calc.unpaidOwnerPayouts,
                    count: calc.unpaidPayoutReservationCount,
                    isPositive: true
                )

                CalculationRow(
                    label: "Plus: Unpaid Taxes",
                    value: calc.unpaidTaxes,
                    count: calc.unpaidTaxReservationCount,
                    isPositive: true
                )

                CalculationRow(
                    label: "Plus: Maintenance Reserves",
                    value: calc.maintenanceReserves,
                    isPositive: true
                )

                Divider()

                HStack {
                    Text("Expected Trust Balance")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Text(calc.expectedBalance.asCurrency)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                Divider()

                HStack {
                    Text("Actual Balance (Bank + Stripe)")
                        .font(.subheadline)
                    Spacer()
                    Text(calc.actualBalance.asCurrency)
                        .font(.subheadline)
                }

                Divider()

                HStack {
                    Text("Variance")
                        .font(.subheadline)
                        .fontWeight(.bold)
                    Spacer()
                    Text(calc.variance.asCurrency)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(calc.isBalanced ? .green : .red)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    private func drillDownSections(_ calc: TrustCalculationService.TrustCalculation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Future Deposits
            DisclosureGroup {
                ForEach(calc.futureReservations) { res in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(res.guestName)
                                .font(.subheadline)
                            Text("\(res.propertyName) • \(res.checkInDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(res.depositAmount.asCurrency)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                }
            } label: {
                HStack {
                    Text("Future Deposits (\(calc.futureReservationCount))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text(calc.futureDeposits.asCurrency)
                        .font(.subheadline)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // Unpaid Payouts
            DisclosureGroup {
                ForEach(calc.unpaidPayoutReservations) { res in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(res.guestName)
                                .font(.subheadline)
                            Text("\(res.propertyName) • \(res.ownerName)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(res.ownerPayout.asCurrency)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                }
            } label: {
                HStack {
                    Text("Unpaid Owner Payouts (\(calc.unpaidPayoutReservationCount))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text(calc.unpaidOwnerPayouts.asCurrency)
                        .font(.subheadline)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // Unpaid Taxes
            DisclosureGroup {
                ForEach(calc.unpaidTaxReservations) { res in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(res.guestName)
                                .font(.subheadline)
                            Text("\(res.propertyName) • \(res.checkOutDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(res.taxAmount.asCurrency)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                }
            } label: {
                HStack {
                    Text("Unpaid Taxes (\(calc.unpaidTaxReservationCount))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text(calc.unpaidTaxes.asCurrency)
                        .font(.subheadline)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    private func performCalculation() {
        let service = TrustCalculationService(context: viewContext)
        calculation = service.calculateExpectedBalance(
            bankBalance: bankBalance,
            stripeHoldback: stripeHoldback
        )
    }

    // MARK: - Step 5: Confirm

    private var confirmStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)

            Text("Reconciliation Complete!")
                .font(.title2)
                .fontWeight(.semibold)

            if let calc = calculation {
                VStack(spacing: 8) {
                    Text("Status: \(calc.isBalanced ? "Balanced" : "Variance of \(calc.variance.asCurrency)")")
                        .font(.headline)
                        .foregroundColor(calc.isBalanced ? .green : .orange)

                    Text("This reconciliation has been saved.")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Notes (optional)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextEditor(text: $notes)
                    .frame(height: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }
            .frame(maxWidth: 400)

            Spacer()
        }
        .padding()
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }

            Spacer()

            if currentStep > 0 {
                Button("Back") {
                    withAnimation { currentStep -= 1 }
                }
            }

            if currentStep < steps.count - 1 {
                Button("Next") {
                    if currentStep == 2 {
                        performCalculation()
                    }
                    withAnimation { currentStep += 1 }
                }
                .buttonStyle(.borderedProminent)
                .disabled(currentStep == 0 && isSyncing)
            } else {
                Button("Save & Close") {
                    saveReconciliation()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    private func saveReconciliation() {
        guard let calc = calculation else { return }

        let service = TrustCalculationService(context: viewContext)
        do {
            _ = try service.saveReconciliation(calc, notes: notes.isEmpty ? nil : notes)
            dismiss()
        } catch {
            self.error = error
            showingError = true
        }
    }
}

// MARK: - Supporting Views

struct CalculationRow: View {
    let label: String
    let value: Decimal
    var count: Int? = nil
    var isPositive: Bool = false
    var isSubtraction: Bool = false

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                if isSubtraction {
                    Text("-")
                        .foregroundColor(.red)
                } else if isPositive && !isSubtraction {
                    Text("+")
                        .foregroundColor(.green)
                }
                Text(label)
                if let count = count {
                    Text("(\(count))")
                        .foregroundColor(.secondary)
                }
            }
            .font(.subheadline)

            Spacer()

            Text(value.asCurrency)
                .font(.subheadline)
                .foregroundColor(isSubtraction ? .red : .primary)
        }
    }
}

#Preview {
    ReconciliationWizardView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
