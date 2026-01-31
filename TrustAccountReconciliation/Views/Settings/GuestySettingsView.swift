import SwiftUI
import CoreData

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
