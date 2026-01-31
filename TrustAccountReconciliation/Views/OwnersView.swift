import SwiftUI
import CoreData

struct OwnersView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Owner.name, ascending: true)],
        predicate: NSPredicate(format: "isActive == YES"),
        animation: .default
    )
    private var owners: FetchedResults<Owner>

    @State private var selectedOwner: Owner?
    @State private var showingAddOwner = false

    var body: some View {
        HSplitView {
            // List
            listView
                .frame(minWidth: 300, maxWidth: 400)

            // Detail
            if let owner = selectedOwner {
                OwnerDetailView(owner: owner)
            } else {
                emptyDetailView
            }
        }
        .navigationTitle("Owners")
        .toolbar {
            ToolbarItem {
                Button(action: { showingAddOwner = true }) {
                    Label("Add Owner", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddOwner) {
            AddOwnerView()
                .environment(\.managedObjectContext, viewContext)
        }
    }

    private var listView: some View {
        VStack(spacing: 0) {
            if owners.isEmpty {
                emptyListView
            } else {
                List(owners, selection: $selectedOwner) { owner in
                    OwnerListRow(owner: owner)
                        .tag(owner)
                }
                .listStyle(.sidebar)
            }
        }
    }

    private var emptyListView: some View {
        EmptyStateView.owners {
            showingAddOwner = true
        }
    }

    private var emptyDetailView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.circle")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("Select an Owner")
                .font(.title2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct OwnerListRow: View {
    @ObservedObject var owner: Owner
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(owner.initials)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.blue)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(owner.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("\(owner.propertyCount) properties")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            let unpaid = owner.totalUnpaidPayouts(in: viewContext)
            if unpaid > 0 {
                Text(unpaid.asCurrency)
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}

struct OwnerDetailView: View {
    @ObservedObject var owner: Owner
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showingPayoutSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                header

                Divider()

                // Contact info
                contactSection

                Divider()

                // Payout status
                payoutSection

                Divider()

                // Properties
                propertiesSection
            }
            .padding()
        }
        .sheet(isPresented: $showingPayoutSheet) {
            RecordPayoutView(owner: owner)
                .environment(\.managedObjectContext, viewContext)
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 60, height: 60)
                .overlay(
                    Text(owner.initials)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.blue)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(owner.displayName)
                    .font(.title2)
                    .fontWeight(.bold)

                if let email = owner.email {
                    Text(email)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
    }

    private var contactSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Contact Information")
                .font(.headline)

            VStack(spacing: 8) {
                if let email = owner.email {
                    DetailInfoRow(label: "Email", value: email)
                }
                if let phone = owner.phone {
                    DetailInfoRow(label: "Phone", value: phone)
                }
                DetailInfoRow(label: "Management Fee", value: "\(owner.managementFeePercent as Decimal? ?? 20)%")
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    private var payoutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Payout Status")
                    .font(.headline)
                Spacer()
                Button("Record Payout") {
                    showingPayoutSheet = true
                }
                .buttonStyle(.bordered)
            }

            let unpaidAmount = owner.totalUnpaidPayouts(in: viewContext)

            VStack(spacing: 8) {
                DetailInfoRow(
                    label: "Last Payout",
                    value: owner.lastPayoutDate?.formatted(date: .abbreviated, time: .omitted) ?? "Never"
                )
                DetailInfoRow(
                    label: "Days Since Payout",
                    value: owner.daysSinceLastPayout.map { "\($0)" } ?? "N/A"
                )
                DetailInfoRow(label: "Unpaid Amount", value: unpaidAmount.asCurrency, isBold: true)
            }
            .padding()
            .background(unpaidAmount > 0 ? Color.orange.opacity(0.1) : Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    private var propertiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Properties")
                    .font(.headline)
                Spacer()
                Text("\(owner.propertiesList.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if owner.propertiesList.isEmpty {
                Text("No properties assigned")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                VStack(spacing: 8) {
                    ForEach(owner.propertiesList) { property in
                        HStack {
                            Image(systemName: "house.fill")
                                .foregroundColor(.blue)
                            Text(property.displayName)
                                .font(.subheadline)
                            Spacer()
                            Text("\(property.futureReservations.count) upcoming")
                                .font(.caption)
                                .foregroundColor(.secondary)
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
}

struct RecordPayoutView: View {
    let owner: Owner
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    @State private var payoutDate = Date()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Record Payout")
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

            VStack(spacing: 20) {
                Text("Record a payout to \(owner.displayName)")
                    .font(.headline)

                let unpaidAmount = owner.totalUnpaidPayouts(in: viewContext)
                Text("Unpaid Amount: \(unpaidAmount.asCurrency)")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.orange)

                DatePicker("Payout Date", selection: $payoutDate, displayedComponents: .date)
                    .frame(width: 300)

                Text("This will mark all completed reservations as paid out and update the last payout date.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            .padding()

            Spacer()

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Record Payout") {
                    recordPayout()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 450, height: 350)
    }

    private func recordPayout() {
        // Mark all unpaid reservations as paid
        let reservations = owner.unpaidReservations(in: viewContext)
        for reservation in reservations {
            reservation.ownerPaidOut = true
            reservation.ownerPaidOutDate = payoutDate
        }

        // Update owner's last payout date
        owner.lastPayoutDate = payoutDate
        owner.updatedAt = Date()

        do {
            try viewContext.save()
            dismiss()
        } catch {
            // Handle error
        }
    }
}

struct AddOwnerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var managementFeePercent: Decimal = 20

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Owner")
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
                Section("Owner Information") {
                    TextField("Name", text: $name)
                    TextField("Email", text: $email)
                    TextField("Phone", text: $phone)
                }

                Section("Financials") {
                    TextField("Default Management Fee %", value: $managementFeePercent, format: .number)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create Owner") {
                    createOwner()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
    }

    private func createOwner() {
        _ = Owner.create(
            in: viewContext,
            name: name,
            email: email.isEmpty ? nil : email,
            phone: phone.isEmpty ? nil : phone,
            managementFeePercent: managementFeePercent
        )

        do {
            try viewContext.save()
            dismiss()
        } catch {
            // Handle error
        }
    }
}

#Preview {
    OwnersView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
