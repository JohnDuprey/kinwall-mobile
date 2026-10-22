import Foundation
import DeviceCheck
import CryptoKit

/// The private App Attest key stays in Apple's Secure Enclave. JavaScript receives its public
/// identifier and opaque proofs only; the gateway validates all proofs against the official app.
enum AppAttest {
    static var supported: Bool {
        Bundle.main.object(forInfoDictionaryKey: "KinwallAppAttest") as? Bool == true && DCAppAttestService.shared.isSupported
    }
    static func generateKey() async throws -> String {
        guard supported else { throw NSError(domain: "KinwallAppAttest", code: 1) }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            DCAppAttestService.shared.generateKey { key, error in
                if let key { continuation.resume(returning: key) }
                else { continuation.resume(throwing: error ?? NSError(domain: "KinwallAppAttest", code: 2)) }
            }
        }
    }
    static func proof(key: String, data: String, initial: Bool) async throws -> String {
        guard supported else { throw NSError(domain: "KinwallAppAttest", code: 1) }
        let hash = Data(SHA256.hash(data: Data(data.utf8)))
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let complete: @Sendable (Data?, Error?) -> Void = { proof, error in
                if let proof { continuation.resume(returning: proof.base64EncodedString()) }
                else { continuation.resume(throwing: error ?? NSError(domain: "KinwallAppAttest", code: 2)) }
            }
            if initial { DCAppAttestService.shared.attestKey(key, clientDataHash: hash, completionHandler: complete) }
            else { DCAppAttestService.shared.generateAssertion(key, clientDataHash: hash, completionHandler: complete) }
        }
    }
}
