import SwiftUI

@main
struct TrustAccountReconciliationApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) { }

            CommandMenu("Trust Account") {
                Button("Run Reconciliation...") {
                    NotificationCenter.default.post(name: .runReconciliation, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("Sync with Guesty...") {
                    NotificationCenter.default.post(name: .syncGuesty, object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            }
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
        #endif
    }
}
