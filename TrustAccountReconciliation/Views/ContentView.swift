import SwiftUI
import CoreData

/// Main content view with sidebar navigation for the simplified Trust Account Reconciliation system.
struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var selectedNavigation: NavigationItem? = .dashboard
    @State private var showingReconciliationWizard = false
    @State private var showingSync = false

    var body: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            detailContent
        }
        .frame(minWidth: 1000, minHeight: 700)
        .onReceive(NotificationCenter.default.publisher(for: .runReconciliation)) { _ in
            showingReconciliationWizard = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .syncGuesty)) { _ in
            showingSync = true
        }
        .sheet(isPresented: $showingReconciliationWizard) {
            ReconciliationWizardView()
                .environment(\.managedObjectContext, viewContext)
        }
        .sheet(isPresented: $showingSync) {
            GuestySyncView()
                .environment(\.managedObjectContext, viewContext)
        }
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        List(selection: $selectedNavigation) {
            Section {
                NavigationLink(value: NavigationItem.dashboard) {
                    Label("Dashboard", systemImage: "gauge.with.dots.needle.bottom.50percent")
                }
            }

            Section("Data") {
                NavigationLink(value: NavigationItem.reservations) {
                    Label("Reservations", systemImage: "calendar")
                }

                NavigationLink(value: NavigationItem.properties) {
                    Label("Properties", systemImage: "house.fill")
                }

                NavigationLink(value: NavigationItem.owners) {
                    Label("Owners", systemImage: "person.2.fill")
                }
            }

            Section("Accounting") {
                NavigationLink(value: NavigationItem.reconciliation) {
                    Label("Reconciliation", systemImage: "checkmark.circle.fill")
                }

                NavigationLink(value: NavigationItem.reports) {
                    Label("Reports", systemImage: "chart.bar.doc.horizontal")
                }
            }

            Section {
                NavigationLink(value: NavigationItem.settings) {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
        .toolbar {
            ToolbarItem {
                Button(action: { showingReconciliationWizard = true }) {
                    Label("Reconcile", systemImage: "checkmark.circle")
                }
            }

            ToolbarItem {
                Button(action: { showingSync = true }) {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
            }
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        switch selectedNavigation {
        case .dashboard:
            DashboardView()
        case .reservations:
            ReservationsView()
        case .properties:
            PropertiesView()
        case .owners:
            OwnersView()
        case .reconciliation:
            ReconciliationHistoryView()
        case .reports:
            ReportsView()
        case .settings:
            SettingsView()
        case .none:
            DashboardView()
        }
    }
}

// MARK: - Navigation Items

enum NavigationItem: String, Identifiable, CaseIterable {
    case dashboard
    case reservations
    case properties
    case owners
    case reconciliation
    case reports
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .reservations: return "Reservations"
        case .properties: return "Properties"
        case .owners: return "Owners"
        case .reconciliation: return "Reconciliation"
        case .reports: return "Reports"
        case .settings: return "Settings"
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let runReconciliation = Notification.Name("runReconciliation")
    static let syncGuesty = Notification.Name("syncGuesty")
}

// MARK: - Preview

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
