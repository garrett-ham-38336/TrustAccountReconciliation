import Foundation
import AppKit
import CoreData
import PDFKit

/// Service for generating PDF reports
class PDFExportService {
    static let shared = PDFExportService()

    private let pageWidth: CGFloat = 612  // Letter size
    private let pageHeight: CGFloat = 792
    private let margin: CGFloat = 50

    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private lazy var currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter
    }()

    private init() {}

    // MARK: - Reconciliation Report

    /// Generates a PDF report for a reconciliation snapshot
    func generateReconciliationReport(_ reconciliation: ReconciliationSnapshot) -> Data? {
        let pdfData = NSMutableData()

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            return nil
        }

        var pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        var yPosition: CGFloat = pageHeight - margin

        // Start first page
        context.beginPDFPage(nil)

        // Draw header
        yPosition = drawHeader(context: context, y: yPosition, title: "Trust Account Reconciliation Report")

        // Draw date
        let dateText = "Reconciliation Date: \(dateFormatter.string(from: reconciliation.reconciliationDate ?? Date()))"
        yPosition = drawText(context: context, text: dateText, y: yPosition, fontSize: 12, color: .gray)
        yPosition -= 20

        // Draw status
        let statusText = reconciliation.isBalanced ? "Status: BALANCED" : "Status: VARIANCE DETECTED"
        let statusColor: NSColor = reconciliation.isBalanced ? .systemGreen : .systemOrange
        yPosition = drawText(context: context, text: statusText, y: yPosition, fontSize: 14, bold: true, color: statusColor)
        yPosition -= 30

        // Draw summary section
        yPosition = drawSectionHeader(context: context, y: yPosition, title: "Summary")
        yPosition = drawKeyValue(context: context, y: yPosition, key: "Expected Balance", value: formatCurrency(reconciliation.expectedBalance as Decimal? ?? 0))
        yPosition = drawKeyValue(context: context, y: yPosition, key: "Actual Balance", value: formatCurrency(reconciliation.actualBalance as Decimal? ?? 0))
        yPosition = drawKeyValue(context: context, y: yPosition, key: "Variance", value: formatCurrency(reconciliation.variance as Decimal? ?? 0), valueColor: reconciliation.isBalanced ? .black : .systemRed)
        yPosition -= 20

        // Draw calculation breakdown
        yPosition = drawSectionHeader(context: context, y: yPosition, title: "Calculation Breakdown")
        yPosition = drawKeyValue(context: context, y: yPosition, key: "Future Deposits (\(reconciliation.futureReservationCount) reservations)", value: formatCurrency(reconciliation.futureDeposits as Decimal? ?? 0))
        yPosition = drawKeyValue(context: context, y: yPosition, key: "Less: Stripe Holdback", value: formatCurrency(reconciliation.stripeHoldback as Decimal? ?? 0))
        yPosition = drawKeyValue(context: context, y: yPosition, key: "Plus: Unpaid Owner Payouts (\(reconciliation.unpaidPayoutCount) reservations)", value: formatCurrency(reconciliation.unpaidOwnerPayouts as Decimal? ?? 0))
        yPosition = drawKeyValue(context: context, y: yPosition, key: "Plus: Unpaid Taxes (\(reconciliation.unpaidTaxReservationCount) reservations)", value: formatCurrency(reconciliation.unpaidTaxes as Decimal? ?? 0))
        yPosition = drawKeyValue(context: context, y: yPosition, key: "Plus: Maintenance Reserves", value: formatCurrency(reconciliation.maintenanceReserves as Decimal? ?? 0))

        // Draw line
        yPosition -= 10
        drawLine(context: context, y: yPosition)
        yPosition -= 20

        yPosition = drawKeyValue(context: context, y: yPosition, key: "Expected Trust Balance", value: formatCurrency(reconciliation.expectedBalance as Decimal? ?? 0), bold: true)
        yPosition -= 30

        // Draw actual balance breakdown
        yPosition = drawSectionHeader(context: context, y: yPosition, title: "Actual Balance")
        yPosition = drawKeyValue(context: context, y: yPosition, key: "Bank Balance", value: formatCurrency(reconciliation.bankBalance as Decimal? ?? 0))
        yPosition = drawKeyValue(context: context, y: yPosition, key: "Plus: Stripe Holdback", value: formatCurrency(reconciliation.stripeHoldback as Decimal? ?? 0))
        drawLine(context: context, y: yPosition - 5)
        yPosition -= 15
        yPosition = drawKeyValue(context: context, y: yPosition, key: "Total Actual Balance", value: formatCurrency(reconciliation.actualBalance as Decimal? ?? 0), bold: true)

        // Notes if present
        if let notes = reconciliation.notes, !notes.isEmpty {
            yPosition -= 30
            yPosition = drawSectionHeader(context: context, y: yPosition, title: "Notes")
            yPosition = drawText(context: context, text: notes, y: yPosition, fontSize: 11)
        }

        // Draw footer
        drawFooter(context: context, pageNumber: 1)

        context.endPDFPage()
        context.closePDF()

        return pdfData as Data
    }

    // MARK: - Owner Payout Statement

    /// Generates a payout statement PDF for an owner
    func generateOwnerPayoutStatement(
        owner: Owner,
        reservations: [Reservation],
        periodStart: Date,
        periodEnd: Date
    ) -> Data? {
        let pdfData = NSMutableData()

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            return nil
        }

        var yPosition: CGFloat = pageHeight - margin
        var pageNumber = 1

        // Start first page
        context.beginPDFPage(nil)

        // Draw header
        yPosition = drawHeader(context: context, y: yPosition, title: "Owner Payout Statement")

        // Owner info
        yPosition = drawText(context: context, text: owner.name ?? "Unknown Owner", y: yPosition, fontSize: 14, bold: true)
        if let email = owner.email {
            yPosition = drawText(context: context, text: email, y: yPosition, fontSize: 11, color: .gray)
        }
        yPosition -= 10

        // Period
        let periodText = "Period: \(dateFormatter.string(from: periodStart)) - \(dateFormatter.string(from: periodEnd))"
        yPosition = drawText(context: context, text: periodText, y: yPosition, fontSize: 12)
        yPosition -= 20

        // Calculate totals
        let totalRevenue = reservations.reduce(Decimal(0)) { $0 + ($1.totalAmount as Decimal? ?? 0) }
        let totalManagementFees = reservations.reduce(Decimal(0)) { $0 + ($1.managementFee as Decimal? ?? 0) }
        let totalPayout = reservations.reduce(Decimal(0)) { $0 + ($1.ownerPayout as Decimal? ?? 0) }

        // Summary
        yPosition = drawSectionHeader(context: context, y: yPosition, title: "Summary")
        yPosition = drawKeyValue(context: context, y: yPosition, key: "Total Reservations", value: "\(reservations.count)")
        yPosition = drawKeyValue(context: context, y: yPosition, key: "Total Revenue", value: formatCurrency(totalRevenue))
        yPosition = drawKeyValue(context: context, y: yPosition, key: "Management Fees (\(owner.managementFeePercent ?? 20)%)", value: formatCurrency(totalManagementFees))
        drawLine(context: context, y: yPosition - 5)
        yPosition -= 15
        yPosition = drawKeyValue(context: context, y: yPosition, key: "Net Payout", value: formatCurrency(totalPayout), bold: true, valueColor: .systemGreen)
        yPosition -= 30

        // Reservations table
        yPosition = drawSectionHeader(context: context, y: yPosition, title: "Reservation Details")

        // Table header
        yPosition = drawTableHeader(context: context, y: yPosition, columns: [
            ("Guest", 120),
            ("Property", 120),
            ("Dates", 100),
            ("Revenue", 70),
            ("Fee", 60),
            ("Payout", 70)
        ])

        // Table rows
        for reservation in reservations {
            if yPosition < margin + 100 {
                // New page
                drawFooter(context: context, pageNumber: pageNumber)
                context.endPDFPage()
                pageNumber += 1
                context.beginPDFPage(nil)
                yPosition = pageHeight - margin
                yPosition = drawTableHeader(context: context, y: yPosition, columns: [
                    ("Guest", 120),
                    ("Property", 120),
                    ("Dates", 100),
                    ("Revenue", 70),
                    ("Fee", 60),
                    ("Payout", 70)
                ])
            }

            let dateRange = formatDateRange(reservation.checkInDate, reservation.checkOutDate)
            yPosition = drawTableRow(context: context, y: yPosition, values: [
                (reservation.guestName ?? "Unknown", 120),
                (reservation.property?.name ?? "Unknown", 120),
                (dateRange, 100),
                (formatCurrency(reservation.totalAmount as Decimal? ?? 0), 70),
                (formatCurrency(reservation.managementFee as Decimal? ?? 0), 60),
                (formatCurrency(reservation.ownerPayout as Decimal? ?? 0), 70)
            ])
        }

        drawFooter(context: context, pageNumber: pageNumber)
        context.endPDFPage()
        context.closePDF()

        return pdfData as Data
    }

    // MARK: - Tax Report

    /// Generates a tax summary PDF report
    func generateTaxReport(
        reservations: [Reservation],
        periodStart: Date,
        periodEnd: Date
    ) -> Data? {
        let pdfData = NSMutableData()

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            return nil
        }

        var yPosition: CGFloat = pageHeight - margin

        context.beginPDFPage(nil)

        // Header
        yPosition = drawHeader(context: context, y: yPosition, title: "Tax Collection Report")

        // Period
        let periodText = "Period: \(dateFormatter.string(from: periodStart)) - \(dateFormatter.string(from: periodEnd))"
        yPosition = drawText(context: context, text: periodText, y: yPosition, fontSize: 12)
        yPosition -= 20

        // Calculate totals
        let totalTax = reservations.reduce(Decimal(0)) { $0 + ($1.taxAmount as Decimal? ?? 0) }
        let remittedTax = reservations.filter { $0.taxRemitted }.reduce(Decimal(0)) { $0 + ($1.taxAmount as Decimal? ?? 0) }
        let unremittedTax = totalTax - remittedTax

        // Summary
        yPosition = drawSectionHeader(context: context, y: yPosition, title: "Summary")
        yPosition = drawKeyValue(context: context, y: yPosition, key: "Total Reservations", value: "\(reservations.count)")
        yPosition = drawKeyValue(context: context, y: yPosition, key: "Total Tax Collected", value: formatCurrency(totalTax))
        yPosition = drawKeyValue(context: context, y: yPosition, key: "Tax Remitted", value: formatCurrency(remittedTax), valueColor: .systemGreen)
        yPosition = drawKeyValue(context: context, y: yPosition, key: "Tax Outstanding", value: formatCurrency(unremittedTax), valueColor: unremittedTax > 0 ? .systemOrange : .black)
        yPosition -= 30

        // By month breakdown
        let grouped = Dictionary(grouping: reservations) { reservation -> String in
            guard let date = reservation.checkOutDate else { return "Unknown" }
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: date)
        }

        yPosition = drawSectionHeader(context: context, y: yPosition, title: "By Month")

        for (month, monthReservations) in grouped.sorted(by: { $0.key < $1.key }) {
            let monthTax = monthReservations.reduce(Decimal(0)) { $0 + ($1.taxAmount as Decimal? ?? 0) }
            let monthRemitted = monthReservations.filter { $0.taxRemitted }.count == monthReservations.count
            let status = monthRemitted ? " (Remitted)" : " (Outstanding)"
            yPosition = drawKeyValue(context: context, y: yPosition, key: month + status, value: formatCurrency(monthTax))
        }

        drawFooter(context: context, pageNumber: 1)
        context.endPDFPage()
        context.closePDF()

        return pdfData as Data
    }

    // MARK: - Drawing Helpers

    private func drawHeader(context: CGContext, y: CGFloat, title: String) -> CGFloat {
        var yPos = y

        // Company name (if set)
        // TODO: Get from AppSettings

        // Title
        yPos = drawText(context: context, text: title, y: yPos, fontSize: 20, bold: true)

        // Horizontal line
        yPos -= 10
        drawLine(context: context, y: yPos)
        yPos -= 20

        return yPos
    }

    private func drawFooter(context: CGContext, pageNumber: Int) {
        let footerY: CGFloat = 30

        // Page number
        let pageText = "Page \(pageNumber)"
        drawText(context: context, text: pageText, y: footerY, fontSize: 10, color: .gray, centered: true)

        // Generated date
        let generatedText = "Generated: \(dateFormatter.string(from: Date()))"
        drawText(context: context, text: generatedText, y: footerY, fontSize: 10, color: .gray, rightAligned: true)
    }

    private func drawSectionHeader(context: CGContext, y: CGFloat, title: String) -> CGFloat {
        var yPos = y
        yPos = drawText(context: context, text: title, y: yPos, fontSize: 14, bold: true, color: .darkGray)
        yPos -= 5
        return yPos
    }

    @discardableResult
    private func drawText(
        context: CGContext,
        text: String,
        y: CGFloat,
        fontSize: CGFloat,
        bold: Bool = false,
        color: NSColor = .black,
        centered: Bool = false,
        rightAligned: Bool = false
    ) -> CGFloat {
        let font = bold ? NSFont.boldSystemFont(ofSize: fontSize) : NSFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()

        var xPos = margin
        if centered {
            xPos = (pageWidth - textSize.width) / 2
        } else if rightAligned {
            xPos = pageWidth - margin - textSize.width
        }

        context.saveGState()
        context.textMatrix = .identity

        let textRect = CGRect(x: xPos, y: y - textSize.height, width: textSize.width, height: textSize.height)
        attributedString.draw(in: textRect)

        context.restoreGState()

        return y - textSize.height - 5
    }

    private func drawKeyValue(
        context: CGContext,
        y: CGFloat,
        key: String,
        value: String,
        bold: Bool = false,
        valueColor: NSColor = .black
    ) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 11)
        let boldFont = NSFont.boldSystemFont(ofSize: 11)

        let keyAttributes: [NSAttributedString.Key: Any] = [
            .font: bold ? boldFont : font,
            .foregroundColor: NSColor.darkGray
        ]

        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: bold ? boldFont : font,
            .foregroundColor: valueColor
        ]

        let keyString = NSAttributedString(string: key, attributes: keyAttributes)
        let valueString = NSAttributedString(string: value, attributes: valueAttributes)

        let keyRect = CGRect(x: margin, y: y - 15, width: 300, height: 15)
        keyString.draw(in: keyRect)

        let valueRect = CGRect(x: pageWidth - margin - 100, y: y - 15, width: 100, height: 15)
        valueString.draw(in: valueRect)

        return y - 20
    }

    private func drawLine(context: CGContext, y: CGFloat) {
        context.setStrokeColor(NSColor.lightGray.cgColor)
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: margin, y: y))
        context.addLine(to: CGPoint(x: pageWidth - margin, y: y))
        context.strokePath()
    }

    private func drawTableHeader(context: CGContext, y: CGFloat, columns: [(String, CGFloat)]) -> CGFloat {
        let font = NSFont.boldSystemFont(ofSize: 10)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.darkGray
        ]

        var xPos = margin
        for (title, width) in columns {
            let string = NSAttributedString(string: title, attributes: attributes)
            let rect = CGRect(x: xPos, y: y - 12, width: width, height: 12)
            string.draw(in: rect)
            xPos += width
        }

        drawLine(context: context, y: y - 15)
        return y - 25
    }

    private func drawTableRow(context: CGContext, y: CGFloat, values: [(String, CGFloat)]) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 9)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]

        var xPos = margin
        for (value, width) in values {
            let truncated = value.count > 20 ? String(value.prefix(18)) + "..." : value
            let string = NSAttributedString(string: truncated, attributes: attributes)
            let rect = CGRect(x: xPos, y: y - 12, width: width, height: 12)
            string.draw(in: rect)
            xPos += width
        }

        return y - 18
    }

    // MARK: - Formatting Helpers

    private func formatCurrency(_ value: Decimal) -> String {
        currencyFormatter.string(from: value as NSDecimalNumber) ?? "$0.00"
    }

    private func formatDateRange(_ start: Date?, _ end: Date?) -> String {
        guard let start = start, let end = end else { return "N/A" }
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return "\(formatter.string(from: start))-\(formatter.string(from: end))"
    }

    // MARK: - Export

    /// Shows a save panel and exports PDF data
    func exportPDF(data: Data, suggestedName: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = suggestedName

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url)
                NSWorkspace.shared.open(url)
            } catch {
                DebugLogger.shared.logError(error, context: "PDF export")
            }
        }
    }
}
