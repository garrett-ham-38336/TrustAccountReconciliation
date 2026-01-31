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
                case .taxRemittance:
                    TaxRemittanceSection()
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

#Preview {
    SettingsView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
