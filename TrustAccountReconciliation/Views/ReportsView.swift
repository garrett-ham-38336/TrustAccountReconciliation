import SwiftUI
import CoreData

struct ReportsView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @State private var selectedReport: ReportType?
    @State private var startDate = Date().startOfMonth
    @State private var endDate = Date().endOfMonth
    @State private var selectedOwner: Owner?
    @State private var isGenerating = false
    @State private var alert: AlertItem?

    var body: some View {
        HSplitView {
            // Report Selection
            reportSelectionView
                .frame(minWidth: 250, maxWidth: 350)

            // Report Preview/Configuration
            if let report = selectedReport {
                reportConfigurationView(for: report)
            } else {
                emptyStateView
            }
        }
        .navigationTitle("Reports")
        .alert(item: $alert) { $0.buildAlert() }
    }

    // MARK: - Report Selection View

    private var reportSelectionView: some View {
        List(selection: $selectedReport) {
            Section("Trust Account") {
                ForEach(ReportType.trustReports, id: \.self) { report in
                    ReportListRow(report: report)
                        .tag(report)
                }
            }

            Section("Owner Reports") {
                ForEach(ReportType.ownerReports, id: \.self) { report in
                    ReportListRow(report: report)
                        .tag(report)
                }
            }

            Section("Tax Reports") {
                ForEach(ReportType.taxReports, id: \.self) { report in
                    ReportListRow(report: report)
                        .tag(report)
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Report Configuration View

    private func reportConfigurationView(for report: ReportType) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                reportHeader(for: report)

                Divider()

                // Configuration Options
                reportOptions(for: report)

                Divider()

                // Preview
                reportPreview(for: report)

                // Actions
                reportActions
            }
            .padding()
        }
    }

    private func reportHeader(for report: ReportType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: report.icon)
                    .font(.title2)
                    .foregroundColor(report.color)

                Text(report.displayName)
                    .font(.title2)
                    .fontWeight(.bold)
            }

            Text(report.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private func reportOptions(for report: ReportType) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Report Options")
                .font(.headline)

            // Date Range
            if report.requiresDateRange {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Date Range")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack(spacing: 16) {
                        DatePicker("From", selection: $startDate, displayedComponents: .date)
                            .labelsHidden()

                        Text("to")
                            .foregroundColor(.secondary)

                        DatePicker("To", selection: $endDate, displayedComponents: .date)
                            .labelsHidden()

                        Spacer()

                        Menu("Quick Select") {
                            Button("This Month") {
                                startDate = Date().startOfMonth
                                endDate = Date().endOfMonth
                            }
                            Button("Last Month") {
                                let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
                                startDate = lastMonth.startOfMonth
                                endDate = lastMonth.endOfMonth
                            }
                            Button("This Quarter") {
                                let (start, end) = currentQuarterDates()
                                startDate = start
                                endDate = end
                            }
                            Button("This Year") {
                                startDate = Calendar.current.date(from: Calendar.current.dateComponents([.year], from: Date()))!
                                endDate = Date()
                            }
                        }
                    }
                }
            }

            // Owner selection
            if report.requiresOwnerSelection {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Owner")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    OwnerReportPicker(selection: $selectedOwner)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func reportPreview(for report: ReportType) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Preview")
                .font(.headline)

            ReportPreviewContent(
                report: report,
                startDate: startDate,
                endDate: endDate,
                owner: selectedOwner
            )
        }
    }

    private var reportActions: some View {
        HStack {
            Spacer()

            Button(action: { exportReport(format: .csv) }) {
                Label("Export CSV", systemImage: "tablecells")
            }

            Button(action: { exportReport(format: .pdf) }) {
                Label("Export PDF", systemImage: "doc.fill")
            }

            Button(action: { printReport() }) {
                Label("Print", systemImage: "printer")
            }
            .buttonStyle(.borderedProminent)
        }
        .disabled(isGenerating)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("Select a Report")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("Choose a report from the list to configure and generate it.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func exportReport(format: ExportFormat) {
        isGenerating = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isGenerating = false
            alert = .success(message: "Report exported successfully")
        }
    }

    private func printReport() {
        alert = .info(title: "Print", message: "Print functionality coming soon")
    }

    private func currentQuarterDates() -> (Date, Date) {
        let calendar = Calendar.current
        let now = Date()
        let quarter = (calendar.component(.month, from: now) - 1) / 3
        let startMonth = quarter * 3 + 1
        var components = calendar.dateComponents([.year], from: now)
        components.month = startMonth
        components.day = 1
        let start = calendar.date(from: components)!
        let end = calendar.date(byAdding: .month, value: 3, to: start)!.addingTimeInterval(-1)
        return (start, end)
    }
}

// MARK: - Report Types

enum ReportType: String, CaseIterable, Identifiable {
    // Trust Account Reports
    case trustBalanceSummary
    case reconciliationHistory
    case futureDeposits

    // Owner Reports
    case ownerPayoutSummary
    case ownerStatement
    case propertyPerformance

    // Tax Reports
    case taxLiabilitySummary
    case taxRemittanceHistory

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .trustBalanceSummary: return "Trust Balance Summary"
        case .reconciliationHistory: return "Reconciliation History"
        case .futureDeposits: return "Future Deposits Report"
        case .ownerPayoutSummary: return "Owner Payout Summary"
        case .ownerStatement: return "Owner Statement"
        case .propertyPerformance: return "Property Performance"
        case .taxLiabilitySummary: return "Tax Liability Summary"
        case .taxRemittanceHistory: return "Tax Remittance History"
        }
    }

    var description: String {
        switch self {
        case .trustBalanceSummary:
            return "Current trust account balance breakdown showing expected vs actual balance."
        case .reconciliationHistory:
            return "History of all reconciliations with variance tracking."
        case .futureDeposits:
            return "List of all future reservations with deposits held in trust."
        case .ownerPayoutSummary:
            return "Summary of unpaid owner payouts by owner."
        case .ownerStatement:
            return "Detailed statement for a specific owner showing all activity."
        case .propertyPerformance:
            return "Reservation and revenue statistics by property."
        case .taxLiabilitySummary:
            return "Current tax liabilities by jurisdiction."
        case .taxRemittanceHistory:
            return "History of tax remittances and due dates."
        }
    }

    var icon: String {
        switch self {
        case .trustBalanceSummary: return "building.columns.fill"
        case .reconciliationHistory: return "checkmark.circle.fill"
        case .futureDeposits: return "calendar.badge.clock"
        case .ownerPayoutSummary: return "person.2.fill"
        case .ownerStatement: return "envelope.fill"
        case .propertyPerformance: return "chart.bar.fill"
        case .taxLiabilitySummary: return "percent"
        case .taxRemittanceHistory: return "building.fill"
        }
    }

    var color: Color {
        switch self {
        case .trustBalanceSummary, .reconciliationHistory, .futureDeposits:
            return .blue
        case .ownerPayoutSummary, .ownerStatement, .propertyPerformance:
            return .green
        case .taxLiabilitySummary, .taxRemittanceHistory:
            return .orange
        }
    }

    var requiresDateRange: Bool {
        switch self {
        case .trustBalanceSummary, .futureDeposits, .ownerPayoutSummary, .taxLiabilitySummary:
            return false
        default:
            return true
        }
    }

    var requiresOwnerSelection: Bool {
        switch self {
        case .ownerStatement, .propertyPerformance:
            return true
        default:
            return false
        }
    }

    static var trustReports: [ReportType] {
        [.trustBalanceSummary, .reconciliationHistory, .futureDeposits]
    }

    static var ownerReports: [ReportType] {
        [.ownerPayoutSummary, .ownerStatement, .propertyPerformance]
    }

    static var taxReports: [ReportType] {
        [.taxLiabilitySummary, .taxRemittanceHistory]
    }
}

enum ExportFormat {
    case pdf
    case csv
}

// MARK: - Supporting Views

struct ReportListRow: View {
    let report: ReportType

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: report.icon)
                .foregroundColor(report.color)
                .frame(width: 24)

            Text(report.displayName)
                .font(.subheadline)
        }
        .padding(.vertical, 4)
    }
}

struct OwnerReportPicker: View {
    @Binding var selection: Owner?

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Owner.name, ascending: true)],
        predicate: NSPredicate(format: "isActive == YES")
    )
    private var owners: FetchedResults<Owner>

    var body: some View {
        Picker("Owner", selection: $selection) {
            Text("All Owners").tag(nil as Owner?)
            Divider()
            ForEach(owners) { owner in
                Text(owner.displayName).tag(owner as Owner?)
            }
        }
        .labelsHidden()
    }
}

// MARK: - Report Preview Content

struct ReportPreviewContent: View {
    let report: ReportType
    let startDate: Date
    let endDate: Date
    let owner: Owner?

    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Report header preview
            VStack(alignment: .center, spacing: 8) {
                Text("Trust Account Report")
                    .font(.headline)

                Text(report.displayName)
                    .font(.title3)
                    .fontWeight(.bold)

                if report.requiresDateRange {
                    Text("\(startDate.asShortDate) - \(endDate.asShortDate)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text("As of \(Date().asShortDate)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // Dynamic content based on report type
            Group {
                switch report {
                case .trustBalanceSummary:
                    TrustBalancePreview()
                case .futureDeposits:
                    FutureDepositsPreview()
                case .ownerPayoutSummary:
                    OwnerPayoutPreview()
                case .taxLiabilitySummary:
                    TaxLiabilityPreview()
                default:
                    Text("Report preview will appear here when generated.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 200, alignment: .center)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                }
            }
        }
    }
}

// MARK: - Report Preview Components

struct TrustBalancePreview: View {
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        let calculation = TrustCalculationService.shared.calculateExpectedBalance(context: viewContext)

        VStack(spacing: 16) {
            // Summary row
            HStack(spacing: 24) {
                VStack {
                    Text("Expected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(calculation.expectedBalance.asCurrency)
                        .font(.title2)
                        .fontWeight(.bold)
                }

                VStack {
                    Text("Actual")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("--")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                }

                VStack {
                    Text("Variance")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("--")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // Breakdown
            VStack(spacing: 8) {
                HStack {
                    Text("Future Deposits (\(calculation.futureReservations.count))")
                    Spacer()
                    Text(calculation.futureDeposits.asCurrency)
                }
                HStack {
                    Text("- Stripe Holdback")
                    Spacer()
                    Text("--")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("+ Unpaid Owner Payouts (\(calculation.ownerPayouts.count))")
                    Spacer()
                    Text(calculation.unpaidOwnerPayouts.asCurrency)
                }
                HStack {
                    Text("+ Unpaid Taxes (\(calculation.unpaidTaxes.count))")
                    Spacer()
                    Text(calculation.unpaidTaxAmount.asCurrency)
                }
                Divider()
                HStack {
                    Text("Expected Trust Balance")
                        .fontWeight(.semibold)
                    Spacer()
                    Text(calculation.expectedBalance.asCurrency)
                        .fontWeight(.semibold)
                }
            }
            .font(.subheadline)
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
}

struct FutureDepositsPreview: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Reservation.checkInDate, ascending: true)],
        predicate: NSPredicate(format: "checkInDate > %@ AND isCancelled == NO", Date() as NSDate),
        animation: .default
    )
    private var reservations: FetchedResults<Reservation>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Property")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Guest")
                    .frame(width: 120, alignment: .leading)
                Text("Check-In")
                    .frame(width: 100, alignment: .leading)
                Text("Deposit")
                    .frame(width: 100, alignment: .trailing)
            }
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal)

            Divider()

            if reservations.isEmpty {
                Text("No future reservations with deposits")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(reservations.prefix(10)) { reservation in
                    HStack {
                        Text(reservation.property?.displayName ?? "Unknown")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(reservation.guestName ?? "Unknown")
                            .frame(width: 120, alignment: .leading)
                        Text(reservation.checkInDate?.formatted(date: .abbreviated, time: .omitted) ?? "")
                            .frame(width: 100, alignment: .leading)
                        Text((reservation.depositReceived as Decimal? ?? 0).asCurrency)
                            .frame(width: 100, alignment: .trailing)
                    }
                    .font(.caption)
                    .padding(.horizontal)
                }

                if reservations.count > 10 {
                    Text("... and \(reservations.count - 10) more")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }

                Divider()

                let total = reservations.reduce(Decimal(0)) { $0 + ($1.depositReceived as Decimal? ?? 0) }
                HStack {
                    Text("Total")
                        .fontWeight(.semibold)
                    Spacer()
                    Text(total.asCurrency)
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct OwnerPayoutPreview: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Owner.name, ascending: true)],
        predicate: NSPredicate(format: "isActive == YES")
    )
    private var owners: FetchedResults<Owner>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Owner")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Properties")
                    .frame(width: 80, alignment: .trailing)
                Text("Last Payout")
                    .frame(width: 100, alignment: .leading)
                Text("Unpaid Amount")
                    .frame(width: 120, alignment: .trailing)
            }
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal)

            Divider()

            if owners.isEmpty {
                Text("No owners found")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(owners) { owner in
                    let unpaid = owner.totalUnpaidPayouts(in: viewContext)
                    HStack {
                        Text(owner.displayName)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(owner.propertyCount)")
                            .frame(width: 80, alignment: .trailing)
                        Text(owner.lastPayoutDate?.formatted(date: .abbreviated, time: .omitted) ?? "Never")
                            .frame(width: 100, alignment: .leading)
                        Text(unpaid.asCurrency)
                            .frame(width: 120, alignment: .trailing)
                            .foregroundColor(unpaid > 0 ? .orange : .primary)
                    }
                    .font(.caption)
                    .padding(.horizontal)
                }

                Divider()

                let total = owners.reduce(Decimal(0)) { $0 + $1.totalUnpaidPayouts(in: viewContext) }
                HStack {
                    Text("Total Unpaid")
                        .fontWeight(.semibold)
                    Spacer()
                    Text(total.asCurrency)
                        .fontWeight(.semibold)
                        .foregroundColor(total > 0 ? .orange : .primary)
                }
                .font(.subheadline)
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct TaxLiabilityPreview: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Reservation.checkOutDate, ascending: true)],
        predicate: NSPredicate(format: "checkOutDate <= %@ AND isCancelled == NO AND taxRemitted == NO AND taxAmount > 0", Date() as NSDate),
        animation: .default
    )
    private var unpaidTaxReservations: FetchedResults<Reservation>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Reservation")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Property")
                    .frame(width: 150, alignment: .leading)
                Text("Check-Out")
                    .frame(width: 100, alignment: .leading)
                Text("Tax Amount")
                    .frame(width: 100, alignment: .trailing)
            }
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal)

            Divider()

            if unpaidTaxReservations.isEmpty {
                Text("No unpaid tax liabilities")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(unpaidTaxReservations.prefix(10)) { reservation in
                    HStack {
                        Text(reservation.guestName ?? "Unknown")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(reservation.property?.displayName ?? "Unknown")
                            .frame(width: 150, alignment: .leading)
                        Text(reservation.checkOutDate?.formatted(date: .abbreviated, time: .omitted) ?? "")
                            .frame(width: 100, alignment: .leading)
                        Text((reservation.taxAmount as Decimal? ?? 0).asCurrency)
                            .frame(width: 100, alignment: .trailing)
                    }
                    .font(.caption)
                    .padding(.horizontal)
                }

                if unpaidTaxReservations.count > 10 {
                    Text("... and \(unpaidTaxReservations.count - 10) more")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }

                Divider()

                let total = unpaidTaxReservations.reduce(Decimal(0)) { $0 + ($1.taxAmount as Decimal? ?? 0) }
                HStack {
                    Text("Total Unpaid Taxes")
                        .fontWeight(.semibold)
                    Spacer()
                    Text(total.asCurrency)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                }
                .font(.subheadline)
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

#Preview {
    ReportsView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
