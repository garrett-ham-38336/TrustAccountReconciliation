import SwiftUI
import CoreData

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
