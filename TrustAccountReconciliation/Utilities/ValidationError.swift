import Foundation

/// Validation errors for data integrity checks
enum ValidationError: LocalizedError {
    case requiredField(String)
    case invalidValue(String)
    case periodLocked(String)
    case insufficientFunds(String)
    case duplicateEntry(String)
    case dataIntegrity(String)
    case networkError(String)
    case fileError(String)

    var errorDescription: String? {
        switch self {
        case .requiredField(let message):
            return "Required Field: \(message)"
        case .invalidValue(let message):
            return "Invalid Value: \(message)"
        case .periodLocked(let message):
            return "Period Locked: \(message)"
        case .insufficientFunds(let message):
            return "Insufficient Funds: \(message)"
        case .duplicateEntry(let message):
            return "Duplicate Entry: \(message)"
        case .dataIntegrity(let message):
            return "Data Integrity Error: \(message)"
        case .networkError(let message):
            return "Network Error: \(message)"
        case .fileError(let message):
            return "File Error: \(message)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .requiredField:
            return "Please fill in all required fields."
        case .invalidValue:
            return "Please check the entered value and try again."
        case .periodLocked:
            return "Contact your administrator to unlock the period if changes are needed."
        case .insufficientFunds:
            return "Ensure sufficient funds are available before proceeding."
        case .duplicateEntry:
            return "A similar entry already exists. Please verify and update if needed."
        case .dataIntegrity:
            return "Run a data integrity check from Settings to diagnose the issue."
        case .networkError:
            return "Check your internet connection and try again."
        case .fileError:
            return "Check file permissions and available disk space."
        }
    }
}
