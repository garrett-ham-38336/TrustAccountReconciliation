import Foundation
import Security
import CryptoKit

/// Certificate pinning configuration for API services
/// Provides protection against man-in-the-middle attacks by validating server certificates
class CertificatePinningDelegate: NSObject, URLSessionDelegate {

    /// Pinned certificate hashes (SHA-256 of SubjectPublicKeyInfo)
    /// These should be updated when certificates are rotated
    private let pinnedHashes: [String: Set<String>]

    /// Whether to allow fallback to system trust when pins don't match
    /// Set to false in production for strict pinning
    private let allowSystemTrustFallback: Bool

    /// Domains that should be pinned
    private let pinnedDomains: Set<String>

    init(pinnedHashes: [String: Set<String>], allowSystemTrustFallback: Bool = false) {
        self.pinnedHashes = pinnedHashes
        self.allowSystemTrustFallback = allowSystemTrustFallback
        self.pinnedDomains = Set(pinnedHashes.keys)
        super.init()
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host

        // Check if this domain should be pinned
        guard shouldPinDomain(host) else {
            // Not a pinned domain, use default handling
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // First, perform standard certificate validation
        var error: CFError?
        let isValid = SecTrustEvaluateWithError(serverTrust, &error)

        guard isValid else {
            DebugLogger.shared.log("Certificate validation failed for \(host): \(error?.localizedDescription ?? "Unknown error")", prefix: "SECURITY")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Get the certificate chain
        guard let certificateChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
              !certificateChain.isEmpty else {
            DebugLogger.shared.log("No certificates in chain for \(host)", prefix: "SECURITY")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Check if any certificate in the chain matches our pins
        let matchingDomain = pinnedDomains.first { host.hasSuffix($0) || host == $0 }
        guard let domain = matchingDomain,
              let expectedHashes = pinnedHashes[domain] else {
            if allowSystemTrustFallback {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
            return
        }

        // Check each certificate in the chain
        for certificate in certificateChain {
            if let publicKeyHash = getPublicKeyHash(for: certificate) {
                if expectedHashes.contains(publicKeyHash) {
                    // Pin matched!
                    DebugLogger.shared.log("Certificate pin matched for \(host)", prefix: "SECURITY")
                    completionHandler(.useCredential, URLCredential(trust: serverTrust))
                    return
                }
            }
        }

        // No pin matched
        DebugLogger.shared.log("Certificate pin mismatch for \(host). Expected one of: \(expectedHashes)", prefix: "SECURITY")

        if allowSystemTrustFallback {
            DebugLogger.shared.log("Falling back to system trust for \(host)", prefix: "SECURITY")
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    /// Checks if a domain should have certificate pinning applied
    private func shouldPinDomain(_ host: String) -> Bool {
        for domain in pinnedDomains {
            if host == domain || host.hasSuffix("." + domain) {
                return true
            }
        }
        return false
    }

    /// Extracts the SHA-256 hash of the SubjectPublicKeyInfo from a certificate
    private func getPublicKeyHash(for certificate: SecCertificate) -> String? {
        guard let publicKey = SecCertificateCopyKey(certificate) else {
            return nil
        }

        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            return nil
        }

        // Hash the public key data
        let hash = SHA256.hash(data: publicKeyData)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Pinned Certificate Configuration

/// Configuration for certificate pinning
struct CertificatePinningConfiguration {
    /// Stripe API certificate pins
    /// These are the SHA-256 hashes of Stripe's public keys
    /// Note: These should be updated when Stripe rotates their certificates
    static let stripePins: Set<String> = [
        // Stripe uses multiple certificates - add actual hashes here
        // To get the hash, run:
        // openssl s_client -connect api.stripe.com:443 2>/dev/null | openssl x509 -pubkey -noout | openssl pkey -pubin -outform DER | openssl dgst -sha256 -hex
        "placeholder_stripe_pin_1",
        "placeholder_stripe_pin_2"
    ]

    /// Guesty API certificate pins
    static let guestyPins: Set<String> = [
        // Guesty certificate hashes
        // To get the hash, run:
        // openssl s_client -connect open-api.guesty.com:443 2>/dev/null | openssl x509 -pubkey -noout | openssl pkey -pubin -outform DER | openssl dgst -sha256 -hex
        "placeholder_guesty_pin_1",
        "placeholder_guesty_pin_2"
    ]

    /// Creates the default pinning configuration
    static func createDefaultConfiguration(strictMode: Bool = false) -> CertificatePinningDelegate {
        let pins: [String: Set<String>] = [
            "api.stripe.com": stripePins,
            "open-api.guesty.com": guestyPins
        ]

        return CertificatePinningDelegate(
            pinnedHashes: pins,
            allowSystemTrustFallback: !strictMode
        )
    }
}

// MARK: - Certificate Pin Updater

/// Utility for fetching and updating certificate pins
class CertificatePinUpdater {

    /// Fetches the current certificate hash for a domain
    /// Use this to get initial pins or verify current pins
    static func fetchCertificateHash(for domain: String, port: Int = 443) async -> String? {
        let url = URL(string: "https://\(domain)")!

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"

        // Create a session that captures the certificate
        let captureDelegate = CertificateCaptureDelegate()
        let session = URLSession(configuration: .ephemeral, delegate: captureDelegate, delegateQueue: nil)

        do {
            let _ = try await session.data(for: request)
            return captureDelegate.capturedHash
        } catch {
            DebugLogger.shared.log("Failed to fetch certificate for \(domain): \(error)", prefix: "SECURITY")
            return nil
        }
    }

    /// Logs current certificate hashes for all pinned domains
    /// Useful for updating pins during certificate rotation
    static func logCurrentCertificateHashes() async {
        let domains = ["api.stripe.com", "open-api.guesty.com"]

        DebugLogger.shared.log("Fetching current certificate hashes...", prefix: "SECURITY")

        for domain in domains {
            if let hash = await fetchCertificateHash(for: domain) {
                DebugLogger.shared.log("\(domain): \(hash)", prefix: "SECURITY")
            } else {
                DebugLogger.shared.log("\(domain): Failed to fetch certificate", prefix: "SECURITY")
            }
        }
    }
}

/// Delegate that captures certificate hashes for pin generation
private class CertificateCaptureDelegate: NSObject, URLSessionDelegate {
    var capturedHash: String?

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        if let certificateChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
           let certificate = certificateChain.first,
           let publicKey = SecCertificateCopyKey(certificate),
           let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? {
            let hash = SHA256.hash(data: publicKeyData)
            capturedHash = hash.map { String(format: "%02x", $0) }.joined()
        }

        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}

// MARK: - URLSession Extension for Pinned Sessions

extension URLSession {
    /// Creates a URLSession with certificate pinning enabled
    /// - Parameters:
    ///   - configuration: The session configuration to use
    ///   - strictMode: When true, connections fail if pins don't match. When false, falls back to system trust.
    /// - Returns: A URLSession configured with certificate pinning
    static func pinnedSession(
        configuration: URLSessionConfiguration = .default,
        strictMode: Bool = false
    ) -> URLSession {
        let delegate = CertificatePinningConfiguration.createDefaultConfiguration(strictMode: strictMode)
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }
}
