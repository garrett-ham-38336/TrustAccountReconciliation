import Foundation

/// Input validation utilities for currency, percentage, and count fields
enum InputValidation {

    // MARK: - Validation Results

    enum ValidationResult {
        case valid
        case invalid(String)

        var isValid: Bool {
            if case .valid = self { return true }
            return false
        }

        var errorMessage: String? {
            if case .invalid(let message) = self { return message }
            return nil
        }
    }

    // MARK: - Currency Validation

    /// Validates a currency amount
    /// - Parameters:
    ///   - value: The decimal value to validate
    ///   - allowNegative: Whether negative values are allowed (default: false)
    ///   - maximum: Optional maximum value
    ///   - fieldName: Name of the field for error messages
    /// - Returns: ValidationResult indicating success or failure with message
    static func validateCurrency(
        _ value: Decimal,
        allowNegative: Bool = false,
        maximum: Decimal? = nil,
        fieldName: String = "Amount"
    ) -> ValidationResult {
        // Check for negative values
        if !allowNegative && value < 0 {
            return .invalid("\(fieldName) cannot be negative")
        }

        // Check maximum
        if let max = maximum, value > max {
            return .invalid("\(fieldName) cannot exceed \(max.asCurrency)")
        }

        // Check for reasonable maximum (10 million as sanity check)
        let sanityMax: Decimal = 10_000_000
        if value > sanityMax {
            return .invalid("\(fieldName) exceeds maximum allowed value")
        }

        return .valid
    }

    /// Validates a currency string and converts to Decimal
    /// - Parameters:
    ///   - string: The string value to parse and validate
    ///   - allowNegative: Whether negative values are allowed
    ///   - maximum: Optional maximum value
    ///   - fieldName: Name of the field for error messages
    /// - Returns: Tuple of optional Decimal and ValidationResult
    static func parseCurrency(
        _ string: String,
        allowNegative: Bool = false,
        maximum: Decimal? = nil,
        fieldName: String = "Amount"
    ) -> (value: Decimal?, result: ValidationResult) {
        // Remove currency symbols and whitespace
        let cleaned = string
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)

        guard !cleaned.isEmpty else {
            return (nil, .invalid("\(fieldName) is required"))
        }

        guard let decimal = Decimal(string: cleaned) else {
            return (nil, .invalid("\(fieldName) must be a valid number"))
        }

        let validation = validateCurrency(decimal, allowNegative: allowNegative, maximum: maximum, fieldName: fieldName)
        return (decimal, validation)
    }

    // MARK: - Percentage Validation

    /// Validates a percentage value
    /// - Parameters:
    ///   - value: The decimal percentage (0-100 scale)
    ///   - allowNegative: Whether negative values are allowed (default: false)
    ///   - minimum: Minimum allowed percentage (default: 0)
    ///   - maximum: Maximum allowed percentage (default: 100)
    ///   - fieldName: Name of the field for error messages
    /// - Returns: ValidationResult indicating success or failure
    static func validatePercentage(
        _ value: Decimal,
        allowNegative: Bool = false,
        minimum: Decimal = 0,
        maximum: Decimal = 100,
        fieldName: String = "Percentage"
    ) -> ValidationResult {
        if !allowNegative && value < 0 {
            return .invalid("\(fieldName) cannot be negative")
        }

        if value < minimum {
            return .invalid("\(fieldName) must be at least \(minimum)%")
        }

        if value > maximum {
            return .invalid("\(fieldName) cannot exceed \(maximum)%")
        }

        return .valid
    }

    /// Validates a management fee percentage (0-50% reasonable range)
    static func validateManagementFee(_ value: Decimal) -> ValidationResult {
        return validatePercentage(
            value,
            minimum: 0,
            maximum: 50,
            fieldName: "Management fee"
        )
    }

    /// Validates a tax rate percentage (0-25% reasonable range)
    static func validateTaxRate(_ value: Decimal) -> ValidationResult {
        return validatePercentage(
            value,
            minimum: 0,
            maximum: 25,
            fieldName: "Tax rate"
        )
    }

    // MARK: - Count Validation

    /// Validates a count/integer value
    /// - Parameters:
    ///   - value: The integer value to validate
    ///   - allowZero: Whether zero is allowed (default: true)
    ///   - allowNegative: Whether negative values are allowed (default: false)
    ///   - minimum: Optional minimum value
    ///   - maximum: Optional maximum value
    ///   - fieldName: Name of the field for error messages
    /// - Returns: ValidationResult indicating success or failure
    static func validateCount(
        _ value: Int,
        allowZero: Bool = true,
        allowNegative: Bool = false,
        minimum: Int? = nil,
        maximum: Int? = nil,
        fieldName: String = "Value"
    ) -> ValidationResult {
        if !allowNegative && value < 0 {
            return .invalid("\(fieldName) cannot be negative")
        }

        if !allowZero && value == 0 {
            return .invalid("\(fieldName) must be greater than zero")
        }

        if let min = minimum, value < min {
            return .invalid("\(fieldName) must be at least \(min)")
        }

        if let max = maximum, value > max {
            return .invalid("\(fieldName) cannot exceed \(max)")
        }

        return .valid
    }

    /// Validates night count (1-365 reasonable range)
    static func validateNightCount(_ value: Int) -> ValidationResult {
        return validateCount(
            value,
            allowZero: false,
            minimum: 1,
            maximum: 365,
            fieldName: "Night count"
        )
    }

    /// Validates day of month (1-28 for remittance due day)
    static func validateDayOfMonth(_ value: Int) -> ValidationResult {
        return validateCount(
            value,
            allowZero: false,
            minimum: 1,
            maximum: 28,
            fieldName: "Day of month"
        )
    }

    // MARK: - String Validation

    /// Validates a required string field
    /// - Parameters:
    ///   - value: The string to validate
    ///   - minLength: Minimum required length (default: 1)
    ///   - maxLength: Maximum allowed length (default: 500)
    ///   - fieldName: Name of the field for error messages
    /// - Returns: ValidationResult indicating success or failure
    static func validateRequired(
        _ value: String,
        minLength: Int = 1,
        maxLength: Int = 500,
        fieldName: String = "Field"
    ) -> ValidationResult {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return .invalid("\(fieldName) is required")
        }

        if trimmed.count < minLength {
            return .invalid("\(fieldName) must be at least \(minLength) characters")
        }

        if trimmed.count > maxLength {
            return .invalid("\(fieldName) cannot exceed \(maxLength) characters")
        }

        return .valid
    }

    /// Validates an email address format
    static func validateEmail(_ value: String) -> ValidationResult {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return .valid // Email is optional in most cases
        }

        // Basic email regex pattern
        let pattern = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let predicate = NSPredicate(format: "SELF MATCHES %@", pattern)

        if !predicate.evaluate(with: trimmed) {
            return .invalid("Please enter a valid email address")
        }

        return .valid
    }

    /// Validates a phone number format (basic)
    static func validatePhone(_ value: String) -> ValidationResult {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return .valid // Phone is optional
        }

        // Remove common formatting characters
        let digits = trimmed.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)

        if digits.count < 10 {
            return .invalid("Phone number must have at least 10 digits")
        }

        if digits.count > 15 {
            return .invalid("Phone number is too long")
        }

        return .valid
    }

    // MARK: - Date Validation

    /// Validates that a date is in the future
    static func validateFutureDate(_ date: Date, fieldName: String = "Date") -> ValidationResult {
        if date <= Date() {
            return .invalid("\(fieldName) must be in the future")
        }
        return .valid
    }

    /// Validates that a date is not in the future
    static func validatePastOrPresentDate(_ date: Date, fieldName: String = "Date") -> ValidationResult {
        if date > Date() {
            return .invalid("\(fieldName) cannot be in the future")
        }
        return .valid
    }

    /// Validates a date range
    static func validateDateRange(
        start: Date,
        end: Date,
        startFieldName: String = "Start date",
        endFieldName: String = "End date"
    ) -> ValidationResult {
        if end <= start {
            return .invalid("\(endFieldName) must be after \(startFieldName)")
        }
        return .valid
    }

    // MARK: - Bank Balance Validation

    /// Validates a bank balance for reconciliation
    static func validateBankBalance(_ value: Decimal) -> ValidationResult {
        return validateCurrency(
            value,
            allowNegative: false,
            maximum: 100_000_000,
            fieldName: "Bank balance"
        )
    }

    /// Validates Stripe holdback amount
    static func validateStripeHoldback(_ value: Decimal) -> ValidationResult {
        return validateCurrency(
            value,
            allowNegative: false,
            maximum: 10_000_000,
            fieldName: "Stripe holdback"
        )
    }
}

// Note: asCurrency extension is defined in Formatters.swift
