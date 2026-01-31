import SwiftUI
import AppKit

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
