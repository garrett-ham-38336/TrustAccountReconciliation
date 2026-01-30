import SwiftUI
import CoreData

struct GuestySyncView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    @State private var isSyncing = false
    @State private var syncProgress: String = ""
    @State private var syncResult: GuestyAPIService.SyncResult?
    @State private var error: Error?
    @State private var showingError = false

    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Text("Sync with Guesty")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            Spacer()

            if let result = syncResult {
                // Success state
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.green)

                    Text("Sync Complete!")
                        .font(.title2)
                        .fontWeight(.semibold)

                    VStack(spacing: 8) {
                        HStack {
                            Text("Properties:")
                            Spacer()
                            Text("\(result.propertiesCreated) created, \(result.propertiesUpdated) updated")
                        }
                        HStack {
                            Text("Reservations:")
                            Spacer()
                            Text("\(result.reservationsCreated) created, \(result.reservationsUpdated) updated")
                        }
                        HStack {
                            Text("Duration:")
                            Spacer()
                            Text(String(format: "%.1f seconds", result.duration))
                        }
                    }
                    .font(.subheadline)
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .frame(maxWidth: 300)

                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if isSyncing {
                // Syncing state
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)

                    Text("Syncing...")
                        .font(.title3)
                        .fontWeight(.medium)

                    Text(syncProgress)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else if !GuestyAPIService.shared.hasCredentials {
                // Not configured state
                VStack(spacing: 16) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.orange)

                    Text("Guesty Not Configured")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Please configure your Guesty API credentials in Settings before syncing.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)

                    Button("Go to Settings") {
                        dismiss()
                        // Navigate to settings
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                // Ready to sync state
                VStack(spacing: 16) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.blue)

                    Text("Ready to Sync")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("This will fetch all reservations from Guesty and update your local database.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)

                    Button("Start Sync") {
                        startSync()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }

            Spacer()
        }
        .frame(width: 500, height: 400)
        .alert("Sync Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(error?.localizedDescription ?? "An unknown error occurred")
        }
    }

    private func startSync() {
        isSyncing = true
        syncProgress = "Connecting to Guesty..."

        Task {
            do {
                let result = try await GuestyAPIService.shared.syncReservations(
                    context: viewContext
                ) { progress in
                    Task { @MainActor in
                        syncProgress = progress
                    }
                }

                await MainActor.run {
                    isSyncing = false
                    syncResult = result
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
}

#Preview {
    GuestySyncView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
