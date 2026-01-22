import CryptoKit
import Foundation
import Testing

@testable import DeltaDoreClient

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@Test func parseChallenge() throws {
    let header = "Digest realm=\"ServiceMedia\", nonce=\"abc123\", qop=\"auth\", opaque=\"xyz\""
    let challenge = try DigestChallenge.parse(from: header)

    #expect(challenge.realm == "ServiceMedia")
    #expect(challenge.nonce == "abc123")
    #expect(challenge.qop == "auth")
    #expect(challenge.opaque == "xyz")
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@Test func authorizationHeaderUsesAuthQopAndExpectedResponse() throws {
    let challenge = DigestChallenge(
        realm: "protected area",
        nonce: "nonce-value",
        qop: "auth,auth-int",
        opaque: nil,
        algorithm: nil
    )
    let randomBytes: @Sendable (Int) -> [UInt8] = { count in
        let bytes = Array(0..<16).map { UInt8($0) }
        return Array(bytes.prefix(count))
    }

    let header = try DigestAuthorizationBuilder.build(
        challenge: challenge,
        username: "user",
        password: "pass",
        method: "GET",
        uri: "/mediation/client?mac=AA:BB&appli=1",
        randomBytes: randomBytes
    )

    let cnonce = "000102030405060708090a0b0c0d0e0f"
    let ha1 = md5Hex("user:protected area:pass")
    let ha2 = md5Hex("GET:/mediation/client?mac=AA:BB&appli=1")
    let expected = md5Hex("\(ha1):nonce-value:00000001:\(cnonce):auth:\(ha2)")

    #expect(header.hasPrefix("Digest "))
    #expect(header.contains("username=\"user\""))
    #expect(header.contains("realm=\"protected area\""))
    #expect(header.contains("qop=auth"))
    #expect(header.contains("nc=00000001"))
    #expect(header.contains("cnonce=\"\(cnonce)\""))
    #expect(header.contains("response=\"\(expected)\""))
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@Test func unsupportedAlgorithmThrows() {
    let challenge = DigestChallenge(
        realm: "ServiceMedia",
        nonce: "nonce",
        qop: "auth",
        opaque: nil,
        algorithm: "SHA-256"
    )

    let randomBytes: @Sendable (Int) -> [UInt8] = { _ in [0] }
    #expect(throws: TydomConnection.ConnectionError.unsupportedAlgorithm("SHA-256")) {
        _ = try DigestAuthorizationBuilder.build(
            challenge: challenge,
            username: "user",
            password: "pass",
            method: "GET",
            uri: "/",
            randomBytes: randomBytes
        )
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@Test func unsupportedQopThrows() {
    let challenge = DigestChallenge(
        realm: "ServiceMedia",
        nonce: "nonce",
        qop: "auth-int",
        opaque: nil,
        algorithm: nil
    )

    let randomBytes: @Sendable (Int) -> [UInt8] = { _ in [0] }
    #expect(throws: TydomConnection.ConnectionError.unsupportedQop("auth-int")) {
        _ = try DigestAuthorizationBuilder.build(
            challenge: challenge,
            username: "user",
            password: "pass",
            method: "GET",
            uri: "/",
            randomBytes: randomBytes
        )
    }
}

private func md5Hex(_ string: String) -> String {
    let digest = Insecure.MD5.hash(data: Data(string.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}
