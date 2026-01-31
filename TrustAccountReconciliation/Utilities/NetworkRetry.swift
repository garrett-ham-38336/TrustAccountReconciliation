import Foundation

/// Configuration for network retry behavior
struct RetryConfiguration {
    /// Maximum number of retry attempts
    var maxAttempts: Int

    /// Initial delay between retries (in seconds)
    var initialDelay: TimeInterval

    /// Maximum delay between retries (in seconds)
    var maxDelay: TimeInterval

    /// Multiplier for exponential backoff
    var backoffMultiplier: Double

    /// Whether to add jitter to delays
    var useJitter: Bool

    /// Default configuration
    static let `default` = RetryConfiguration(
        maxAttempts: 3,
        initialDelay: 1.0,
        maxDelay: 30.0,
        backoffMultiplier: 2.0,
        useJitter: true
    )

    /// More aggressive retry for critical operations
    static let aggressive = RetryConfiguration(
        maxAttempts: 5,
        initialDelay: 0.5,
        maxDelay: 60.0,
        backoffMultiplier: 2.0,
        useJitter: true
    )

    /// Single retry for quick operations
    static let quick = RetryConfiguration(
        maxAttempts: 2,
        initialDelay: 0.5,
        maxDelay: 5.0,
        backoffMultiplier: 2.0,
        useJitter: false
    )
}

/// Errors that can occur during retry operations
enum RetryError: LocalizedError {
    case maxAttemptsExceeded(lastError: Error)
    case nonRetryableError(Error)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .maxAttemptsExceeded(let lastError):
            return "Maximum retry attempts exceeded. Last error: \(lastError.localizedDescription)"
        case .nonRetryableError(let error):
            return "Non-retryable error: \(error.localizedDescription)"
        case .cancelled:
            return "Operation was cancelled"
        }
    }
}

/// Result of a retry operation
struct RetryResult<T> {
    let value: T
    let attempts: Int
    let totalDuration: TimeInterval
}

/// Utility for retrying async operations with exponential backoff
enum NetworkRetry {

    /// Determines if an error is retryable
    static func isRetryable(_ error: Error) -> Bool {
        // URLError cases that are retryable
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut,
                 .cannotFindHost,
                 .cannotConnectToHost,
                 .networkConnectionLost,
                 .dnsLookupFailed,
                 .notConnectedToInternet,
                 .internationalRoamingOff,
                 .dataNotAllowed,
                 .secureConnectionFailed:
                return true
            default:
                return false
            }
        }

        // Check for HTTP status codes in custom errors
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return true
        }

        // Server errors (5xx) are generally retryable
        // Client errors (4xx) are generally not, except 429 (Too Many Requests)
        if let statusCode = (error as? HTTPStatusError)?.statusCode {
            return statusCode >= 500 || statusCode == 429
        }

        return false
    }

    /// Calculates delay for a given attempt with exponential backoff
    static func calculateDelay(
        attempt: Int,
        configuration: RetryConfiguration
    ) -> TimeInterval {
        let exponentialDelay = configuration.initialDelay * pow(configuration.backoffMultiplier, Double(attempt - 1))
        var delay = min(exponentialDelay, configuration.maxDelay)

        if configuration.useJitter {
            // Add up to 25% random jitter
            let jitter = delay * Double.random(in: 0...0.25)
            delay += jitter
        }

        return delay
    }

    /// Executes an async operation with retry logic
    /// - Parameters:
    ///   - configuration: Retry configuration
    ///   - operation: The async operation to retry
    /// - Returns: RetryResult containing the value and retry statistics
    static func execute<T>(
        configuration: RetryConfiguration = .default,
        operation: @escaping () async throws -> T
    ) async throws -> RetryResult<T> {
        let startTime = Date()
        var lastError: Error?

        for attempt in 1...configuration.maxAttempts {
            do {
                // Check for cancellation
                try Task.checkCancellation()

                let value = try await operation()

                return RetryResult(
                    value: value,
                    attempts: attempt,
                    totalDuration: Date().timeIntervalSince(startTime)
                )
            } catch is CancellationError {
                throw RetryError.cancelled
            } catch {
                lastError = error

                // Check if error is retryable
                guard isRetryable(error) else {
                    throw RetryError.nonRetryableError(error)
                }

                // Don't wait after the last attempt
                if attempt < configuration.maxAttempts {
                    let delay = calculateDelay(attempt: attempt, configuration: configuration)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        throw RetryError.maxAttemptsExceeded(lastError: lastError ?? NSError(domain: "NetworkRetry", code: -1))
    }

    /// Executes an async operation with retry logic and progress reporting
    /// - Parameters:
    ///   - configuration: Retry configuration
    ///   - onRetry: Called before each retry with attempt number and delay
    ///   - operation: The async operation to retry
    /// - Returns: RetryResult containing the value and retry statistics
    static func execute<T>(
        configuration: RetryConfiguration = .default,
        onRetry: @escaping (Int, TimeInterval) async -> Void,
        operation: @escaping () async throws -> T
    ) async throws -> RetryResult<T> {
        let startTime = Date()
        var lastError: Error?

        for attempt in 1...configuration.maxAttempts {
            do {
                try Task.checkCancellation()

                let value = try await operation()

                return RetryResult(
                    value: value,
                    attempts: attempt,
                    totalDuration: Date().timeIntervalSince(startTime)
                )
            } catch is CancellationError {
                throw RetryError.cancelled
            } catch {
                lastError = error

                guard isRetryable(error) else {
                    throw RetryError.nonRetryableError(error)
                }

                if attempt < configuration.maxAttempts {
                    let delay = calculateDelay(attempt: attempt, configuration: configuration)
                    await onRetry(attempt, delay)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        throw RetryError.maxAttemptsExceeded(lastError: lastError ?? NSError(domain: "NetworkRetry", code: -1))
    }
}

/// Protocol for errors that contain HTTP status codes
protocol HTTPStatusError: Error {
    var statusCode: Int { get }
}

// MARK: - Extension for common API errors

extension GuestyError: HTTPStatusError {
    var statusCode: Int {
        switch self {
        case .authenticationFailed(let code):
            return code
        case .requestFailed(let code):
            return code
        default:
            return 0
        }
    }
}

extension StripeError: HTTPStatusError {
    var statusCode: Int {
        switch self {
        case .requestFailed(let code):
            return code
        case .invalidCredentials:
            return 401
        case .insufficientPermissions:
            return 403
        default:
            return 0
        }
    }
}
