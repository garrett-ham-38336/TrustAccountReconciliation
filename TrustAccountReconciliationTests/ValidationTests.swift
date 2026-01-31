import XCTest
@testable import TrustAccountReconciliation

final class ValidationTests: XCTestCase {

    // MARK: - Currency Validation Tests

    func testValidateCurrency_ValidAmount() {
        let result = InputValidation.validateCurrency(1000)
        XCTAssertTrue(result.isValid)
        XCTAssertNil(result.errorMessage)
    }

    func testValidateCurrency_ZeroAmount() {
        let result = InputValidation.validateCurrency(0)
        XCTAssertTrue(result.isValid)
    }

    func testValidateCurrency_NegativeAmount() {
        let result = InputValidation.validateCurrency(-100)
        XCTAssertFalse(result.isValid)
        XCTAssertNotNil(result.errorMessage)
        XCTAssertTrue(result.errorMessage!.contains("negative"))
    }

    func testValidateCurrency_NegativeAllowed() {
        let result = InputValidation.validateCurrency(-100, allowNegative: true)
        XCTAssertTrue(result.isValid)
    }

    func testValidateCurrency_ExceedsMaximum() {
        let result = InputValidation.validateCurrency(1000, maximum: 500)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errorMessage!.contains("exceed"))
    }

    func testValidateCurrency_WithinMaximum() {
        let result = InputValidation.validateCurrency(400, maximum: 500)
        XCTAssertTrue(result.isValid)
    }

    func testValidateCurrency_ExceedsSanityMax() {
        let result = InputValidation.validateCurrency(100_000_000)
        XCTAssertFalse(result.isValid)
    }

    // MARK: - Parse Currency Tests

    func testParseCurrency_ValidString() {
        let (value, result) = InputValidation.parseCurrency("1000.50")
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(value, Decimal(string: "1000.50"))
    }

    func testParseCurrency_WithDollarSign() {
        let (value, result) = InputValidation.parseCurrency("$1,234.56")
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(value, Decimal(string: "1234.56"))
    }

    func testParseCurrency_EmptyString() {
        let (value, result) = InputValidation.parseCurrency("")
        XCTAssertFalse(result.isValid)
        XCTAssertNil(value)
        XCTAssertTrue(result.errorMessage!.contains("required"))
    }

    func testParseCurrency_InvalidString() {
        let (value, result) = InputValidation.parseCurrency("abc")
        XCTAssertFalse(result.isValid)
        XCTAssertNil(value)
        XCTAssertTrue(result.errorMessage!.contains("valid number"))
    }

    // MARK: - Percentage Validation Tests

    func testValidatePercentage_ValidValue() {
        let result = InputValidation.validatePercentage(25)
        XCTAssertTrue(result.isValid)
    }

    func testValidatePercentage_Zero() {
        let result = InputValidation.validatePercentage(0)
        XCTAssertTrue(result.isValid)
    }

    func testValidatePercentage_MaximumValue() {
        let result = InputValidation.validatePercentage(100)
        XCTAssertTrue(result.isValid)
    }

    func testValidatePercentage_ExceedsMaximum() {
        let result = InputValidation.validatePercentage(150)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errorMessage!.contains("100"))
    }

    func testValidatePercentage_Negative() {
        let result = InputValidation.validatePercentage(-5)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errorMessage!.contains("negative"))
    }

    func testValidatePercentage_CustomRange() {
        let result = InputValidation.validatePercentage(50, minimum: 10, maximum: 40)
        XCTAssertFalse(result.isValid)
    }

    // MARK: - Management Fee Validation Tests

    func testValidateManagementFee_ValidFee() {
        let result = InputValidation.validateManagementFee(20)
        XCTAssertTrue(result.isValid)
    }

    func testValidateManagementFee_TooHigh() {
        let result = InputValidation.validateManagementFee(60)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errorMessage!.contains("50"))
    }

    func testValidateManagementFee_Zero() {
        let result = InputValidation.validateManagementFee(0)
        XCTAssertTrue(result.isValid)
    }

    // MARK: - Tax Rate Validation Tests

    func testValidateTaxRate_ValidRate() {
        let result = InputValidation.validateTaxRate(9.5)
        XCTAssertTrue(result.isValid)
    }

    func testValidateTaxRate_TooHigh() {
        let result = InputValidation.validateTaxRate(30)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errorMessage!.contains("25"))
    }

    // MARK: - Count Validation Tests

    func testValidateCount_ValidCount() {
        let result = InputValidation.validateCount(10)
        XCTAssertTrue(result.isValid)
    }

    func testValidateCount_Zero() {
        let result = InputValidation.validateCount(0)
        XCTAssertTrue(result.isValid)
    }

    func testValidateCount_ZeroNotAllowed() {
        let result = InputValidation.validateCount(0, allowZero: false)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errorMessage!.contains("greater than zero"))
    }

    func testValidateCount_Negative() {
        let result = InputValidation.validateCount(-5)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errorMessage!.contains("negative"))
    }

    func testValidateCount_BelowMinimum() {
        let result = InputValidation.validateCount(3, minimum: 5)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errorMessage!.contains("at least 5"))
    }

    func testValidateCount_AboveMaximum() {
        let result = InputValidation.validateCount(15, maximum: 10)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errorMessage!.contains("exceed 10"))
    }

    // MARK: - Night Count Validation Tests

    func testValidateNightCount_ValidNights() {
        let result = InputValidation.validateNightCount(7)
        XCTAssertTrue(result.isValid)
    }

    func testValidateNightCount_Zero() {
        let result = InputValidation.validateNightCount(0)
        XCTAssertFalse(result.isValid)
    }

    func testValidateNightCount_TooMany() {
        let result = InputValidation.validateNightCount(400)
        XCTAssertFalse(result.isValid)
    }

    // MARK: - Day of Month Validation Tests

    func testValidateDayOfMonth_ValidDay() {
        let result = InputValidation.validateDayOfMonth(15)
        XCTAssertTrue(result.isValid)
    }

    func testValidateDayOfMonth_FirstDay() {
        let result = InputValidation.validateDayOfMonth(1)
        XCTAssertTrue(result.isValid)
    }

    func testValidateDayOfMonth_LastValidDay() {
        let result = InputValidation.validateDayOfMonth(28)
        XCTAssertTrue(result.isValid)
    }

    func testValidateDayOfMonth_Invalid() {
        let result = InputValidation.validateDayOfMonth(30)
        XCTAssertFalse(result.isValid)
    }

    func testValidateDayOfMonth_Zero() {
        let result = InputValidation.validateDayOfMonth(0)
        XCTAssertFalse(result.isValid)
    }

    // MARK: - String Validation Tests

    func testValidateRequired_ValidString() {
        let result = InputValidation.validateRequired("Test Name")
        XCTAssertTrue(result.isValid)
    }

    func testValidateRequired_EmptyString() {
        let result = InputValidation.validateRequired("")
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errorMessage!.contains("required"))
    }

    func testValidateRequired_WhitespaceOnly() {
        let result = InputValidation.validateRequired("   ")
        XCTAssertFalse(result.isValid)
    }

    func testValidateRequired_TooShort() {
        let result = InputValidation.validateRequired("A", minLength: 3)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errorMessage!.contains("at least 3"))
    }

    func testValidateRequired_TooLong() {
        let longString = String(repeating: "A", count: 600)
        let result = InputValidation.validateRequired(longString, maxLength: 500)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errorMessage!.contains("exceed 500"))
    }

    // MARK: - Email Validation Tests

    func testValidateEmail_ValidEmail() {
        let result = InputValidation.validateEmail("test@example.com")
        XCTAssertTrue(result.isValid)
    }

    func testValidateEmail_EmptyEmail() {
        // Empty is valid (email is optional)
        let result = InputValidation.validateEmail("")
        XCTAssertTrue(result.isValid)
    }

    func testValidateEmail_InvalidFormat() {
        let result = InputValidation.validateEmail("not-an-email")
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errorMessage!.contains("valid email"))
    }

    func testValidateEmail_MissingAt() {
        let result = InputValidation.validateEmail("testexample.com")
        XCTAssertFalse(result.isValid)
    }

    func testValidateEmail_MissingDomain() {
        let result = InputValidation.validateEmail("test@")
        XCTAssertFalse(result.isValid)
    }

    // MARK: - Phone Validation Tests

    func testValidatePhone_ValidPhone() {
        let result = InputValidation.validatePhone("(555) 123-4567")
        XCTAssertTrue(result.isValid)
    }

    func testValidatePhone_EmptyPhone() {
        // Empty is valid (phone is optional)
        let result = InputValidation.validatePhone("")
        XCTAssertTrue(result.isValid)
    }

    func testValidatePhone_TooShort() {
        let result = InputValidation.validatePhone("555-1234")
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errorMessage!.contains("10 digits"))
    }

    func testValidatePhone_TooLong() {
        let result = InputValidation.validatePhone("1234567890123456")
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errorMessage!.contains("too long"))
    }

    func testValidatePhone_DigitsOnly() {
        let result = InputValidation.validatePhone("5551234567")
        XCTAssertTrue(result.isValid)
    }

    // MARK: - Date Validation Tests

    func testValidateFutureDate_FutureDate() {
        let futureDate = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        let result = InputValidation.validateFutureDate(futureDate)
        XCTAssertTrue(result.isValid)
    }

    func testValidateFutureDate_PastDate() {
        let pastDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let result = InputValidation.validateFutureDate(pastDate)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errorMessage!.contains("future"))
    }

    func testValidatePastOrPresentDate_PastDate() {
        let pastDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let result = InputValidation.validatePastOrPresentDate(pastDate)
        XCTAssertTrue(result.isValid)
    }

    func testValidatePastOrPresentDate_FutureDate() {
        let futureDate = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        let result = InputValidation.validatePastOrPresentDate(futureDate)
        XCTAssertFalse(result.isValid)
    }

    func testValidateDateRange_ValidRange() {
        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
        let result = InputValidation.validateDateRange(start: start, end: end)
        XCTAssertTrue(result.isValid)
    }

    func testValidateDateRange_InvalidRange() {
        let start = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
        let end = Date()
        let result = InputValidation.validateDateRange(start: start, end: end)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errorMessage!.contains("after"))
    }

    func testValidateDateRange_SameDate() {
        let date = Date()
        let result = InputValidation.validateDateRange(start: date, end: date)
        XCTAssertFalse(result.isValid)
    }

    // MARK: - Bank Balance Validation Tests

    func testValidateBankBalance_ValidBalance() {
        let result = InputValidation.validateBankBalance(50000)
        XCTAssertTrue(result.isValid)
    }

    func testValidateBankBalance_Negative() {
        let result = InputValidation.validateBankBalance(-1000)
        XCTAssertFalse(result.isValid)
    }

    func testValidateBankBalance_Zero() {
        let result = InputValidation.validateBankBalance(0)
        XCTAssertTrue(result.isValid)
    }

    // MARK: - Stripe Holdback Validation Tests

    func testValidateStripeHoldback_ValidAmount() {
        let result = InputValidation.validateStripeHoldback(5000)
        XCTAssertTrue(result.isValid)
    }

    func testValidateStripeHoldback_Negative() {
        let result = InputValidation.validateStripeHoldback(-500)
        XCTAssertFalse(result.isValid)
    }

    func testValidateStripeHoldback_Zero() {
        let result = InputValidation.validateStripeHoldback(0)
        XCTAssertTrue(result.isValid)
    }
}
