import Foundation

/// Endpoint material is stored encoded so plain domains are not present as searchable strings.
/// This is obfuscation, not a substitute for TLS or server-side authorization.
enum EndpointVault {
    private static let licenseEncoded = "aHR0cHM6Ly9wcm94eXN5c3RlbS5vcmcvYXBpL3RycGMvYW5kcm9pZC52YWxpZGF0ZUtleQ=="
    private static let remoteEncoded = "aHR0cHM6Ly9vZ2lvc3JjLXJzMjVtazZmLm1hbnVzLnNwYWNl"
    private static let remoteConfigPathEncoded = "L2FwaS90cnBjL3JlbW90ZS5nZXRDb25maWc="

    static let licenseURLString = decode(licenseEncoded)
    static let remoteBaseURLString = decode(remoteEncoded)
    static let remoteConfigPath = decode(remoteConfigPathEncoded)
    static let licenseURL = URL(string: licenseURLString)!
    static let remoteBaseURL = URL(string: remoteBaseURLString)!

    private static func decode(_ value: String) -> String {
        guard let data = Data(base64Encoded: value), let decoded = String(data: data, encoding: .utf8) else {
            preconditionFailure("Endpoint configuration is invalid")
        }
        return decoded
    }
}

extension URL {
    var endpointSafeDescription: String { "<redacted-endpoint>" }
}
