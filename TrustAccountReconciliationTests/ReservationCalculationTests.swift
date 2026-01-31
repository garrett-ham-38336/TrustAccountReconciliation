import XCTest
import CoreData
@testable import TrustAccountReconciliation

final class ReservationCalculationTests: XCTestCase {

    var persistenceController: PersistenceController!
    var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        persistenceController = PersistenceController(inMemory: true)
        context = persistenceController.container.viewContext
    }

    override func tearDownWithError() throws {
        persistenceController = nil
        context = nil
    }

    // MARK: - Helper Methods

    private func createOwner(managementFeePercent: Decimal = 20) -> Owner {
        let owner = Owner(context: context)
        owner.id = UUID()
        owner.name = "Test Owner"
        owner.managementFeePercent = managementFeePercent as NSDecimalNumber
        owner.isActive = true
        owner.createdAt = Date()
        owner.updatedAt = Date()
        return owner
    }

    private func createProperty(owner: Owner?, managementFeePercent: Decimal? = nil) -> Property {
        let property = Property(context: context)
        property.id = UUID()
        property.name = "Test Property"
        property.owner = owner
        if let fee = managementFeePercent {
            property.managementFeePercent = fee as NSDecimalNumber
        }
        property.isActive = true
        property.createdAt = Date()
        property.updatedAt = Date()
        return property
    }

    private func createReservation(
        property: Property?,
        totalAmount: Decimal,
        taxAmount: Decimal = 0,
        hostServiceFee: Decimal = 0
    ) -> Reservation {
        let reservation = Reservation(context: context)
        reservation.id = UUID()
        reservation.guestName = "Test Guest"
        reservation.property = property
        reservation.checkInDate = Date()
        reservation.checkOutDate = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
        reservation.totalAmount = totalAmount as NSDecimalNumber
        reservation.taxAmount = taxAmount as NSDecimalNumber
        reservation.hostServiceFee = hostServiceFee as NSDecimalNumber
        reservation.createdAt = Date()
        reservation.updatedAt = Date()
        return reservation
    }

    // MARK: - Owner Payout Calculation Tests

    func testCalculateOwnerPayout_DefaultFee() throws {
        // Arrange
        let reservation = createReservation(
            property: nil,
            totalAmount: 1000,
            taxAmount: 0
        )

        // Act
        let payout = reservation.calculateOwnerPayout()

        // Assert
        // Default is 20% management fee, so owner gets 80%
        XCTAssertEqual(payout, 800)
    }

    func testCalculateOwnerPayout_WithOwnerFee() throws {
        // Arrange
        let owner = createOwner(managementFeePercent: 25)
        let property = createProperty(owner: owner)
        let reservation = createReservation(
            property: property,
            totalAmount: 1000
        )

        // Act
        let payout = reservation.calculateOwnerPayout()

        // Assert
        // 25% management fee, owner gets 75%
        XCTAssertEqual(payout, 750)
    }

    func testCalculateOwnerPayout_WithPropertyFee() throws {
        // Arrange
        let owner = createOwner(managementFeePercent: 20)
        let property = createProperty(owner: owner, managementFeePercent: 30)
        let reservation = createReservation(
            property: property,
            totalAmount: 1000
        )

        // Act
        let payout = reservation.calculateOwnerPayout()

        // Assert
        // Property fee (30%) takes precedence over owner fee (20%)
        XCTAssertEqual(payout, 700)
    }

    func testCalculateOwnerPayout_ExcludesTaxes() throws {
        // Arrange
        let owner = createOwner(managementFeePercent: 20)
        let property = createProperty(owner: owner)
        let reservation = createReservation(
            property: property,
            totalAmount: 1000,
            taxAmount: 100  // $100 in taxes
        )

        // Act
        let payout = reservation.calculateOwnerPayout()

        // Assert
        // Net revenue = 1000 - 100 = 900
        // Management fee = 900 * 0.20 = 180
        // Owner payout = 900 - 180 = 720
        XCTAssertEqual(payout, 720)
    }

    func testCalculateOwnerPayout_ExcludesHostFees() throws {
        // Arrange
        let owner = createOwner(managementFeePercent: 20)
        let property = createProperty(owner: owner)
        let reservation = createReservation(
            property: property,
            totalAmount: 1000,
            taxAmount: 0,
            hostServiceFee: 50
        )

        // Act
        let payout = reservation.calculateOwnerPayout()

        // Assert
        // Net revenue = 1000 - 50 = 950
        // Management fee = 950 * 0.20 = 190
        // Owner payout = 950 - 190 = 760
        XCTAssertEqual(payout, 760)
    }

    func testCalculateOwnerPayout_ComplexScenario() throws {
        // Arrange
        let owner = createOwner(managementFeePercent: 15)
        let property = createProperty(owner: owner)
        let reservation = createReservation(
            property: property,
            totalAmount: 1500,
            taxAmount: 150,
            hostServiceFee: 100
        )

        // Act
        let payout = reservation.calculateOwnerPayout()

        // Assert
        // Net revenue = 1500 - 150 - 100 = 1250
        // Management fee = 1250 * 0.15 = 187.50
        // Owner payout = 1250 - 187.50 = 1062.50
        XCTAssertEqual(payout, Decimal(string: "1062.5")!)
    }

    // MARK: - Management Fee Calculation Tests

    func testCalculateManagementFee_DefaultFee() throws {
        // Arrange
        let reservation = createReservation(
            property: nil,
            totalAmount: 1000
        )

        // Act
        let fee = reservation.calculateManagementFee()

        // Assert
        // Default 20% of 1000 = 200
        XCTAssertEqual(fee, 200)
    }

    func testCalculateManagementFee_WithPropertyFee() throws {
        // Arrange
        let owner = createOwner(managementFeePercent: 20)
        let property = createProperty(owner: owner, managementFeePercent: 25)
        let reservation = createReservation(
            property: property,
            totalAmount: 1000
        )

        // Act
        let fee = reservation.calculateManagementFee()

        // Assert
        // Property fee of 25% = 250
        XCTAssertEqual(fee, 250)
    }

    func testCalculateManagementFee_ExcludesTaxes() throws {
        // Arrange
        let owner = createOwner(managementFeePercent: 20)
        let property = createProperty(owner: owner)
        let reservation = createReservation(
            property: property,
            totalAmount: 1000,
            taxAmount: 100
        )

        // Act
        let fee = reservation.calculateManagementFee()

        // Assert
        // Net = 900, fee = 900 * 0.20 = 180
        XCTAssertEqual(fee, 180)
    }

    // MARK: - Reservation Status Tests

    func testIsFuture_FutureCheckIn() throws {
        // Arrange
        let reservation = Reservation(context: context)
        reservation.id = UUID()
        reservation.guestName = "Test"
        reservation.checkInDate = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        reservation.checkOutDate = Calendar.current.date(byAdding: .day, value: 10, to: Date())!
        reservation.isCancelled = false
        reservation.createdAt = Date()
        reservation.updatedAt = Date()

        // Assert
        XCTAssertTrue(reservation.isFuture)
        XCTAssertFalse(reservation.isActive)
        XCTAssertFalse(reservation.isCompleted)
    }

    func testIsActive_CurrentStay() throws {
        // Arrange
        let reservation = Reservation(context: context)
        reservation.id = UUID()
        reservation.guestName = "Test"
        reservation.checkInDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        reservation.checkOutDate = Calendar.current.date(byAdding: .day, value: 2, to: Date())!
        reservation.isCancelled = false
        reservation.createdAt = Date()
        reservation.updatedAt = Date()

        // Assert
        XCTAssertTrue(reservation.isActive)
        XCTAssertFalse(reservation.isFuture)
        XCTAssertFalse(reservation.isCompleted)
    }

    func testIsCompleted_PastCheckOut() throws {
        // Arrange
        let reservation = Reservation(context: context)
        reservation.id = UUID()
        reservation.guestName = "Test"
        reservation.checkInDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        reservation.checkOutDate = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        reservation.isCancelled = false
        reservation.createdAt = Date()
        reservation.updatedAt = Date()

        // Assert
        XCTAssertTrue(reservation.isCompleted)
        XCTAssertFalse(reservation.isFuture)
        XCTAssertFalse(reservation.isActive)
    }

    func testCancelledReservation_NotFuture() throws {
        // Arrange
        let reservation = Reservation(context: context)
        reservation.id = UUID()
        reservation.guestName = "Test"
        reservation.checkInDate = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        reservation.checkOutDate = Calendar.current.date(byAdding: .day, value: 10, to: Date())!
        reservation.isCancelled = true
        reservation.createdAt = Date()
        reservation.updatedAt = Date()

        // Assert
        XCTAssertFalse(reservation.isFuture)
    }

    func testCancelledReservation_NotCompleted() throws {
        // Arrange
        let reservation = Reservation(context: context)
        reservation.id = UUID()
        reservation.guestName = "Test"
        reservation.checkInDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        reservation.checkOutDate = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        reservation.isCancelled = true
        reservation.createdAt = Date()
        reservation.updatedAt = Date()

        // Assert
        XCTAssertFalse(reservation.isCompleted)
    }

    // MARK: - Date Range String Tests

    func testDateRangeString() throws {
        // Arrange
        let checkIn = Date()
        let checkOut = Calendar.current.date(byAdding: .day, value: 3, to: Date())!

        let reservation = Reservation(context: context)
        reservation.id = UUID()
        reservation.guestName = "Test"
        reservation.checkInDate = checkIn
        reservation.checkOutDate = checkOut
        reservation.createdAt = Date()
        reservation.updatedAt = Date()

        // Act
        let dateRange = reservation.dateRangeString

        // Assert
        XCTAssertFalse(dateRange.isEmpty)
        XCTAssertTrue(dateRange.contains(" - "))
    }

    // MARK: - Edge Cases

    func testCalculateOwnerPayout_ZeroAmount() throws {
        // Arrange
        let reservation = createReservation(
            property: nil,
            totalAmount: 0
        )

        // Act
        let payout = reservation.calculateOwnerPayout()

        // Assert
        XCTAssertEqual(payout, 0)
    }

    func testCalculateOwnerPayout_TaxesEqualTotal() throws {
        // Arrange
        let reservation = createReservation(
            property: nil,
            totalAmount: 100,
            taxAmount: 100
        )

        // Act
        let payout = reservation.calculateOwnerPayout()

        // Assert
        // Net revenue is 0, so payout is 0
        XCTAssertEqual(payout, 0)
    }

    func testCalculateOwnerPayout_LargeAmount() throws {
        // Arrange
        let owner = createOwner(managementFeePercent: 20)
        let property = createProperty(owner: owner)
        let reservation = createReservation(
            property: property,
            totalAmount: 100000,
            taxAmount: 10000
        )

        // Act
        let payout = reservation.calculateOwnerPayout()

        // Assert
        // Net = 90000, fee = 18000, payout = 72000
        XCTAssertEqual(payout, 72000)
    }
}
