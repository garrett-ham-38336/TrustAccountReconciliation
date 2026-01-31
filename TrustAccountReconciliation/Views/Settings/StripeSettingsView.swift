import SwiftUI
import CoreData

struct StripeSettingsSection: View {
    @Environment(\.managedObjectContext) private var viewContext

    @State private var secretKey = ""
    @State private var isEnabled = false
    @State private var isTesting = false
    @State private var isSaving = false
    @State private var isSyncing = false
    @State private var connectionStatus: ConnectionStatus = .unknown
    @State private var lastSyncDate: Date?
    @State private var lastBalance: (available: Decimal, pending: Decimal, reserve: Decimal)?
    @State private var manualRiskReserve: Decimal = 0
    @State private var alert: AlertItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Stripe API Integration")
                .font(.title2)
                .fontWeight(.bold)

            // Status card
            HStack(spacing: 16) {
                Image(systemName: connectionStatus.icon)
                    .font(.title2)
                    .foregroundColor(connectionStatus.color)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Connection Status")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(connectionStatus.text)
                        .font(.headline)
                        .foregroundColor(connectionStatus.color)
                }

                Spacer()

                if let lastSync = lastSyncDate {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Last Sync")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(lastSync.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // Balance display (if synced)
            if let balance = lastBalance {
                SettingsGroup(title: "Current Balance (from API)") {
                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Available")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(balance.available.asCurrency)
                                .font(.headline)
                                .foregroundColor(.green)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Pending")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(balance.pending.asCurrency)
                                .font(.headline)
                                .foregroundColor(.orange)
                        }

                        Spacer()

                        Button(action: syncBalance) {
                            if isSyncing {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
                        .disabled(isSyncing || !isEnabled)
                    }
                }

                SettingsGroup(title: "Risk Reserve (Manual Entry)") {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Stripe's API does not include risk reserves. Enter your reserve amount from the Stripe Dashboard manually.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Risk Reserve")
                            .frame(width: 120, alignment: .leading)
                        TextField("", value: $manualRiskReserve, format: .currency(code: "USD"))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 150)
                        Button("Save") {
                            saveManualReserve()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 4)

                    Divider()
                        .padding(.vertical, 8)

                    HStack {
                        Text("Total Stripe Holdback")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text((balance.pending + manualRiskReserve).asCurrency)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.indigo)
                    }

                    Text("Pending (\(balance.pending.asCurrency)) + Risk Reserve (\(manualRiskReserve.asCurrency))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Credentials
            SettingsGroup(title: "API Credentials") {
                Toggle("Enable Stripe Integration", isOn: $isEnabled)
                    .padding(.bottom, 8)

                HStack {
                    Text("Secret Key")
                        .frame(width: 180, alignment: .leading)
                    SecureField("sk_live_... or sk_test_...", text: $secretKey)
                        .textFieldStyle(.roundedBorder)
                }
                .disabled(!isEnabled)

                HStack {
                    Button("Test Connection") {
                        testConnection()
                    }
                    .disabled(!isEnabled || secretKey.isEmpty || isTesting)

                    if isTesting {
                        ProgressView()
                            .scaleEffect(0.8)
                    }

                    Spacer()

                    if isEnabled && !secretKey.isEmpty {
                        Button("Clear Credentials") {
                            clearCredentials()
                        }
                        .foregroundColor(.red)
                    }
                }
                .padding(.top, 8)
            }

            // Help text
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 8) {
                    Text("How to get your Stripe API key:")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. Log in to your Stripe Dashboard")
                        Text("2. Go to Developers > API Keys")
                        Text("3. Copy your Secret key (starts with sk_live_ or sk_test_)")
                        Text("4. The key needs read access to Balance")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)

                    Text("Note: Use sk_test_ keys for testing, sk_live_ for production.")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.top, 4)
                }
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)

            // Save button
            HStack {
                Spacer()
                Button(action: save) {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text("Save Credentials")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || (!isEnabled && secretKey.isEmpty))
            }
        }
        .onAppear(perform: loadCredentials)
        .alert(item: $alert) { $0.buildAlert() }
    }

    private func loadCredentials() {
        let service = StripeAPIService.shared
        if let key = service.getCredentials() {
            secretKey = key
            isEnabled = !key.isEmpty
            connectionStatus = .unknown
        }

        // Load last sync info
        if let snapshot = StripeSnapshot.mostRecent(in: viewContext) {
            lastSyncDate = snapshot.snapshotDate
            lastBalance = (
                available: snapshot.availableBalance as Decimal? ?? 0,
                pending: snapshot.pendingBalance as Decimal? ?? 0,
                reserve: snapshot.reserveBalance as Decimal? ?? 0
            )
            // Load manual reserve (stored in reserve field)
            manualRiskReserve = snapshot.reserveBalance as Decimal? ?? 0
            if isEnabled {
                connectionStatus = .connected
            }
        }
    }

    private func saveManualReserve() {
        // Update the most recent snapshot with the manual reserve
        if let snapshot = StripeSnapshot.mostRecent(in: viewContext) {
            snapshot.reserveBalance = manualRiskReserve as NSDecimalNumber
            snapshot.totalBalance = ((snapshot.availableBalance as Decimal? ?? 0) +
                                     (snapshot.pendingBalance as Decimal? ?? 0) +
                                     manualRiskReserve) as NSDecimalNumber
            do {
                try viewContext.save()
                alert = .success(message: "Risk reserve saved")
            } catch {
                alert = .error(error)
            }
        } else {
            alert = .error(NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Sync from Stripe first before entering reserve"]))
        }
    }

    private func testConnection() {
        connectionStatus = .testing
        isTesting = true

        Task {
            do {
                let service = StripeAPIService.shared
                try service.saveCredentials(secretKey: secretKey)
                try await service.authenticate()

                await MainActor.run {
                    connectionStatus = .connected
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    connectionStatus = .failed(error.localizedDescription)
                    isTesting = false
                }
            }
        }
    }

    private func syncBalance() {
        isSyncing = true

        Task {
            do {
                let service = StripeAPIService.shared
                let snapshot = try await service.syncBalance(context: viewContext)

                await MainActor.run {
                    lastSyncDate = snapshot.snapshotDate
                    lastBalance = (
                        available: snapshot.availableBalance as Decimal? ?? 0,
                        pending: snapshot.pendingBalance as Decimal? ?? 0,
                        reserve: snapshot.reserveBalance as Decimal? ?? 0
                    )
                    isSyncing = false
                    alert = .success(message: "Stripe balance synced successfully")
                }
            } catch {
                await MainActor.run {
                    isSyncing = false
                    alert = .error(error)
                }
            }
        }
    }

    private func clearCredentials() {
        do {
            try StripeAPIService.shared.clearCredentials()
            secretKey = ""
            isEnabled = false
            connectionStatus = .unknown
            lastBalance = nil
            alert = .success(message: "Stripe credentials cleared")
        } catch {
            alert = .error(error)
        }
    }

    private func save() {
        isSaving = true

        do {
            let service = StripeAPIService.shared

            if isEnabled && !secretKey.isEmpty {
                try service.saveCredentials(secretKey: secretKey)
            } else if !isEnabled {
                try service.clearCredentials()
            }

            try viewContext.save()
            alert = .success(message: "Stripe settings saved successfully")
        } catch {
            alert = .error(error)
        }

        isSaving = false
    }
}
