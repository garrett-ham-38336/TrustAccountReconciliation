import Foundation
import os.log

/// Centralized debug logging with log rotation
final class DebugLogger {
    static let shared = DebugLogger()

    /// Maximum log file size in bytes (5 MB)
    private let maxLogSize: Int = 5 * 1024 * 1024

    /// Maximum number of backup log files to keep
    private let maxBackupFiles: Int = 3

    /// OSLog for system logging
    private let osLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "TrustAccountReconciliation", category: "Debug")

    /// File manager
    private let fileManager = FileManager.default

    /// Serial queue for thread-safe file operations
    private let logQueue = DispatchQueue(label: "com.trustaccounting.logger", qos: .utility)

    /// Date formatter for log entries
    private lazy var dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private init() {
        // Perform initial cleanup on app launch
        logQueue.async { [weak self] in
            self?.performCleanupIfNeeded()
        }
    }

    // MARK: - Log Directory

    private var logDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("TrustAccountReconciliation/Logs")

        // Ensure directory exists
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory
    }

    private var currentLogURL: URL {
        logDirectory.appendingPathComponent("debug.log")
    }

    // MARK: - Public Logging Methods

    /// Logs a debug message for Guesty API operations
    func logGuesty(_ message: String) {
        log(message, prefix: "GUESTY")
    }

    /// Logs a debug message for Stripe API operations
    func logStripe(_ message: String) {
        log(message, prefix: "STRIPE")
    }

    /// Logs a general debug message
    func log(_ message: String, prefix: String = "DEBUG") {
        let timestamp = dateFormatter.string(from: Date())
        let formattedMessage = "[\(timestamp)] [\(prefix)] \(message)"

        // Log to console and OSLog
        print(formattedMessage)
        os_log("%{public}@", log: osLog, type: .debug, formattedMessage)

        // Log to file asynchronously
        logQueue.async { [weak self] in
            self?.writeToFile(formattedMessage + "\n")
        }
    }

    /// Logs an error
    func logError(_ error: Error, context: String) {
        let message = "\(context): \(error.localizedDescription)"
        log(message, prefix: "ERROR")

        // Also log to OSLog at error level
        os_log("%{public}@", log: osLog, type: .error, message)
    }

    // MARK: - File Operations

    private func writeToFile(_ message: String) {
        let logURL = currentLogURL

        // Check if rotation is needed before writing
        rotateIfNeeded()

        // Write to file
        if let data = message.data(using: .utf8) {
            if fileManager.fileExists(atPath: logURL.path) {
                // Append to existing file
                if let fileHandle = try? FileHandle(forWritingTo: logURL) {
                    defer { try? fileHandle.close() }
                    try? fileHandle.seekToEnd()
                    try? fileHandle.write(contentsOf: data)
                }
            } else {
                // Create new file
                try? data.write(to: logURL, options: .atomic)
            }
        }
    }

    // MARK: - Log Rotation

    private func rotateIfNeeded() {
        let logURL = currentLogURL

        guard fileManager.fileExists(atPath: logURL.path) else { return }

        do {
            let attributes = try fileManager.attributesOfItem(atPath: logURL.path)
            let fileSize = attributes[.size] as? Int ?? 0

            if fileSize > maxLogSize {
                rotateLog()
            }
        } catch {
            // Ignore errors checking file size
        }
    }

    private func rotateLog() {
        let logURL = currentLogURL

        // Shift existing backup files
        for i in stride(from: maxBackupFiles - 1, through: 1, by: -1) {
            let oldBackup = logDirectory.appendingPathComponent("debug.\(i).log")
            let newBackup = logDirectory.appendingPathComponent("debug.\(i + 1).log")

            if fileManager.fileExists(atPath: newBackup.path) {
                try? fileManager.removeItem(at: newBackup)
            }
            if fileManager.fileExists(atPath: oldBackup.path) {
                try? fileManager.moveItem(at: oldBackup, to: newBackup)
            }
        }

        // Move current log to backup.1
        let firstBackup = logDirectory.appendingPathComponent("debug.1.log")
        if fileManager.fileExists(atPath: firstBackup.path) {
            try? fileManager.removeItem(at: firstBackup)
        }
        try? fileManager.moveItem(at: logURL, to: firstBackup)

        // Log rotation event
        let message = "--- Log rotated at \(dateFormatter.string(from: Date())) ---\n"
        try? message.data(using: .utf8)?.write(to: logURL, options: .atomic)
    }

    // MARK: - Cleanup

    private func performCleanupIfNeeded() {
        // Remove backup files older than 7 days
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!

        do {
            let contents = try fileManager.contentsOfDirectory(at: logDirectory, includingPropertiesForKeys: [.contentModificationDateKey])

            for url in contents {
                if url.pathExtension == "log" {
                    let attributes = try url.resourceValues(forKeys: [.contentModificationDateKey])
                    if let modDate = attributes.contentModificationDate, modDate < cutoffDate {
                        try fileManager.removeItem(at: url)
                    }
                }
            }
        } catch {
            // Ignore cleanup errors
        }

        // Also remove old backup files beyond the limit
        for i in (maxBackupFiles + 1)...10 {
            let backupURL = logDirectory.appendingPathComponent("debug.\(i).log")
            try? fileManager.removeItem(at: backupURL)
        }
    }

    /// Manually triggers cleanup and rotation check
    func performMaintenance() {
        logQueue.async { [weak self] in
            self?.performCleanupIfNeeded()
            self?.rotateIfNeeded()
        }
    }

    // MARK: - Log Access

    /// Returns the current log file contents
    func getCurrentLogContents() -> String? {
        try? String(contentsOf: currentLogURL, encoding: .utf8)
    }

    /// Returns the URL of the log directory for export
    func getLogDirectoryURL() -> URL {
        logDirectory
    }

    /// Clears all log files
    func clearAllLogs() {
        logQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                let contents = try self.fileManager.contentsOfDirectory(at: self.logDirectory, includingPropertiesForKeys: nil)
                for url in contents where url.pathExtension == "log" {
                    try self.fileManager.removeItem(at: url)
                }
            } catch {
                // Ignore errors
            }
        }
    }
}

// MARK: - Convenience Extension for Error Logging

extension Error {
    func logToDebug(context: String) {
        DebugLogger.shared.logError(self, context: context)
    }
}
