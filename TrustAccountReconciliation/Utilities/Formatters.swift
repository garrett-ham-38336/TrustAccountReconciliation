import Foundation

/// Centralized formatters for consistent display throughout the app
struct Formatters {
    // MARK: - Currency Formatting

    /// Standard currency formatter (USD)
    static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    /// Currency formatter without symbol (for data entry)
    static let currencyNoSymbol: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    /// Formats a Decimal as currency
    static func formatCurrency(_ value: Decimal) -> String {
        return currency.string(from: value as NSDecimalNumber) ?? "$0.00"
    }

    /// Formats a Decimal as currency with explicit sign
    static func formatCurrencyWithSign(_ value: Decimal) -> String {
        let formatted = formatCurrency(abs(value))
        if value < 0 {
            return "-\(formatted)"
        } else if value > 0 {
            return "+\(formatted)"
        }
        return formatted
    }

    // MARK: - Percentage Formatting

    /// Percentage formatter
    static let percentage: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    /// Formats a Decimal as percentage (expects 0.10 for 10%)
    static func formatPercentage(_ value: Decimal) -> String {
        return percentage.string(from: value as NSDecimalNumber) ?? "0%"
    }

    // MARK: - Date Formatting

    /// Short date formatter (e.g., "Jan 15, 2024")
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    /// Long date formatter (e.g., "January 15, 2024")
    static let longDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()

    /// Date and time formatter
    static let dateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    /// Month and year formatter (e.g., "January 2024")
    static let monthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    /// ISO date formatter for data export
    static let isoDate: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()

    /// Formats a date for display
    static func formatDate(_ date: Date, style: DateFormatStyle = .short) -> String {
        switch style {
        case .short:
            return shortDate.string(from: date)
        case .long:
            return longDate.string(from: date)
        case .dateTime:
            return dateTime.string(from: date)
        case .monthYear:
            return monthYear.string(from: date)
        case .iso:
            return isoDate.string(from: date)
        }
    }

    enum DateFormatStyle {
        case short
        case long
        case dateTime
        case monthYear
        case iso
    }

    // MARK: - Number Formatting

    /// Integer formatter
    static let integer: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    /// Decimal formatter with 2 places
    static let decimal: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    // MARK: - Account Number Formatting

    /// Masks an account number for display (shows last 4 digits)
    static func maskAccountNumber(_ accountNumber: String) -> String {
        guard accountNumber.count > 4 else { return "****" }
        let lastFour = String(accountNumber.suffix(4))
        return "****\(lastFour)"
    }

    /// Formats a check number with leading zeros
    static func formatCheckNumber(_ number: Int, digits: Int = 4) -> String {
        return String(format: "%0\(digits)d", number)
    }

    // MARK: - Phone Number Formatting

    /// Formats a phone number for display
    static func formatPhoneNumber(_ phone: String) -> String {
        let digits = phone.filter { $0.isNumber }
        guard digits.count == 10 else { return phone }

        let areaCode = String(digits.prefix(3))
        let exchange = String(digits.dropFirst(3).prefix(3))
        let subscriber = String(digits.suffix(4))

        return "(\(areaCode)) \(exchange)-\(subscriber)"
    }

    // MARK: - File Size Formatting

    /// Formats bytes as human-readable file size
    static func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Duration Formatting

    /// Formats a number of days as a duration string
    static func formatDays(_ days: Int) -> String {
        if days == 0 {
            return "Today"
        } else if days == 1 {
            return "1 day"
        } else if days < 7 {
            return "\(days) days"
        } else if days < 30 {
            let weeks = days / 7
            return weeks == 1 ? "1 week" : "\(weeks) weeks"
        } else if days < 365 {
            let months = days / 30
            return months == 1 ? "1 month" : "\(months) months"
        } else {
            let years = days / 365
            return years == 1 ? "1 year" : "\(years) years"
        }
    }

    /// Formats nights for booking display
    static func formatNights(_ nights: Int) -> String {
        return nights == 1 ? "1 night" : "\(nights) nights"
    }
}

// MARK: - Decimal Extensions

extension Decimal {
    /// Formats as currency string
    var asCurrency: String {
        return Formatters.formatCurrency(self)
    }

    /// Formats as percentage string
    var asPercentage: String {
        return Formatters.formatPercentage(self)
    }
}

// MARK: - Date Extensions

extension Date {
    /// Formats as short date string
    var asShortDate: String {
        return Formatters.formatDate(self, style: .short)
    }

    /// Formats as long date string
    var asLongDate: String {
        return Formatters.formatDate(self, style: .long)
    }

    /// Formats as month and year
    var asMonthYear: String {
        return Formatters.formatDate(self, style: .monthYear)
    }

    /// Gets the start of the month
    var startOfMonth: Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: self)
        return calendar.date(from: components) ?? self
    }

    /// Gets the end of the month
    var endOfMonth: Date {
        let calendar = Calendar.current
        guard let startOfNextMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) else {
            return self
        }
        return calendar.date(byAdding: .day, value: -1, to: startOfNextMonth) ?? self
    }
}
