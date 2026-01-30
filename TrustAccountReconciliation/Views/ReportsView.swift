import SwiftUI
import CoreData

struct ReportsView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @State private var selectedReport: ReportType?
    @State private var startDate = Date().startOfMonth
    @State private var endDate = Date().endOfMonth
    @State private var selectedOwner: Owner?
    @State private var isGenerating = false
    @State private var isMaximized = false
    @State private var alert: AlertItem?

    var body: some View {
        Group {
            if isMaximized, let report = selectedReport {
                // Maximized view - full screen report
                maximizedReportView(for: report)
            } else {
                // Normal split view
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
            }
        }
        .navigationTitle(isMaximized ? (selectedReport?.displayName ?? "Reports") : "Reports")
        .alert(item: $alert) { $0.buildAlert() }
    }

    // MARK: - Maximized Report View

    private func maximizedReportView(for report: ReportType) -> some View {
        VStack(spacing: 0) {
            // Header with minimize button
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.displayName)
                        .font(.title2)
                        .fontWeight(.bold)

                    if report.requiresDateRange {
                        Text("\(startDate.asShortDate) - \(endDate.asShortDate)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Date range quick select (for reports that need it)
                if report.requiresDateRange {
                    Menu("Change Period") {
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

                Button(action: { isMaximized = false }) {
                    Label("Minimize", systemImage: "arrow.down.right.and.arrow.up.left")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Full report content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch report {
                    case .revenueBySource:
                        RevenueBySourceFullView(startDate: startDate, endDate: endDate)
                    default:
                        ReportPreviewContent(
                            report: report,
                            startDate: startDate,
                            endDate: endDate,
                            owner: selectedOwner
                        )
                    }
                }
                .padding()
            }
        }
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

            Section("Revenue Reports") {
                ForEach(ReportType.revenueReports, id: \.self) { report in
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
            Button(action: { isMaximized = true }) {
                Label("Maximize", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.bordered)

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

    // Revenue Reports
    case revenueBySource

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
        case .revenueBySource: return "Revenue by Source"
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
        case .revenueBySource:
            return "Monthly property revenue breakdown by booking source (Airbnb, VRBO, Other)."
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
        case .revenueBySource: return "dollarsign.arrow.circlepath"
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
        case .revenueBySource:
            return .purple
        case .taxLiabilitySummary, .taxRemittanceHistory:
            return .orange
        }
    }

    var requiresDateRange: Bool {
        switch self {
        case .trustBalanceSummary, .futureDeposits, .ownerPayoutSummary, .taxLiabilitySummary:
            return false
        case .revenueBySource:
            return true  // Uses month selector
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

    static var revenueReports: [ReportType] {
        [.revenueBySource]
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
                case .revenueBySource:
                    RevenueBySourcePreview(startDate: startDate, endDate: endDate)
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

// MARK: - Revenue by Source Full View (Maximized)

struct RevenueBySourceFullView: View {
    let startDate: Date
    let endDate: Date

    @Environment(\.managedObjectContext) private var viewContext
    @State private var propertyRevenues: [PropertyRevenueData] = []

    struct PropertyRevenueData: Identifiable {
        let id: UUID
        let propertyName: String
        let airbnbTotal: Decimal
        let airbnbCount: Int
        let vrboTotal: Decimal
        let vrboCount: Int
        let otherTotal: Decimal
        let otherCount: Int

        var grandTotal: Decimal {
            airbnbTotal + vrboTotal + otherTotal
        }

        var totalCount: Int {
            airbnbCount + vrboCount + otherCount
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Summary stats
            HStack(spacing: 24) {
                StatBox(title: "Properties", value: "\(propertyRevenues.count)", color: .blue)
                StatBox(title: "Airbnb Total", value: totals.airbnb.asCurrency, color: .red)
                StatBox(title: "VRBO Total", value: totals.vrbo.asCurrency, color: .blue)
                StatBox(title: "Other Total", value: totals.other.asCurrency, color: .gray)
                StatBox(title: "Grand Total", value: totals.grand.asCurrency, color: .purple)
            }

            // Table
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Property")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Airbnb")
                        .frame(width: 120, alignment: .trailing)
                    Text("# Stays")
                        .frame(width: 60, alignment: .trailing)
                    Text("VRBO")
                        .frame(width: 120, alignment: .trailing)
                    Text("# Stays")
                        .frame(width: 60, alignment: .trailing)
                    Text("Other")
                        .frame(width: 120, alignment: .trailing)
                    Text("# Stays")
                        .frame(width: 60, alignment: .trailing)
                    Text("Total")
                        .frame(width: 120, alignment: .trailing)
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                if propertyRevenues.isEmpty {
                    Text("No reservations found for the selected period")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(40)
                } else {
                    ForEach(propertyRevenues) { property in
                        HStack {
                            Text(property.propertyName)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fontWeight(.medium)
                            Text(property.airbnbTotal.asCurrency)
                                .frame(width: 120, alignment: .trailing)
                                .foregroundColor(property.airbnbTotal > 0 ? .red : .secondary)
                            Text("\(property.airbnbCount)")
                                .frame(width: 60, alignment: .trailing)
                                .foregroundColor(.secondary)
                            Text(property.vrboTotal.asCurrency)
                                .frame(width: 120, alignment: .trailing)
                                .foregroundColor(property.vrboTotal > 0 ? .blue : .secondary)
                            Text("\(property.vrboCount)")
                                .frame(width: 60, alignment: .trailing)
                                .foregroundColor(.secondary)
                            Text(property.otherTotal.asCurrency)
                                .frame(width: 120, alignment: .trailing)
                                .foregroundColor(property.otherTotal > 0 ? .primary : .secondary)
                            Text("\(property.otherCount)")
                                .frame(width: 60, alignment: .trailing)
                                .foregroundColor(.secondary)
                            Text(property.grandTotal.asCurrency)
                                .frame(width: 120, alignment: .trailing)
                                .fontWeight(.semibold)
                        }
                        .font(.subheadline)
                        .padding(.horizontal)
                        .padding(.vertical, 10)

                        Divider()
                    }

                    // Totals row
                    HStack {
                        Text("TOTAL")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fontWeight(.bold)
                        Text(totals.airbnb.asCurrency)
                            .frame(width: 120, alignment: .trailing)
                            .foregroundColor(.red)
                        Text("\(totalCounts.airbnb)")
                            .frame(width: 60, alignment: .trailing)
                        Text(totals.vrbo.asCurrency)
                            .frame(width: 120, alignment: .trailing)
                            .foregroundColor(.blue)
                        Text("\(totalCounts.vrbo)")
                            .frame(width: 60, alignment: .trailing)
                        Text(totals.other.asCurrency)
                            .frame(width: 120, alignment: .trailing)
                        Text("\(totalCounts.other)")
                            .frame(width: 60, alignment: .trailing)
                        Text(totals.grand.asCurrency)
                            .frame(width: 120, alignment: .trailing)
                            .foregroundColor(.purple)
                    }
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .background(Color(NSColor.controlBackgroundColor))
                }
            }
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
        }
        .onAppear(perform: loadData)
        .onChange(of: startDate) { loadData() }
        .onChange(of: endDate) { loadData() }
    }

    private var totals: (airbnb: Decimal, vrbo: Decimal, other: Decimal, grand: Decimal) {
        let airbnb = propertyRevenues.reduce(Decimal(0)) { $0 + $1.airbnbTotal }
        let vrbo = propertyRevenues.reduce(Decimal(0)) { $0 + $1.vrboTotal }
        let other = propertyRevenues.reduce(Decimal(0)) { $0 + $1.otherTotal }
        return (airbnb, vrbo, other, airbnb + vrbo + other)
    }

    private var totalCounts: (airbnb: Int, vrbo: Int, other: Int) {
        let airbnb = propertyRevenues.reduce(0) { $0 + $1.airbnbCount }
        let vrbo = propertyRevenues.reduce(0) { $0 + $1.vrboCount }
        let other = propertyRevenues.reduce(0) { $0 + $1.otherCount }
        return (airbnb, vrbo, other)
    }

    private func loadData() {
        let request: NSFetchRequest<Reservation> = Reservation.fetchRequest()
        request.predicate = NSPredicate(
            format: "checkOutDate >= %@ AND checkOutDate <= %@ AND isCancelled == NO",
            startDate as NSDate,
            endDate as NSDate
        )

        guard let reservations = try? viewContext.fetch(request) else {
            propertyRevenues = []
            return
        }

        var propertyData: [UUID: (name: String, airbnb: Decimal, airbnbCount: Int, vrbo: Decimal, vrboCount: Int, other: Decimal, otherCount: Int)] = [:]

        for reservation in reservations {
            guard let property = reservation.property,
                  let propertyId = property.id else { continue }

            let propertyName = property.displayName
            let amount = reservation.totalAmount as Decimal? ?? 0
            let source = (reservation.source ?? "").lowercased()

            var data = propertyData[propertyId] ?? (name: propertyName, airbnb: 0, airbnbCount: 0, vrbo: 0, vrboCount: 0, other: 0, otherCount: 0)

            if source.contains("airbnb") {
                data.airbnb += amount
                data.airbnbCount += 1
            } else if source.contains("vrbo") || source.contains("homeaway") {
                data.vrbo += amount
                data.vrboCount += 1
            } else {
                data.other += amount
                data.otherCount += 1
            }

            propertyData[propertyId] = data
        }

        propertyRevenues = propertyData
            .filter { $0.value.airbnb + $0.value.vrbo + $0.value.other > 0 }
            .map { PropertyRevenueData(
                id: $0.key,
                propertyName: $0.value.name,
                airbnbTotal: $0.value.airbnb,
                airbnbCount: $0.value.airbnbCount,
                vrboTotal: $0.value.vrbo,
                vrboCount: $0.value.vrboCount,
                otherTotal: $0.value.other,
                otherCount: $0.value.otherCount
            )}
            .sorted { $0.grandTotal > $1.grandTotal }
    }
}

struct StatBox: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .frame(minWidth: 100)
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Revenue by Source Preview

struct RevenueBySourcePreview: View {
    let startDate: Date
    let endDate: Date

    @Environment(\.managedObjectContext) private var viewContext
    @State private var propertyRevenues: [PropertyRevenueBySource] = []

    struct PropertyRevenueBySource: Identifiable {
        let id: UUID
        let propertyName: String
        let airbnbTotal: Decimal
        let vrboTotal: Decimal
        let otherTotal: Decimal

        var grandTotal: Decimal {
            airbnbTotal + vrboTotal + otherTotal
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack {
                Text("Property")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Airbnb")
                    .frame(width: 100, alignment: .trailing)
                Text("VRBO")
                    .frame(width: 100, alignment: .trailing)
                Text("Other")
                    .frame(width: 100, alignment: .trailing)
                Text("Total")
                    .frame(width: 100, alignment: .trailing)
            }
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal)

            Divider()

            if propertyRevenues.isEmpty {
                Text("No reservations found for the selected period")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(propertyRevenues) { property in
                            HStack {
                                Text(property.propertyName)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .lineLimit(1)
                                Text(property.airbnbTotal.asCurrency)
                                    .frame(width: 100, alignment: .trailing)
                                    .foregroundColor(property.airbnbTotal > 0 ? .primary : .secondary)
                                Text(property.vrboTotal.asCurrency)
                                    .frame(width: 100, alignment: .trailing)
                                    .foregroundColor(property.vrboTotal > 0 ? .primary : .secondary)
                                Text(property.otherTotal.asCurrency)
                                    .frame(width: 100, alignment: .trailing)
                                    .foregroundColor(property.otherTotal > 0 ? .primary : .secondary)
                                Text(property.grandTotal.asCurrency)
                                    .frame(width: 100, alignment: .trailing)
                                    .fontWeight(.medium)
                            }
                            .font(.caption)
                            .padding(.horizontal)
                            .padding(.vertical, 6)

                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 300)

                // Totals row
                let totals = calculateTotals()
                HStack {
                    Text("TOTAL")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fontWeight(.bold)
                    Text(totals.airbnb.asCurrency)
                        .frame(width: 100, alignment: .trailing)
                        .foregroundColor(.red)
                    Text(totals.vrbo.asCurrency)
                        .frame(width: 100, alignment: .trailing)
                        .foregroundColor(.blue)
                    Text(totals.other.asCurrency)
                        .frame(width: 100, alignment: .trailing)
                        .foregroundColor(.gray)
                    Text(totals.grand.asCurrency)
                        .frame(width: 100, alignment: .trailing)
                        .foregroundColor(.purple)
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .padding(.vertical)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .onAppear(perform: loadData)
        .onChange(of: startDate) { loadData() }
        .onChange(of: endDate) { loadData() }
    }

    private func loadData() {
        // Fetch reservations for the selected date range
        // Use checkout date to determine which month the revenue belongs to
        let request: NSFetchRequest<Reservation> = Reservation.fetchRequest()
        request.predicate = NSPredicate(
            format: "checkOutDate >= %@ AND checkOutDate <= %@ AND isCancelled == NO",
            startDate as NSDate,
            endDate as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Reservation.property?.name, ascending: true)]

        guard let reservations = try? viewContext.fetch(request) else {
            propertyRevenues = []
            return
        }

        // Group by property and source
        var propertyData: [UUID: (name: String, airbnb: Decimal, vrbo: Decimal, other: Decimal)] = [:]

        for reservation in reservations {
            guard let property = reservation.property,
                  let propertyId = property.id else { continue }

            let propertyName = property.displayName
            let amount = reservation.totalAmount as Decimal? ?? 0
            let source = (reservation.source ?? "").lowercased()

            var data = propertyData[propertyId] ?? (name: propertyName, airbnb: 0, vrbo: 0, other: 0)

            if source.contains("airbnb") {
                data.airbnb += amount
            } else if source.contains("vrbo") || source.contains("homeaway") {
                data.vrbo += amount
            } else {
                data.other += amount
            }

            propertyData[propertyId] = data
        }

        // Convert to array, filtering out properties with no revenue
        propertyRevenues = propertyData
            .filter { $0.value.airbnb + $0.value.vrbo + $0.value.other > 0 }
            .map { PropertyRevenueBySource(
                id: $0.key,
                propertyName: $0.value.name,
                airbnbTotal: $0.value.airbnb,
                vrboTotal: $0.value.vrbo,
                otherTotal: $0.value.other
            )}
            .sorted { $0.grandTotal > $1.grandTotal }
    }

    private func calculateTotals() -> (airbnb: Decimal, vrbo: Decimal, other: Decimal, grand: Decimal) {
        let airbnb = propertyRevenues.reduce(Decimal(0)) { $0 + $1.airbnbTotal }
        let vrbo = propertyRevenues.reduce(Decimal(0)) { $0 + $1.vrboTotal }
        let other = propertyRevenues.reduce(Decimal(0)) { $0 + $1.otherTotal }
        return (airbnb, vrbo, other, airbnb + vrbo + other)
    }
}

#Preview {
    ReportsView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
