import SwiftUI
import CoreData

struct PropertiesView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Property.name, ascending: true)],
        predicate: NSPredicate(format: "isActive == YES"),
        animation: .default
    )
    private var properties: FetchedResults<Property>

    @State private var selectedProperty: Property?
    @State private var showingAddProperty = false

    var body: some View {
        HSplitView {
            // List
            listView
                .frame(minWidth: 300, maxWidth: 400)

            // Detail
            if let property = selectedProperty {
                PropertyDetailView(property: property)
            } else {
                emptyDetailView
            }
        }
        .navigationTitle("Properties")
        .toolbar {
            ToolbarItem {
                Button(action: { showingAddProperty = true }) {
                    Label("Add Property", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddProperty) {
            AddPropertyView()
                .environment(\.managedObjectContext, viewContext)
        }
    }

    private var listView: some View {
        VStack(spacing: 0) {
            if properties.isEmpty {
                emptyListView
            } else {
                List(properties, selection: $selectedProperty) { property in
                    PropertyListRow(property: property)
                        .tag(property)
                }
                .listStyle(.sidebar)
            }
        }
    }

    private var emptyListView: some View {
        VStack(spacing: 16) {
            Image(systemName: "house")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Properties")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Sync with Guesty to import your properties, or add them manually.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Add Property") {
                showingAddProperty = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var emptyDetailView: some View {
        VStack(spacing: 16) {
            Image(systemName: "house.fill")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("Select a Property")
                .font(.title2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PropertyListRow: View {
    @ObservedObject var property: Property

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "house.fill")
                .foregroundColor(.blue)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(property.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let owner = property.owner {
                    Text(owner.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text("\(property.futureReservations.count) upcoming")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct PropertyDetailView: View {
    @ObservedObject var property: Property
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                header

                Divider()

                // Details
                detailsSection

                Divider()

                // Upcoming Reservations
                upcomingReservationsSection

                Divider()

                // Stats
                statsSection
            }
            .padding()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(property.displayName)
                .font(.title2)
                .fontWeight(.bold)

            if !property.fullAddress.isEmpty {
                Text(property.fullAddress)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if let owner = property.owner {
                Label(owner.displayName, systemImage: "person.fill")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)

            VStack(spacing: 8) {
                DetailInfoRow(label: "Management Fee", value: "\(property.effectiveManagementFeePercent)%")
                if let guestyId = property.guestyListingId {
                    DetailInfoRow(label: "Guesty ID", value: guestyId)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    private var upcomingReservationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Upcoming Reservations")
                    .font(.headline)
                Spacer()
                Text("\(property.futureReservations.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if property.futureReservations.isEmpty {
                Text("No upcoming reservations")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                VStack(spacing: 8) {
                    ForEach(property.futureReservations.prefix(5)) { reservation in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(reservation.guestName ?? "Unknown")
                                    .font(.subheadline)
                                Text(reservation.dateRangeString)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text((reservation.totalAmount as Decimal? ?? 0).asCurrency)
                                .font(.subheadline)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
        }
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Statistics")
                .font(.headline)

            let totalDeposits = property.futureReservations.reduce(Decimal(0)) {
                $0 + ($1.depositReceived as Decimal? ?? 0)
            }

            VStack(spacing: 8) {
                DetailInfoRow(label: "Future Deposits Held", value: totalDeposits.asCurrency)
                DetailInfoRow(label: "Total Reservations", value: "\(property.reservationsList.count)")
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
}

struct AddPropertyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Owner.name, ascending: true)],
        predicate: NSPredicate(format: "isActive == YES")
    )
    private var owners: FetchedResults<Owner>

    @State private var name = ""
    @State private var address = ""
    @State private var city = ""
    @State private var state = "AR"
    @State private var zipCode = ""
    @State private var selectedOwner: Owner?
    @State private var managementFeePercent: Decimal = 20

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Property")
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
                Section("Property Information") {
                    TextField("Property Name", text: $name)
                    TextField("Address", text: $address)
                    TextField("City", text: $city)
                    TextField("State", text: $state)
                    TextField("ZIP Code", text: $zipCode)
                }

                Section("Owner") {
                    Picker("Owner", selection: $selectedOwner) {
                        Text("None").tag(nil as Owner?)
                        ForEach(owners) { owner in
                            Text(owner.displayName).tag(owner as Owner?)
                        }
                    }
                }

                Section("Financials") {
                    TextField("Management Fee %", value: $managementFeePercent, format: .number)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create Property") {
                    createProperty()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 500)
    }

    private func createProperty() {
        let property = Property.create(
            in: viewContext,
            name: name,
            address: address.isEmpty ? nil : address,
            owner: selectedOwner
        )
        property.city = city.isEmpty ? nil : city
        property.state = state
        property.zipCode = zipCode.isEmpty ? nil : zipCode
        property.managementFeePercent = managementFeePercent as NSDecimalNumber

        do {
            try viewContext.save()
            dismiss()
        } catch {
            // Handle error
        }
    }
}

#Preview {
    PropertiesView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
