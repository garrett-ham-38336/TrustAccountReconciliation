import SwiftUI
import CoreData

struct ReservationsView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Reservation.checkInDate, ascending: false)],
        animation: .default
    )
    private var reservations: FetchedResults<Reservation>

    @State private var searchText = ""
    @State private var filterStatus: FilterStatus = .all
    @State private var selectedReservation: Reservation?

    enum FilterStatus: String, CaseIterable {
        case all = "All"
        case future = "Future"
        case active = "Active"
        case completed = "Completed"
        case cancelled = "Cancelled"
    }

    var body: some View {
        HSplitView {
            // List
            listView
                .frame(minWidth: 400, maxWidth: 500)

            // Detail
            if let reservation = selectedReservation {
                ReservationDetailView(reservation: reservation)
            } else {
                emptyDetailView
            }
        }
        .navigationTitle("Reservations")
        .searchable(text: $searchText, prompt: "Search reservations")
        .toolbar {
            ToolbarItemGroup {
                Picker("Filter", selection: $filterStatus) {
                    ForEach(FilterStatus.allCases, id: \.self) { status in
                        Text(status.rawValue).tag(status)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var listView: some View {
        VStack(spacing: 0) {
            // Summary header
            HStack {
                Text("\(filteredReservations.count) reservations")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if filteredReservations.isEmpty {
                emptyListView
            } else {
                List(filteredReservations, selection: $selectedReservation) { reservation in
                    ReservationListRow(reservation: reservation)
                        .tag(reservation)
                }
                .listStyle(.plain)
            }
        }
    }

    private var filteredReservations: [Reservation] {
        var results = Array(reservations)

        // Apply status filter
        switch filterStatus {
        case .all:
            break
        case .future:
            results = results.filter { $0.isFuture }
        case .active:
            results = results.filter { $0.isActive }
        case .completed:
            results = results.filter { $0.isCompleted && !$0.isCancelled }
        case .cancelled:
            results = results.filter { $0.isCancelled }
        }

        // Apply search
        if !searchText.isEmpty {
            results = results.filter { reservation in
                (reservation.guestName?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (reservation.confirmationCode?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (reservation.property?.name?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        return results
    }

    private var emptyListView: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Reservations")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Sync with Guesty to import your reservations.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var emptyDetailView: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("Select a Reservation")
                .font(.title2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ReservationListRow: View {
    @ObservedObject var reservation: Reservation

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(reservation.guestName ?? "Unknown Guest")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(reservation.property?.displayName ?? "Unknown Property")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(reservation.dateRangeString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text((reservation.totalAmount as Decimal? ?? 0).asCurrency)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(reservation.confirmationCode ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .opacity(reservation.isCancelled ? 0.5 : 1.0)
    }

    private var statusColor: Color {
        if reservation.isCancelled { return .red }
        if reservation.isFuture { return .blue }
        if reservation.isActive { return .green }
        return .gray
    }
}

struct ReservationDetailView: View {
    @ObservedObject var reservation: Reservation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                header

                Divider()

                // Guest info
                guestInfoSection

                Divider()

                // Financial breakdown
                financialSection

                Divider()

                // Payout status
                payoutStatusSection
            }
            .padding()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(reservation.guestName ?? "Unknown Guest")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                StatusBadge(reservation: reservation)
            }

            Text(reservation.property?.displayName ?? "Unknown Property")
                .font(.headline)
                .foregroundColor(.secondary)

            HStack(spacing: 16) {
                Label(reservation.dateRangeString, systemImage: "calendar")
                Label("\(reservation.nightCount) nights", systemImage: "moon.fill")
                if let code = reservation.confirmationCode {
                    Label(code, systemImage: "number")
                }
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
    }

    private var guestInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Guest Information")
                .font(.headline)

            VStack(spacing: 8) {
                if let email = reservation.guestEmail {
                    DetailInfoRow(label: "Email", value: email)
                }
                if let phone = reservation.guestPhone {
                    DetailInfoRow(label: "Phone", value: phone)
                }
                if let source = reservation.source {
                    DetailInfoRow(label: "Booking Source", value: source)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    private var financialSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Financial Breakdown")
                .font(.headline)

            VStack(spacing: 8) {
                DetailInfoRow(label: "Accommodation", value: (reservation.accommodationFare as Decimal? ?? 0).asCurrency)
                DetailInfoRow(label: "Cleaning Fee", value: (reservation.cleaningFee as Decimal? ?? 0).asCurrency)
                DetailInfoRow(label: "Taxes", value: (reservation.taxAmount as Decimal? ?? 0).asCurrency)

                Divider()

                DetailInfoRow(label: "Total", value: (reservation.totalAmount as Decimal? ?? 0).asCurrency, isBold: true)
                DetailInfoRow(label: "Deposit Received", value: (reservation.depositReceived as Decimal? ?? 0).asCurrency)

                Divider()

                DetailInfoRow(label: "Management Fee", value: (reservation.managementFee as Decimal? ?? 0).asCurrency)
                DetailInfoRow(label: "Owner Payout", value: (reservation.ownerPayout as Decimal? ?? 0).asCurrency, isBold: true)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    private var payoutStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Payout Status")
                .font(.headline)

            VStack(spacing: 8) {
                HStack {
                    Text("Owner Paid Out")
                    Spacer()
                    if reservation.ownerPaidOut {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            if let date = reservation.ownerPaidOutDate {
                                Text(date.formatted(date: .abbreviated, time: .omitted))
                            }
                        }
                    } else {
                        Text("Pending")
                            .foregroundColor(.orange)
                    }
                }
                .font(.subheadline)

                HStack {
                    Text("Tax Remitted")
                    Spacer()
                    if reservation.taxRemitted {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            if let date = reservation.taxRemittedDate {
                                Text(date.formatted(date: .abbreviated, time: .omitted))
                            }
                        }
                    } else {
                        Text("Pending")
                            .foregroundColor(.orange)
                    }
                }
                .font(.subheadline)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
}

struct StatusBadge: View {
    let reservation: Reservation

    var body: some View {
        Text(statusText)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(statusColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.15))
            .cornerRadius(4)
    }

    private var statusText: String {
        if reservation.isCancelled { return "Cancelled" }
        if reservation.isFuture { return "Upcoming" }
        if reservation.isActive { return "Active" }
        return "Completed"
    }

    private var statusColor: Color {
        if reservation.isCancelled { return .red }
        if reservation.isFuture { return .blue }
        if reservation.isActive { return .green }
        return .gray
    }
}

struct DetailInfoRow: View {
    let label: String
    let value: String
    var isBold: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(isBold ? .semibold : .regular)
        }
    }
}

#Preview {
    ReservationsView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
