import SwiftUI
import CoreData

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @State private var selectedSection: SettingsSection = .general
    @State private var alert: AlertItem?

    var body: some View {
        HSplitView {
            // Settings Navigation
            settingsNavigation
                .frame(minWidth: 200, maxWidth: 250)

            // Settings Content
            settingsContent
        }
        .navigationTitle("Settings")
        .alert(item: $alert) { $0.buildAlert() }
    }

    // MARK: - Navigation

    private var settingsNavigation: some View {
        List(selection: $selectedSection) {
            Section("Configuration") {
                ForEach(SettingsSection.configurationSections, id: \.self) { section in
                    SettingsNavRow(section: section)
                        .tag(section)
                }
            }

            Section("Integrations") {
                ForEach(SettingsSection.integrationSections, id: \.self) { section in
                    SettingsNavRow(section: section)
                        .tag(section)
                }
            }

            Section("Data") {
                ForEach(SettingsSection.dataSections, id: \.self) { section in
                    SettingsNavRow(section: section)
                        .tag(section)
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Content

    private var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                switch selectedSection {
                case .general:
                    GeneralSettingsSection()
                case .reconciliation:
                    ReconciliationSettingsSection()
                case .guesty:
                    GuestySettingsSection()
                case .stripe:
                    StripeSettingsSection()
                case .taxJurisdictions:
                    TaxJurisdictionsSettingsSection()
                case .backup:
                    BackupSettingsSection()
                case .syncHistory:
                    SyncHistorySection()
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Settings Sections

enum SettingsSection: String, CaseIterable {
    case general
    case reconciliation
    case guesty
    case stripe
    case taxJurisdictions
    case backup
    case syncHistory

    var displayName: String {
        switch self {
        case .general: return "General"
        case .reconciliation: return "Reconciliation"
        case .guesty: return "Guesty API"
        case .stripe: return "Stripe API"
        case .taxJurisdictions: return "Tax Jurisdictions"
        case .backup: return "Backup & Restore"
        case .syncHistory: return "Sync History"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gear"
        case .reconciliation: return "checkmark.circle.fill"
        case .guesty: return "cloud.fill"
        case .stripe: return "creditcard.fill"
        case .taxJurisdictions: return "percent"
        case .backup: return "externaldrive.fill"
        case .syncHistory: return "clock.arrow.circlepath"
        }
    }

    static var configurationSections: [SettingsSection] {
        [.general, .reconciliation]
    }

    static var integrationSections: [SettingsSection] {
        [.guesty, .stripe, .taxJurisdictions]
    }

    static var dataSections: [SettingsSection] {
        [.backup, .syncHistory]
    }
}

struct SettingsNavRow: View {
    let section: SettingsSection

    var body: some View {
        Label(section.displayName, systemImage: section.icon)
    }
}

// MARK: - General Settings

struct GeneralSettingsSection: View {
    @Environment(\.managedObjectContext) private var viewContext

    @State private var companyName = ""
    @State private var defaultManagementFee: Double = 20.0
    @State private var isSaving = false
    @State private var alert: AlertItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("General Settings")
                .font(.title2)
                .fontWeight(.bold)

            SettingsGroup(title: "Company Information") {
                SettingsTextField(label: "Company Name", text: $companyName)
            }

            SettingsGroup(title: "Defaults") {
                HStack {
                    Text("Default Management Fee")
                        .frame(width: 180, alignment: .leading)
                    TextField("", value: $defaultManagementFee, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("%")
                }
            }

            HStack {
                Spacer()
                Button(action: save) {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text("Save Changes")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
        }
        .onAppear(perform: loadSettings)
        .alert(item: $alert) { $0.buildAlert() }
    }

    private func loadSettings() {
        let settings = AppSettings.getOrCreate(in: viewContext)
        companyName = settings.companyName ?? ""
        defaultManagementFee = (settings.defaultManagementFeePercent as Decimal? ?? 20).doubleValue
    }

    private func save() {
        isSaving = true
        let settings = AppSettings.getOrCreate(in: viewContext)
        settings.companyName = companyName.isEmpty ? nil : companyName
        settings.defaultManagementFeePercent = Decimal(defaultManagementFee) as NSDecimalNumber
        settings.updatedAt = Date()

        do {
            try viewContext.save()
            alert = .success(message: "Settings saved successfully")
        } catch {
            alert = .error(error)
        }
        isSaving = false
    }
}

// MARK: - Reconciliation Settings

struct ReconciliationSettingsSection: View {
    @Environment(\.managedObjectContext) private var viewContext

    @State private var varianceThreshold: Double = 100.0
    @State private var reminderDays: Int = 7
    @State private var alert: AlertItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Reconciliation Settings")
                .font(.title2)
                .fontWeight(.bold)

            SettingsGroup(title: "Alerts") {
                HStack {
                    Text("Variance Alert Threshold")
                        .frame(width: 180, alignment: .leading)
                    Text("$")
                    TextField("", value: $varianceThreshold, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }

                Text("Show alerts when reconciliation variance exceeds this amount")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            SettingsGroup(title: "Reminders") {
                HStack {
                    Text("Reconciliation Reminder")
                        .frame(width: 180, alignment: .leading)
                    TextField("", value: $reminderDays, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    Text("days")
                }

                Text("Show reminder when last reconciliation is older than this")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Spacer()
                Button("Save Changes") {
                    save()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .onAppear(perform: loadSettings)
        .alert(item: $alert) { $0.buildAlert() }
    }

    private func loadSettings() {
        let settings = AppSettings.getOrCreate(in: viewContext)
        varianceThreshold = (settings.varianceThreshold as Decimal? ?? 100).doubleValue
        reminderDays = Int(settings.reconciliationReminderDays)
    }

    private func save() {
        let settings = AppSettings.getOrCreate(in: viewContext)
        settings.varianceThreshold = Decimal(varianceThreshold) as NSDecimalNumber
        settings.reconciliationReminderDays = Int16(reminderDays)
        settings.updatedAt = Date()

        do {
            try viewContext.save()
            alert = .success(message: "Reconciliation settings saved")
        } catch {
            alert = .error(error)
        }
    }
}

// MARK: - Guesty Settings

struct GuestySettingsSection: View {
    @Environment(\.managedObjectContext) private var viewContext

    @State private var clientId = ""
    @State private var clientSecret = ""
    @State private var isEnabled = false
    @State private var isTesting = false
    @State private var isSaving = false
    @State private var connectionStatus: ConnectionStatus = .unknown
    @State private var lastSyncDate: Date?
    @State private var alert: AlertItem?

    enum ConnectionStatus {
        case unknown
        case testing
        case connected
        case failed(String)

        var color: Color {
            switch self {
            case .unknown: return .secondary
            case .testing: return .blue
            case .connected: return .green
            case .failed: return .red
            }
        }

        var icon: String {
            switch self {
            case .unknown: return "questionmark.circle"
            case .testing: return "arrow.triangle.2.circlepath"
            case .connected: return "checkmark.circle.fill"
            case .failed: return "xmark.circle.fill"
            }
        }

        var text: String {
            switch self {
            case .unknown: return "Not tested"
            case .testing: return "Testing..."
            case .connected: return "Connected"
            case .failed(let message): return "Failed: \(message)"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Guesty API Integration")
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

            // Credentials
            SettingsGroup(title: "API Credentials") {
                Toggle("Enable Guesty Integration", isOn: $isEnabled)
                    .padding(.bottom, 8)

                SettingsTextField(label: "Client ID", text: $clientId)
                    .disabled(!isEnabled)

                HStack {
                    Text("Client Secret")
                        .frame(width: 180, alignment: .leading)
                    SecureField("", text: $clientSecret)
                        .textFieldStyle(.roundedBorder)
                }
                .disabled(!isEnabled)

                HStack {
                    Button("Test Connection") {
                        testConnection()
                    }
                    .disabled(!isEnabled || clientId.isEmpty || clientSecret.isEmpty || isTesting)

                    if isTesting {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .padding(.top, 8)
            }

            // Help text
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 8) {
                    Text("How to get Guesty API credentials:")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. Log in to your Guesty account")
                        Text("2. Go to Integrations > API")
                        Text("3. Create a new API client with read permissions")
                        Text("4. Copy the Client ID and Client Secret")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
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
                .disabled(isSaving || (!isEnabled && clientId.isEmpty))
            }
        }
        .onAppear(perform: loadCredentials)
        .alert(item: $alert) { $0.buildAlert() }
    }

    private func loadCredentials() {
        let settings = AppSettings.getOrCreate(in: viewContext)
        isEnabled = settings.guestyIntegrationEnabled
        lastSyncDate = settings.lastGuestySyncDate

        // Load from keychain
        if let creds = GuestyAPIService.shared.getCredentials() {
            clientId = creds.clientId
            clientSecret = creds.clientSecret
            connectionStatus = .unknown
        }
    }

    private func testConnection() {
        connectionStatus = .testing
        isTesting = true

        Task {
            do {
                let service = GuestyAPIService.shared
                try service.saveCredentials(clientId: clientId, clientSecret: clientSecret)
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

    private func save() {
        isSaving = true

        do {
            let service = GuestyAPIService.shared

            if isEnabled && !clientId.isEmpty && !clientSecret.isEmpty {
                try service.saveCredentials(clientId: clientId, clientSecret: clientSecret)
            } else if !isEnabled {
                try service.clearCredentials()
            }

            let settings = AppSettings.getOrCreate(in: viewContext)
            settings.guestyIntegrationEnabled = isEnabled
            settings.updatedAt = Date()

            try viewContext.save()
            alert = .success(message: "Guesty settings saved successfully")
        } catch {
            alert = .error(error)
        }

        isSaving = false
    }
}

// MARK: - Stripe Settings

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

    enum ConnectionStatus {
        case unknown
        case testing
        case connected
        case failed(String)

        var color: Color {
            switch self {
            case .unknown: return .secondary
            case .testing: return .blue
            case .connected: return .green
            case .failed: return .red
            }
        }

        var icon: String {
            switch self {
            case .unknown: return "questionmark.circle"
            case .testing: return "arrow.triangle.2.circlepath"
            case .connected: return "checkmark.circle.fill"
            case .failed: return "xmark.circle.fill"
            }
        }

        var text: String {
            switch self {
            case .unknown: return "Not tested"
            case .testing: return "Testing..."
            case .connected: return "Connected"
            case .failed(let message): return "Failed: \(message)"
            }
        }
    }

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

// MARK: - Tax Jurisdictions

struct TaxJurisdictionsSettingsSection: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \TaxJurisdiction.name, ascending: true)],
        predicate: NSPredicate(format: "isActive == YES"),
        animation: .default
    )
    private var jurisdictions: FetchedResults<TaxJurisdiction>

    @State private var showingAddJurisdiction = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Tax Jurisdictions")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                Button(action: { showingAddJurisdiction = true }) {
                    Label("Add Jurisdiction", systemImage: "plus")
                }
            }

            if jurisdictions.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "percent")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No Tax Jurisdictions")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text("Add tax jurisdictions to track and remit occupancy taxes.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Create Arkansas Defaults") {
                        createDefaults()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                VStack(spacing: 12) {
                    ForEach(jurisdictions) { jurisdiction in
                        TaxJurisdictionRow(jurisdiction: jurisdiction)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddJurisdiction) {
            AddTaxJurisdictionView()
                .environment(\.managedObjectContext, viewContext)
        }
    }

    private func createDefaults() {
        // Create Arkansas state tax
        let stateTax = TaxJurisdiction(context: viewContext)
        stateTax.id = UUID()
        stateTax.name = "Arkansas State Tax"
        stateTax.taxType = "occupancy"
        stateTax.taxRate = 6.5 as NSDecimalNumber
        stateTax.remittanceFrequency = "monthly"
        stateTax.remittanceDueDay = 20
        stateTax.isActive = true
        stateTax.createdAt = Date()
        stateTax.updatedAt = Date()

        // Create local tourism tax
        let localTax = TaxJurisdiction(context: viewContext)
        localTax.id = UUID()
        localTax.name = "Local Tourism Tax"
        localTax.taxType = "tourism"
        localTax.taxRate = 3.0 as NSDecimalNumber
        localTax.remittanceFrequency = "monthly"
        localTax.remittanceDueDay = 20
        localTax.isActive = true
        localTax.createdAt = Date()
        localTax.updatedAt = Date()

        try? viewContext.save()
    }
}

struct TaxJurisdictionRow: View {
    @ObservedObject var jurisdiction: TaxJurisdiction

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(jurisdiction.name ?? "Unknown")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    Text(jurisdiction.taxType ?? "occupancy")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let lastRemit = jurisdiction.lastRemittanceDate {
                        Text("Last remitted: \(lastRemit.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            Text("\((jurisdiction.taxRate as Decimal? ?? 0).formatted())%")
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct AddTaxJurisdictionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    @State private var name = ""
    @State private var taxType = "occupancy"
    @State private var taxRate: Double = 0.0
    @State private var remittanceFrequency = "monthly"
    @State private var remittanceDueDay = 20

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Tax Jurisdiction")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            Form {
                Section("Jurisdiction Info") {
                    TextField("Name", text: $name)
                    Picker("Tax Type", selection: $taxType) {
                        Text("Occupancy").tag("occupancy")
                        Text("Tourism").tag("tourism")
                        Text("Sales").tag("sales")
                    }
                    TextField("Tax Rate %", value: $taxRate, format: .number)
                }

                Section("Remittance") {
                    Picker("Frequency", selection: $remittanceFrequency) {
                        Text("Monthly").tag("monthly")
                        Text("Quarterly").tag("quarterly")
                    }
                    Stepper("Due Day: \(remittanceDueDay)", value: $remittanceDueDay, in: 1...28)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create") {
                    createJurisdiction()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
            .padding()
        }
        .frame(width: 450, height: 400)
    }

    private func createJurisdiction() {
        let jurisdiction = TaxJurisdiction(context: viewContext)
        jurisdiction.id = UUID()
        jurisdiction.name = name
        jurisdiction.taxType = taxType
        jurisdiction.taxRate = Decimal(taxRate) as NSDecimalNumber
        jurisdiction.remittanceFrequency = remittanceFrequency
        jurisdiction.remittanceDueDay = Int16(remittanceDueDay)
        jurisdiction.isActive = true
        jurisdiction.createdAt = Date()
        jurisdiction.updatedAt = Date()

        try? viewContext.save()
        dismiss()
    }
}

// MARK: - Backup Settings

struct BackupSettingsSection: View {
    @State private var isBackingUp = false
    @State private var alert: AlertItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Backup & Restore")
                .font(.title2)
                .fontWeight(.bold)

            SettingsGroup(title: "Manual Backup") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Create Backup Now")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text("Creates a complete backup of all data")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(action: createBackup) {
                        if isBackingUp {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text("Create Backup")
                        }
                    }
                    .disabled(isBackingUp)
                }
            }

            SettingsGroup(title: "Restore") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Restore from Backup")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text("Select a backup file to restore")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Choose File...") {
                        restoreBackup()
                    }
                }
            }

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)

                Text("Restoring from a backup will replace all current data. This action cannot be undone.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
        }
        .alert(item: $alert) { $0.buildAlert() }
    }

    private func createBackup() {
        isBackingUp = true

        Task {
            do {
                let url = try await PersistenceController.shared.createBackup()
                await MainActor.run {
                    isBackingUp = false
                    alert = .success(message: "Backup created at \(url.lastPathComponent)")
                }
            } catch {
                await MainActor.run {
                    isBackingUp = false
                    alert = .error(error)
                }
            }
        }
    }

    private func restoreBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "sqlite")!]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            alert = .confirmation(
                title: "Restore Backup",
                message: "This will replace all current data. Are you sure?",
                confirmTitle: "Restore"
            ) {
                do {
                    try PersistenceController.shared.restoreBackup(from: url)
                    alert = .success(message: "Backup restored successfully")
                } catch {
                    alert = .error(error)
                }
            }
        }
    }
}

// MARK: - Sync History

struct SyncHistorySection: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \SyncLog.syncDate, ascending: false)],
        animation: .default
    )
    private var syncLogs: FetchedResults<SyncLog>

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Sync History")
                .font(.title2)
                .fontWeight(.bold)

            if syncLogs.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No Sync History")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text("Sync with Guesty to see history here.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("Date")
                            .frame(width: 150, alignment: .leading)
                        Text("Type")
                            .frame(width: 80, alignment: .leading)
                        Text("Created")
                            .frame(width: 70, alignment: .trailing)
                        Text("Updated")
                            .frame(width: 70, alignment: .trailing)
                        Text("Status")
                            .frame(width: 100, alignment: .leading)
                        Spacer()
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(syncLogs) { log in
                                SyncLogRow(log: log)
                                Divider()
                            }
                        }
                    }
                    .frame(maxHeight: 400)
                }
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
            }
        }
    }
}

struct SyncLogRow: View {
    let log: SyncLog

    var body: some View {
        HStack {
            Text(log.syncDate?.formatted(date: .abbreviated, time: .shortened) ?? "")
                .frame(width: 150, alignment: .leading)

            Text(log.syncType ?? "full")
                .frame(width: 80, alignment: .leading)

            Text("\(log.recordsCreated)")
                .frame(width: 70, alignment: .trailing)

            Text("\(log.recordsUpdated)")
                .frame(width: 70, alignment: .trailing)

            HStack(spacing: 4) {
                Image(systemName: log.status == "success" ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(log.status == "success" ? .green : .red)
                Text(log.status ?? "unknown")
            }
            .frame(width: 100, alignment: .leading)

            Spacer()
        }
        .font(.caption)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - Helper Views

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
}

struct SettingsTextField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 180, alignment: .leading)
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

// MARK: - AppSettings Extension

extension AppSettings {
    static func getOrCreate(in context: NSManagedObjectContext) -> AppSettings {
        let request: NSFetchRequest<AppSettings> = AppSettings.fetchRequest()
        request.fetchLimit = 1

        if let existing = try? context.fetch(request).first {
            return existing
        }

        let settings = AppSettings(context: context)
        settings.id = UUID()
        settings.varianceThreshold = 100 as NSDecimalNumber
        settings.reconciliationReminderDays = 7
        settings.defaultManagementFeePercent = 20 as NSDecimalNumber
        settings.guestyIntegrationEnabled = false
        settings.createdAt = Date()
        settings.updatedAt = Date()

        try? context.save()
        return settings
    }
}

// MARK: - Decimal Extension

extension Decimal {
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}

#Preview {
    SettingsView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
