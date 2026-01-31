import XCTest
import CoreData
@testable import TrustAccountReconciliation

final class TrustCalculationServiceTests: XCTestCase {

    var persistenceController: PersistenceController!
    var context: NSManagedObjectContext!
    var service: TrustCalculationService!

    override func setUpWithError() throws {
        persistenceController = PersistenceController(inMemory: true)
        context = persistenceController.container.viewContext
        service = TrustCalculationService(context: context)
    }

    override func tearDownWithError() throws {
        persistenceController = nil
        context = nil
        service = nil
    }

    // MARK: - Helper Methods

    private func createOwner(name: String, managementFeePercent: Decimal = 20) -> Owner {
        let owner = Owner(context: context)
        owner.id = UUID()
        owner.name = name
        owner.managementFeePercent = managementFeePercent as NSDecimalNumber
        owner.isActive = true
        owner.createdAt = Date()
        owner.updatedAt = Date()
        return owner
    }

    private func createProperty(name: String, owner: Owner?) -> Property {
        let property = Property(context: context)
        property.id = UUID()
        property.name = name
        property.owner = owner
        property.isActive = true
        property.createdAt = Date()
        property.updatedAt = Date()
        return property
    }

    private func createReservation(
        property: Property,
        checkIn: Date,
        checkOut: Date,
        totalAmount: Decimal,
        depositReceived: Decimal,
        taxAmount: Decimal = 0,
        isCancelled: Bool = false,
        ownerPaidOut: Bool = false,
        taxRemitted: Bool = false
    ) -> Reservation {
        let reservation = Reservation(context: context)
        reservation.id = UUID()
        reservation.guestName = "Test Guest"
        reservation.property = property
        reservation.checkInDate = checkIn
        reservation.checkOutDate = checkOut
        reservation.totalAmount = totalAmount as NSDecimalNumber
        reservation.depositReceived = depositReceived as NSDecimalNumber
        reservation.taxAmount = taxAmount as NSDecimalNumber
        reservation.isCancelled = isCancelled
        reservation.ownerPaidOut = ownerPaidOut
        reservation.taxRemitted = taxRemitted
        reservation.ownerPayout = reservation.calculateOwnerPayout() as NSDecimalNumber
        reservation.managementFee = reservation.calculateManagementFee() as NSDecimalNumber
        reservation.createdAt = Date()
        reservation.updatedAt = Date()
        return reservation
    }

    // MARK: - Future Deposits Tests

    func testCalculateExpectedBalance_FutureDeposits() throws {
        // Arrange
        let owner = createOwner(name: "Test Owner")
        let property = createProperty(name: "Test Property", owner: owner)

        let futureDate = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        let futureCheckOut = Calendar.current.date(byAdding: .day, value: 10, to: Date())!

        _ = createReservation(
            property: property,
            checkIn: futureDate,
            checkOut: futureCheckOut,
            totalAmount: 1000,
            depositReceived: 1000
        )

        try context.save()

        // Act
        let calculation = service.calculateExpectedBalance(
            bankBalance: 1000,
            stripeHoldback: 0
        )

        // Assert
        XCTAssertEqual(calculation.futureDeposits, 1000)
        XCTAssertEqual(calculation.futureReservationCount, 1)
    }

    func testCalculateExpectedBalance_ExcludesCancelledReservations() throws {
        // Arrange
        let owner = createOwner(name: "Test Owner")
        let property = createProperty(name: "Test Property", owner: owner)

        let futureDate = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        let futureCheckOut = Calendar.current.date(byAdding: .day, value: 10, to: Date())!

        _ = createReservation(
            property: property,
            checkIn: futureDate,
            checkOut: futureCheckOut,
            totalAmount: 1000,
            depositReceived: 1000,
            isCancelled: true
        )

        try context.save()

        // Act
        let calculation = service.calculateExpectedBalance(
            bankBalance: 0,
            stripeHoldback: 0
        )

        // Assert
        XCTAssertEqual(calculation.futureDeposits, 0)
        XCTAssertEqual(calculation.futureReservationCount, 0)
    }

    // MARK: - Unpaid Owner Payouts Tests

    func testCalculateExpectedBalance_UnpaidOwnerPayouts() throws {
        // Arrange
        let owner = createOwner(name: "Test Owner", managementFeePercent: 20)
        let property = createProperty(name: "Test Property", owner: owner)

        // Create a completed reservation (check-in in the past)
        let pastCheckIn = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let pastCheckOut = Calendar.current.date(byAdding: .day, value: -3, to: Date())!

        let reservation = createReservation(
            property: property,
            checkIn: pastCheckIn,
            checkOut: pastCheckOut,
            totalAmount: 1000,
            depositReceived: 1000,
            ownerPaidOut: false
        )

        try context.save()

        // Act
        let calculation = service.calculateExpectedBalance(
            bankBalance: 1000,
            stripeHoldback: 0
        )

        // Assert
        // Owner payout should be 80% of 1000 = 800 (20% management fee)
        XCTAssertEqual(calculation.unpaidOwnerPayouts, reservation.ownerPayout as Decimal? ?? 0)
        XCTAssertEqual(calculation.unpaidPayoutReservationCount, 1)
    }

    func testCalculateExpectedBalance_ExcludesPaidOutReservations() throws {
        // Arrange
        let owner = createOwner(name: "Test Owner")
        let property = createProperty(name: "Test Property", owner: owner)

        let pastCheckIn = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let pastCheckOut = Calendar.current.date(byAdding: .day, value: -3, to: Date())!

        _ = createReservation(
            property: property,
            checkIn: pastCheckIn,
            checkOut: pastCheckOut,
            totalAmount: 1000,
            depositReceived: 1000,
            ownerPaidOut: true  // Already paid out
        )

        try context.save()

        // Act
        let calculation = service.calculateExpectedBalance(
            bankBalance: 1000,
            stripeHoldback: 0
        )

        // Assert
        XCTAssertEqual(calculation.unpaidOwnerPayouts, 0)
        XCTAssertEqual(calculation.unpaidPayoutReservationCount, 0)
    }

    // MARK: - Unpaid Taxes Tests

    func testCalculateExpectedBalance_UnpaidTaxes() throws {
        // Arrange
        let owner = createOwner(name: "Test Owner")
        let property = createProperty(name: "Test Property", owner: owner)

        let pastCheckIn = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let pastCheckOut = Calendar.current.date(byAdding: .day, value: -3, to: Date())!

        _ = createReservation(
            property: property,
            checkIn: pastCheckIn,
            checkOut: pastCheckOut,
            totalAmount: 1000,
            depositReceived: 1000,
            taxAmount: 100,
            taxRemitted: false
        )

        try context.save()

        // Act
        let calculation = service.calculateExpectedBalance(
            bankBalance: 1000,
            stripeHoldback: 0
        )

        // Assert
        XCTAssertEqual(calculation.unpaidTaxes, 100)
        XCTAssertEqual(calculation.unpaidTaxReservationCount, 1)
    }

    func testCalculateExpectedBalance_ExcludesRemittedTaxes() throws {
        // Arrange
        let owner = createOwner(name: "Test Owner")
        let property = createProperty(name: "Test Property", owner: owner)

        let pastCheckIn = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let pastCheckOut = Calendar.current.date(byAdding: .day, value: -3, to: Date())!

        _ = createReservation(
            property: property,
            checkIn: pastCheckIn,
            checkOut: pastCheckOut,
            totalAmount: 1000,
            depositReceived: 1000,
            taxAmount: 100,
            taxRemitted: true  // Already remitted
        )

        try context.save()

        // Act
        let calculation = service.calculateExpectedBalance(
            bankBalance: 1000,
            stripeHoldback: 0
        )

        // Assert
        XCTAssertEqual(calculation.unpaidTaxes, 0)
        XCTAssertEqual(calculation.unpaidTaxReservationCount, 0)
    }

    // MARK: - Balance Calculation Tests

    func testCalculateExpectedBalance_FullFormula() throws {
        // Arrange
        let owner = createOwner(name: "Test Owner", managementFeePercent: 20)
        let property = createProperty(name: "Test Property", owner: owner)

        // Future reservation with deposit
        let futureDate = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        let futureCheckOut = Calendar.current.date(byAdding: .day, value: 10, to: Date())!

        _ = createReservation(
            property: property,
            checkIn: futureDate,
            checkOut: futureCheckOut,
            totalAmount: 500,
            depositReceived: 500
        )

        // Completed reservation with unpaid payout and taxes
        let pastCheckIn = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let pastCheckOut = Calendar.current.date(byAdding: .day, value: -3, to: Date())!

        let completedReservation = createReservation(
            property: property,
            checkIn: pastCheckIn,
            checkOut: pastCheckOut,
            totalAmount: 1000,
            depositReceived: 1000,
            taxAmount: 100,
            ownerPaidOut: false,
            taxRemitted: false
        )

        try context.save()

        // Act
        let bankBalance: Decimal = 1500
        let stripeHoldback: Decimal = 200

        let calculation = service.calculateExpectedBalance(
            bankBalance: bankBalance,
            stripeHoldback: stripeHoldback
        )

        // Assert
        // Expected = FutureDeposits - StripeHoldback + UnpaidPayouts + UnpaidTaxes
        let ownerPayout = completedReservation.ownerPayout as Decimal? ?? 0

        XCTAssertEqual(calculation.futureDeposits, 500)
        XCTAssertEqual(calculation.stripeHoldback, 200)
        XCTAssertEqual(calculation.unpaidOwnerPayouts, ownerPayout)
        XCTAssertEqual(calculation.unpaidTaxes, 100)

        let expectedBalance = 500 - 200 + ownerPayout + 100
        XCTAssertEqual(calculation.expectedBalance, expectedBalance)

        // Actual balance = bank + stripe holdback
        XCTAssertEqual(calculation.actualBalance, 1700)

        // Variance = actual - expected
        XCTAssertEqual(calculation.variance, calculation.actualBalance - calculation.expectedBalance)
    }

    func testCalculateExpectedBalance_IsBalanced() throws {
        // Arrange
        let owner = createOwner(name: "Test Owner")
        let property = createProperty(name: "Test Property", owner: owner)

        let futureDate = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        let futureCheckOut = Calendar.current.date(byAdding: .day, value: 10, to: Date())!

        _ = createReservation(
            property: property,
            checkIn: futureDate,
            checkOut: futureCheckOut,
            totalAmount: 1000,
            depositReceived: 1000
        )

        try context.save()

        // Act - Set bank balance to exactly match expected
        let calculation = service.calculateExpectedBalance(
            bankBalance: 1000,
            stripeHoldback: 0
        )

        // Assert
        XCTAssertTrue(calculation.isBalanced)
        XCTAssertLessThan(abs(calculation.variance), 1)
    }

    func testCalculateExpectedBalance_VarianceDetected() throws {
        // Arrange
        let owner = createOwner(name: "Test Owner")
        let property = createProperty(name: "Test Property", owner: owner)

        let futureDate = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        let futureCheckOut = Calendar.current.date(byAdding: .day, value: 10, to: Date())!

        _ = createReservation(
            property: property,
            checkIn: futureDate,
            checkOut: futureCheckOut,
            totalAmount: 1000,
            depositReceived: 1000
        )

        try context.save()

        // Act - Bank balance doesn't match
        let calculation = service.calculateExpectedBalance(
            bankBalance: 500,  // Short by 500
            stripeHoldback: 0
        )

        // Assert
        XCTAssertFalse(calculation.isBalanced)
        XCTAssertEqual(calculation.variance, -500)
    }

    // MARK: - Save Reconciliation Tests

    func testSaveReconciliation_CreatesSnapshot() throws {
        // Arrange
        let calculation = TrustCalculationService.TrustCalculation(
            calculationDate: Date(),
            bankBalance: 1000,
            stripeHoldback: 200,
            futureDeposits: 500,
            unpaidOwnerPayouts: 400,
            unpaidTaxes: 100,
            maintenanceReserves: 50,
            futureReservationCount: 2,
            unpaidPayoutReservationCount: 3,
            unpaidTaxReservationCount: 1,
            futureReservations: [],
            unpaidPayoutReservations: [],
            unpaidTaxReservations: []
        )

        // Act
        let snapshot = try service.saveReconciliation(calculation, notes: "Test reconciliation")

        // Assert
        XCTAssertNotNil(snapshot.id)
        XCTAssertEqual(snapshot.bankBalance as Decimal?, 1000)
        XCTAssertEqual(snapshot.stripeHoldback as Decimal?, 200)
        XCTAssertEqual(snapshot.futureDeposits as Decimal?, 500)
        XCTAssertEqual(snapshot.unpaidOwnerPayouts as Decimal?, 400)
        XCTAssertEqual(snapshot.unpaidTaxes as Decimal?, 100)
        XCTAssertEqual(snapshot.maintenanceReserves as Decimal?, 50)
        XCTAssertEqual(snapshot.notes, "Test reconciliation")
    }

    // MARK: - Empty State Tests

    func testCalculateExpectedBalance_EmptyDatabase() throws {
        // Act
        let calculation = service.calculateExpectedBalance(
            bankBalance: 0,
            stripeHoldback: 0
        )

        // Assert
        XCTAssertEqual(calculation.futureDeposits, 0)
        XCTAssertEqual(calculation.unpaidOwnerPayouts, 0)
        XCTAssertEqual(calculation.unpaidTaxes, 0)
        XCTAssertEqual(calculation.expectedBalance, 0)
        XCTAssertTrue(calculation.isBalanced)
    }
}
