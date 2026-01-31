import SwiftUI
import CoreData

struct GeneralSettingsSection: View {
    @Environment(\.managedObjectContext) private var viewContext

    @State private var companyName = ""
    @State private var defaultManagementFee: Double = 20.0
    @State private var maintenanceReserves: Decimal = 0
    @State private var isSaving = false
    @State private var alert: AlertItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("General Settings")
                .font(.title2)
                .fontWeight(.bold)

            SettingsGroup(title: "Company Information") {
                SettingsTextField(label: "Company Name", text: $companyName)
            }

            SettingsGroup(title: "Defaults") {
                HStack {
                    Text("Default Management Fee")
                        .frame(width: 180, alignment: .leading)
                    TextField("", value: $defaultManagementFee, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("%")
                }
            }

            SettingsGroup(title: "Maintenance Reserves") {
                HStack {
                    Text("Total Reserves Held")
                        .frame(width: 180, alignment: .leading)
                    TextField("", value: $maintenanceReserves, format: .currency(code: "USD"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                }

                Text("Total maintenance reserves held for all owners. This amount is included in your trust account reconciliation as funds that should be in the account.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Spacer()
                Button(action: save) {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text("Save Changes")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
        }
        .onAppear(perform: loadSettings)
        .alert(item: $alert) { $0.buildAlert() }
    }

    private func loadSettings() {
        let settings = AppSettings.getOrCreate(in: viewContext)
        companyName = settings.companyName ?? ""
        defaultManagementFee = (settings.defaultManagementFeePercent as Decimal? ?? 20).doubleValue
        maintenanceReserves = settings.maintenanceReserves as Decimal? ?? 0
    }

    private func save() {
        isSaving = true
        let settings = AppSettings.getOrCreate(in: viewContext)
        settings.companyName = companyName.isEmpty ? nil : companyName
        settings.defaultManagementFeePercent = Decimal(defaultManagementFee) as NSDecimalNumber
        settings.maintenanceReserves = maintenanceReserves as NSDecimalNumber
        settings.updatedAt = Date()

        do {
            try viewContext.save()
            alert = .success(message: "Settings saved successfully")
        } catch {
            alert = .error(error)
        }
        isSaving = false
    }
}

// MARK: - Reconciliation Settings

struct ReconciliationSettingsSection: View {
    @Environment(\.managedObjectContext) private var viewContext

    @State private var varianceThreshold: Double = 100.0
    @State private var reminderDays: Int = 7
    @State private var alert: AlertItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Reconciliation Settings")
                .font(.title2)
                .fontWeight(.bold)

            SettingsGroup(title: "Alerts") {
                HStack {
                    Text("Variance Alert Threshold")
                        .frame(width: 180, alignment: .leading)
                    Text("$")
                    TextField("", value: $varianceThreshold, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }

                Text("Show alerts when reconciliation variance exceeds this amount")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            SettingsGroup(title: "Reminders") {
                HStack {
                    Text("Reconciliation Reminder")
                        .frame(width: 180, alignment: .leading)
                    TextField("", value: $reminderDays, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    Text("days")
                }

                Text("Show reminder when last reconciliation is older than this")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Spacer()
                Button("Save Changes") {
                    save()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .onAppear(perform: loadSettings)
        .alert(item: $alert) { $0.buildAlert() }
    }

    private func loadSettings() {
        let settings = AppSettings.getOrCreate(in: viewContext)
        varianceThreshold = (settings.varianceThreshold as Decimal? ?? 100).doubleValue
        reminderDays = Int(settings.reconciliationReminderDays)
    }

    private func save() {
        let settings = AppSettings.getOrCreate(in: viewContext)
        settings.varianceThreshold = Decimal(varianceThreshold) as NSDecimalNumber
        settings.reconciliationReminderDays = Int16(reminderDays)
        settings.updatedAt = Date()

        do {
            try viewContext.save()
            alert = .success(message: "Reconciliation settings saved")
        } catch {
            alert = .error(error)
        }
    }
}

// MARK: - Tax Remittance

struct TaxRemittanceSection: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var selectedMonth: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var unpaidMonths: [MonthYear] = []
    @State private var alert: AlertItem?
    @State private var isProcessing = false

    struct MonthYear: Identifiable, Hashable {
        let id = UUID()
        let month: Int
        let year: Int
        let unpaidAmount: Decimal
        let reservationCount: Int

        var displayName: String {
            let components = DateComponents(year: year, month: month, day: 1)
            guard let date = Calendar.current.date(from: components) else { return "Unknown" }
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: date)
        }

        var date: Date {
            let components = DateComponents(year: year, month: month, day: 1)
            return Calendar.current.date(from: components) ?? Date()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Tax Remittance")
                .font(.title2)
                .fontWeight(.bold)

            Text("Mark monthly taxes as paid to clear them from the unpaid taxes calculation.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            SettingsGroup(title: "Months with Unpaid Taxes") {
                if unpaidMonths.isEmpty {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("All taxes have been marked as paid!")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else {
                    VStack(spacing: 12) {
                        ForEach(unpaidMonths) { monthYear in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(monthYear.displayName)
                                        .font(.subheadline)
                                        .fontWeight(.medium)

                                    Text("\(monthYear.reservationCount) reservations")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Text(monthYear.unpaidAmount.asCurrency)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.orange)

                                Button(action: { markAsPaid(monthYear) }) {
                                    if isProcessing {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    } else {
                                        Text("Mark Paid")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                                .disabled(isProcessing)
                            }
                            .padding()
                            .background(Color(NSColor.windowBackgroundColor))
                            .cornerRadius(8)
                        }
                    }
                }
            }

            // Info section
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text("When you mark a month as paid:")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text("• All reservations with checkout in that month will be marked as tax remitted")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("• The taxes will no longer appear in the unpaid taxes total")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("• This action cannot be undone (but you can manually edit reservations if needed)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
        }
        .onAppear(perform: loadUnpaidMonths)
        .alert(item: $alert) { $0.buildAlert() }
    }

    private func loadUnpaidMonths() {
        // Fetch all reservations with unpaid taxes
        let request: NSFetchRequest<Reservation> = Reservation.fetchRequest()
        request.predicate = NSPredicate(
            format: "checkOutDate <= %@ AND isCancelled == NO AND taxRemitted == NO AND taxAmount > 0",
            Date() as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Reservation.checkOutDate, ascending: true)]

        guard let reservations = try? viewContext.fetch(request) else {
            unpaidMonths = []
            return
        }

        // Group by month/year
        var monthGroups: [String: (month: Int, year: Int, amount: Decimal, count: Int)] = [:]

        for reservation in reservations {
            guard let checkOut = reservation.checkOutDate else { continue }
            let components = Calendar.current.dateComponents([.month, .year], from: checkOut)
            guard let month = components.month, let year = components.year else { continue }

            let key = "\(year)-\(month)"
            let taxAmount = reservation.taxAmount as Decimal? ?? 0

            if var existing = monthGroups[key] {
                existing.amount += taxAmount
                existing.count += 1
                monthGroups[key] = existing
            } else {
                monthGroups[key] = (month: month, year: year, amount: taxAmount, count: 1)
            }
        }

        // Convert to array and sort by date
        unpaidMonths = monthGroups.values
            .map { MonthYear(month: $0.month, year: $0.year, unpaidAmount: $0.amount, reservationCount: $0.count) }
            .sorted { $0.date < $1.date }
    }

    private func markAsPaid(_ monthYear: MonthYear) {
        isProcessing = true

        // Get start and end of the month
        var components = DateComponents()
        components.year = monthYear.year
        components.month = monthYear.month
        components.day = 1

        guard let startOfMonth = Calendar.current.date(from: components),
              let endOfMonth = Calendar.current.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth) else {
            isProcessing = false
            return
        }

        // Add one day to end of month to include the last day
        let endOfMonthPlusOne = Calendar.current.date(byAdding: .day, value: 1, to: endOfMonth) ?? endOfMonth

        // Fetch and update all reservations for this month
        let request: NSFetchRequest<Reservation> = Reservation.fetchRequest()
        request.predicate = NSPredicate(
            format: "checkOutDate >= %@ AND checkOutDate < %@ AND isCancelled == NO AND taxRemitted == NO AND taxAmount > 0",
            startOfMonth as NSDate,
            endOfMonthPlusOne as NSDate
        )

        do {
            let reservations = try viewContext.fetch(request)
            for reservation in reservations {
                reservation.taxRemitted = true
                reservation.taxRemittedDate = Date()
            }

            try viewContext.save()

            // Reload the list
            loadUnpaidMonths()

            alert = .success(message: "Marked \(reservations.count) reservations as tax remitted for \(monthYear.displayName)")
        } catch {
            alert = .error(error)
        }

        isProcessing = false
    }
}
