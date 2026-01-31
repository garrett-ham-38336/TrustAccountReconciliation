import Foundation
import CoreData

/// Service for calculating expected trust account balance
/// Formula: Expected = Future Deposits - Stripe Holdback + Unpaid Payouts + Unpaid Taxes
class TrustCalculationService {
    static let shared = TrustCalculationService()

    private var _context: NSManagedObjectContext?
    var context: NSManagedObjectContext {
        _context ?? PersistenceController.shared.container.viewContext
    }

    private init() {}

    init(context: NSManagedObjectContext) {
        self._context = context
    }

    /// Quick calculation result for reports (without bank/stripe values)
    struct QuickCalculation {
        var futureDeposits: Decimal
        var unpaidOwnerPayouts: Decimal
        var unpaidTaxAmount: Decimal
        var expectedBalance: Decimal

        var futureReservations: [ReservationSummary]
        var ownerPayouts: [OwnerPayoutSummary]
        var unpaidTaxes: [TaxSummary]
    }

    /// Calculates expected balance using default context (for quick reports)
    func calculateExpectedBalance(context: NSManagedObjectContext) -> QuickCalculation {
        let service = TrustCalculationService(context: context)

        // Get future reservations with deposits
        let futureRes = service.fetchFutureReservationsWithDeposits()
        let futureDeposits = futureRes.reduce(Decimal(0)) { $0 + $1.depositAmount }

        // Get owner payout breakdown
        let ownerPayouts = service.getOwnerPayoutBreakdown()
        let unpaidOwnerPayouts = ownerPayouts.reduce(Decimal(0)) { $0 + $1.totalUnpaid }

        // Get tax breakdown
        let taxBreakdown = service.getTaxBreakdown()
        let unpaidTaxAmount = taxBreakdown.reduce(Decimal(0)) { $0 + $1.totalUnpaid }

        return QuickCalculation(
            futureDeposits: futureDeposits,
            unpaidOwnerPayouts: unpaidOwnerPayouts,
            unpaidTaxAmount: unpaidTaxAmount,
            expectedBalance: futureDeposits + unpaidOwnerPayouts + unpaidTaxAmount,
            futureReservations: futureRes,
            ownerPayouts: ownerPayouts,
            unpaidTaxes: taxBreakdown
        )
    }

    // MARK: - Data Structures

    struct TrustCalculation {
        var calculationDate: Date
        var bankBalance: Decimal
        var stripeHoldback: Decimal

        // Calculated components
        var futureDeposits: Decimal
        var unpaidOwnerPayouts: Decimal
        var unpaidTaxes: Decimal
        var maintenanceReserves: Decimal

        // Counts
        var futureReservationCount: Int
        var unpaidPayoutReservationCount: Int
        var unpaidTaxReservationCount: Int

        // Drill-down data
        var futureReservations: [ReservationSummary]
        var unpaidPayoutReservations: [ReservationSummary]
        var unpaidTaxReservations: [ReservationSummary]

        // Three-way reconciliation: Owner-level breakdown
        var ownerPayoutBreakdown: [OwnerPayoutSummary]

        /// Expected trust balance: Future Deposits - Stripe Holdback + Unpaid Payouts + Unpaid Taxes + Maintenance Reserves
        var expectedBalance: Decimal {
            futureDeposits - stripeHoldback + unpaidOwnerPayouts + unpaidTaxes + maintenanceReserves
        }

        /// Actual funds available: Bank Balance + Stripe Holdback
        var actualBalance: Decimal {
            bankBalance + stripeHoldback
        }

        /// Sum of all owner balances (from owner-level breakdown)
        var totalOwnerBalances: Decimal {
            ownerPayoutBreakdown.reduce(Decimal(0)) { $0 + $1.totalUnpaid }
        }

        /// Variance between expected and actual
        var variance: Decimal {
            actualBalance - expectedBalance
        }

        /// Variance between ledger owner payouts and owner-level sum
        /// Should be zero if all data is consistent
        var ownerReconciliationVariance: Decimal {
            unpaidOwnerPayouts - totalOwnerBalances
        }

        /// Whether the account is balanced (within tolerance)
        var isBalanced: Bool {
            abs(variance) < 1.00  // $1 tolerance for rounding
        }

        /// Whether all three balances reconcile
        var isThreeWayBalanced: Bool {
            isBalanced && abs(ownerReconciliationVariance) < 1.00
        }

        /// Formatted summary for display
        var summaryText: String {
            """
            Expected Trust Balance Calculation:

            Future Reservation Deposits: \(futureDeposits.asCurrency)
            - Stripe Holdback: \(stripeHoldback.asCurrency)
            + Unpaid Owner Payouts: \(unpaidOwnerPayouts.asCurrency)
            + Unpaid Taxes: \(unpaidTaxes.asCurrency)
            + Maintenance Reserves: \(maintenanceReserves.asCurrency)
            ─────────────────────────
            Expected Balance: \(expectedBalance.asCurrency)

            Actual Balance (Bank + Stripe): \(actualBalance.asCurrency)

            Variance: \(variance.asCurrency)
            """
        }

        /// Three-way reconciliation summary
        var threeWaySummaryText: String {
            """
            Three-Way Reconciliation:

            1. Bank Balance: \(bankBalance.asCurrency)
               + Stripe Holdback: \(stripeHoldback.asCurrency)
               = Total Cash: \(actualBalance.asCurrency)

            2. Ledger Balance (Expected): \(expectedBalance.asCurrency)
               Variance from Cash: \(variance.asCurrency)

            3. Owner Balances Total: \(totalOwnerBalances.asCurrency)
               (\(ownerPayoutBreakdown.count) owners with unpaid balances)
               Variance from Ledger: \(ownerReconciliationVariance.asCurrency)

            Status: \(isThreeWayBalanced ? "✓ BALANCED" : "⚠ VARIANCE DETECTED")
            """
        }
    }

    struct ReservationSummary: Identifiable, Codable {
        var id: UUID
        var guestyId: String?
        var confirmationCode: String
        var guestName: String
        var propertyName: String
        var ownerName: String
        var checkInDate: Date
        var checkOutDate: Date
        var depositAmount: Decimal
        var ownerPayout: Decimal
        var taxAmount: Decimal
        var totalAmount: Decimal
    }

    struct OwnerPayoutSummary: Identifiable {
        var id: UUID { ownerId }
        var ownerId: UUID
        var ownerName: String
        var totalUnpaid: Decimal
        var reservationCount: Int
        var lastPayoutDate: Date?
        var reservations: [ReservationSummary]
    }

    struct TaxSummary: Identifiable {
        var id: UUID { jurisdictionId }
        var jurisdictionId: UUID
        var jurisdictionName: String
        var totalUnpaid: Decimal
        var reservationCount: Int
        var lastRemittanceDate: Date?
    }

    // MARK: - Calculate Expected Balance

    /// Performs the full trust balance calculation with three-way reconciliation
    func calculateExpectedBalance(
        bankBalance: Decimal,
        stripeHoldback: Decimal
    ) -> TrustCalculation {
        // 1. Get future reservations with deposits
        let futureRes = fetchFutureReservationsWithDeposits()
        let futureDeposits = futureRes.reduce(Decimal(0)) { $0 + $1.depositAmount }

        // 2. Get completed reservations with unpaid owner payouts
        let unpaidPayoutRes = fetchUnpaidOwnerPayouts()
        let unpaidPayouts = unpaidPayoutRes.reduce(Decimal(0)) { $0 + $1.ownerPayout }

        // 3. Get completed reservations with unremitted taxes
        let unpaidTaxRes = fetchUnremittedTaxReservations()
        let unpaidTaxes = unpaidTaxRes.reduce(Decimal(0)) { $0 + $1.taxAmount }

        // 4. Get maintenance reserves from settings
        let maintenanceReserves = fetchMaintenanceReserves()

        // 5. Get owner-level breakdown for three-way reconciliation
        let ownerBreakdown = getOwnerPayoutBreakdown()

        return TrustCalculation(
            calculationDate: Date(),
            bankBalance: bankBalance,
            stripeHoldback: stripeHoldback,
            futureDeposits: futureDeposits,
            unpaidOwnerPayouts: unpaidPayouts,
            unpaidTaxes: unpaidTaxes,
            maintenanceReserves: maintenanceReserves,
            futureReservationCount: futureRes.count,
            unpaidPayoutReservationCount: unpaidPayoutRes.count,
            unpaidTaxReservationCount: unpaidTaxRes.count,
            futureReservations: futureRes,
            unpaidPayoutReservations: unpaidPayoutRes,
            unpaidTaxReservations: unpaidTaxRes,
            ownerPayoutBreakdown: ownerBreakdown
        )
    }

    /// Fetches maintenance reserves from AppSettings
    private func fetchMaintenanceReserves() -> Decimal {
        let request: NSFetchRequest<AppSettings> = AppSettings.fetchRequest()
        request.fetchLimit = 1
        guard let settings = try? context.fetch(request).first else { return 0 }
        return settings.maintenanceReserves as Decimal? ?? 0
    }

    // MARK: - Fetch Methods

    private func fetchFutureReservationsWithDeposits() -> [ReservationSummary] {
        let request = Reservation.futureReservationsWithDeposits()
        guard let reservations = try? context.fetch(request) else { return [] }

        return reservations.map { res in
            ReservationSummary(
                id: res.id ?? UUID(),
                guestyId: res.guestyReservationId,
                confirmationCode: res.confirmationCode ?? "N/A",
                guestName: res.guestName ?? "Unknown",
                propertyName: res.property?.displayName ?? "Unknown",
                ownerName: res.property?.owner?.displayName ?? "Unknown",
                checkInDate: res.checkInDate ?? Date(),
                checkOutDate: res.checkOutDate ?? Date(),
                depositAmount: res.depositReceived as Decimal? ?? 0,
                ownerPayout: res.ownerPayout as Decimal? ?? 0,
                taxAmount: res.taxAmount as Decimal? ?? 0,
                totalAmount: res.totalAmount as Decimal? ?? 0
            )
        }
    }

    private func fetchUnpaidOwnerPayouts() -> [ReservationSummary] {
        // Get the earliest last payout date across all owners
        let ownerRequest: NSFetchRequest<Owner> = Owner.fetchRequest()
        ownerRequest.predicate = NSPredicate(format: "isActive == YES")
        let owners = (try? context.fetch(ownerRequest)) ?? []

        var allUnpaid: [ReservationSummary] = []

        for owner in owners {
            let reservationRequest = Reservation.completedUnpaidPayouts(since: owner.lastPayoutDate)
            reservationRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                reservationRequest.predicate!,
                NSPredicate(format: "property.owner == %@", owner)
            ])

            guard let reservations = try? context.fetch(reservationRequest) else { continue }

            let summaries = reservations.map { res in
                ReservationSummary(
                    id: res.id ?? UUID(),
                    guestyId: res.guestyReservationId,
                    confirmationCode: res.confirmationCode ?? "N/A",
                    guestName: res.guestName ?? "Unknown",
                    propertyName: res.property?.displayName ?? "Unknown",
                    ownerName: owner.displayName,
                    checkInDate: res.checkInDate ?? Date(),
                    checkOutDate: res.checkOutDate ?? Date(),
                    depositAmount: res.depositReceived as Decimal? ?? 0,
                    ownerPayout: res.ownerPayout as Decimal? ?? 0,
                    taxAmount: res.taxAmount as Decimal? ?? 0,
                    totalAmount: res.totalAmount as Decimal? ?? 0
                )
            }
            allUnpaid.append(contentsOf: summaries)
        }

        return allUnpaid.sorted { $0.checkOutDate < $1.checkOutDate }
    }

    private func fetchUnremittedTaxReservations() -> [ReservationSummary] {
        // For simplicity, use global last tax remittance or nil
        // In a more complex setup, this would be per-jurisdiction
        let request = Reservation.completedUnremittedTaxes(since: nil)
        guard let reservations = try? context.fetch(request) else { return [] }

        return reservations.map { res in
            ReservationSummary(
                id: res.id ?? UUID(),
                guestyId: res.guestyReservationId,
                confirmationCode: res.confirmationCode ?? "N/A",
                guestName: res.guestName ?? "Unknown",
                propertyName: res.property?.displayName ?? "Unknown",
                ownerName: res.property?.owner?.displayName ?? "Unknown",
                checkInDate: res.checkInDate ?? Date(),
                checkOutDate: res.checkOutDate ?? Date(),
                depositAmount: res.depositReceived as Decimal? ?? 0,
                ownerPayout: res.ownerPayout as Decimal? ?? 0,
                taxAmount: res.taxAmount as Decimal? ?? 0,
                totalAmount: res.totalAmount as Decimal? ?? 0
            )
        }
    }

    // MARK: - Owner Payout Breakdown

    func getOwnerPayoutBreakdown() -> [OwnerPayoutSummary] {
        let ownerRequest: NSFetchRequest<Owner> = Owner.fetchRequest()
        ownerRequest.predicate = NSPredicate(format: "isActive == YES")
        ownerRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Owner.name, ascending: true)]
        guard let owners = try? context.fetch(ownerRequest) else { return [] }

        return owners.compactMap { owner in
            let reservationRequest = Reservation.completedUnpaidPayouts(since: owner.lastPayoutDate)
            reservationRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                reservationRequest.predicate!,
                NSPredicate(format: "property.owner == %@", owner)
            ])

            guard let reservations = try? context.fetch(reservationRequest), !reservations.isEmpty else {
                return nil
            }

            let summaries = reservations.map { res in
                ReservationSummary(
                    id: res.id ?? UUID(),
                    guestyId: res.guestyReservationId,
                    confirmationCode: res.confirmationCode ?? "N/A",
                    guestName: res.guestName ?? "Unknown",
                    propertyName: res.property?.displayName ?? "Unknown",
                    ownerName: owner.displayName,
                    checkInDate: res.checkInDate ?? Date(),
                    checkOutDate: res.checkOutDate ?? Date(),
                    depositAmount: res.depositReceived as Decimal? ?? 0,
                    ownerPayout: res.ownerPayout as Decimal? ?? 0,
                    taxAmount: res.taxAmount as Decimal? ?? 0,
                    totalAmount: res.totalAmount as Decimal? ?? 0
                )
            }

            let totalUnpaid = summaries.reduce(Decimal(0)) { $0 + $1.ownerPayout }

            return OwnerPayoutSummary(
                ownerId: owner.id ?? UUID(),
                ownerName: owner.displayName,
                totalUnpaid: totalUnpaid,
                reservationCount: summaries.count,
                lastPayoutDate: owner.lastPayoutDate,
                reservations: summaries
            )
        }
    }

    // MARK: - Tax Breakdown

    func getTaxBreakdown() -> [TaxSummary] {
        let jurisdictionRequest: NSFetchRequest<TaxJurisdiction> = TaxJurisdiction.fetchRequest()
        jurisdictionRequest.predicate = NSPredicate(format: "isActive == YES")
        jurisdictionRequest.sortDescriptors = [NSSortDescriptor(keyPath: \TaxJurisdiction.name, ascending: true)]
        guard let jurisdictions = try? context.fetch(jurisdictionRequest) else { return [] }

        return jurisdictions.compactMap { jurisdiction in
            // Get properties in this jurisdiction
            guard let properties = jurisdiction.properties as? Set<Property>, !properties.isEmpty else {
                return nil
            }

            var totalUnpaid: Decimal = 0
            var reservationCount = 0

            for property in properties {
                guard let reservations = property.reservations as? Set<Reservation> else { continue }

                let unpaid = reservations.filter { res in
                    guard let checkOut = res.checkOutDate else { return false }
                    return checkOut <= Date() &&
                           !res.isCancelled &&
                           !res.taxRemitted &&
                           (res.taxAmount as Decimal? ?? 0) > 0
                }

                totalUnpaid += unpaid.reduce(Decimal(0)) { $0 + ($1.taxAmount as Decimal? ?? 0) }
                reservationCount += unpaid.count
            }

            guard totalUnpaid > 0 else { return nil }

            return TaxSummary(
                jurisdictionId: jurisdiction.id ?? UUID(),
                jurisdictionName: jurisdiction.name ?? "Unknown",
                totalUnpaid: totalUnpaid,
                reservationCount: reservationCount,
                lastRemittanceDate: jurisdiction.lastRemittanceDate
            )
        }
    }

    // MARK: - Save Reconciliation Snapshot

    func saveReconciliation(_ calculation: TrustCalculation, notes: String? = nil) throws -> ReconciliationSnapshot {
        let snapshot = ReconciliationSnapshot(context: context)
        snapshot.id = UUID()
        snapshot.reconciliationDate = calculation.calculationDate
        snapshot.bankBalance = calculation.bankBalance as NSDecimalNumber
        snapshot.stripeHoldback = calculation.stripeHoldback as NSDecimalNumber
        snapshot.futureDeposits = calculation.futureDeposits as NSDecimalNumber
        snapshot.unpaidOwnerPayouts = calculation.unpaidOwnerPayouts as NSDecimalNumber
        snapshot.unpaidTaxes = calculation.unpaidTaxes as NSDecimalNumber
        snapshot.maintenanceReserves = calculation.maintenanceReserves as NSDecimalNumber
        snapshot.expectedBalance = calculation.expectedBalance as NSDecimalNumber
        snapshot.actualBalance = calculation.actualBalance as NSDecimalNumber
        snapshot.variance = calculation.variance as NSDecimalNumber
        snapshot.futureReservationCount = Int32(calculation.futureReservationCount)
        snapshot.unpaidPayoutCount = Int32(calculation.unpaidPayoutReservationCount)
        snapshot.unpaidTaxReservationCount = Int32(calculation.unpaidTaxReservationCount)
        snapshot.isBalanced = calculation.isBalanced
        snapshot.status = calculation.isBalanced ? "balanced" : "variance"
        snapshot.notes = notes
        snapshot.createdAt = Date()

        // Store drill-down data as JSON
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        snapshot.futureReservationsData = try? encoder.encode(calculation.futureReservations)
        snapshot.unpaidPayoutsData = try? encoder.encode(calculation.unpaidPayoutReservations)
        snapshot.unpaidTaxesData = try? encoder.encode(calculation.unpaidTaxReservations)

        try context.save()
        return snapshot
    }

    // MARK: - Variance Analysis

    struct VarianceReason {
        var description: String
        var amount: Decimal
        var category: String
    }

    func analyzeVariance(_ calculation: TrustCalculation) -> [VarianceReason] {
        var reasons: [VarianceReason] = []
        let variance = calculation.variance

        if abs(variance) < 1 {
            return []  // No significant variance
        }

        // Common reasons for variance
        if variance > 0 {
            // More money than expected - possible reasons:
            reasons.append(VarianceReason(
                description: "Deposits received but reservation not yet in system",
                amount: variance,
                category: "timing"
            ))
            reasons.append(VarianceReason(
                description: "Manual deposit or transfer not reflected in reservations",
                amount: variance,
                category: "manual"
            ))
        } else {
            // Less money than expected - possible reasons:
            reasons.append(VarianceReason(
                description: "Payment pending in Stripe not yet deposited",
                amount: abs(variance),
                category: "timing"
            ))
            reasons.append(VarianceReason(
                description: "Refund or chargeback processed",
                amount: abs(variance),
                category: "adjustment"
            ))
            reasons.append(VarianceReason(
                description: "Payout or tax payment made but not recorded",
                amount: abs(variance),
                category: "recording"
            ))
        }

        return reasons
    }
}

