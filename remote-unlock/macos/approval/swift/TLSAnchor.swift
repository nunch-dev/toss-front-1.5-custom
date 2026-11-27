import Foundation
import Security

// An explicitly supplied test/private CA still undergoes normal chain and host
// validation. No system trust-store changes or accept-any-certificate mode.
final class TLSAnchor: NSObject, URLSessionDelegate {
    let certificateDER: Data

    init(certificateDER: Data) {
        self.certificateDER = certificateDER
    }

    func urlSession(
        _ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let certificate = SecCertificateCreateWithData(nil, certificateDER as CFData),
              SecTrustSetAnchorCertificates(trust, [certificate] as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
              SecTrustEvaluateWithError(trust, nil) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
