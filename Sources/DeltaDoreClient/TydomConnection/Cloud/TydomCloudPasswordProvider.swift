import Foundation

enum TydomCloudPasswordProvider {
    struct Constants {
        static let mediationHost = "mediation.tydom.com"
        static let authURL = "https://deltadoreadb2ciot.b2clogin.com/deltadoreadb2ciot.onmicrosoft.com/v2.0/.well-known/openid-configuration?p=B2C_1_AccountProviderROPC_SignIn"
        static let authGrantType = "password"
        static let authClientId = "8782839f-3264-472a-ab87-4d4e23524da4"
        static let authScope = "openid profile offline_access https://deltadoreadb2ciot.onmicrosoft.com/iotapi/video_config https://deltadoreadb2ciot.onmicrosoft.com/iotapi/video_allowed https://deltadoreadb2ciot.onmicrosoft.com/iotapi/sites_management_allowed https://deltadoreadb2ciot.onmicrosoft.com/iotapi/sites_management_gateway_credentials https://deltadoreadb2ciot.onmicrosoft.com/iotapi/sites_management_camera_credentials https://deltadoreadb2ciot.onmicrosoft.com/iotapi/comptage_europe_collect_reader https://deltadoreadb2ciot.onmicrosoft.com/iotapi/comptage_europe_site_config_contributor https://deltadoreadb2ciot.onmicrosoft.com/iotapi/pilotage_allowed https://deltadoreadb2ciot.onmicrosoft.com/iotapi/consent_mgt_contributor https://deltadoreadb2ciot.onmicrosoft.com/iotapi/b2caccountprovider_manage_account https://deltadoreadb2ciot.onmicrosoft.com/iotapi/b2caccountprovider_allow_view_account https://deltadoreadb2ciot.onmicrosoft.com/iotapi/tydom_backend_allowed https://deltadoreadb2ciot.onmicrosoft.com/iotapi/websocket_remote_access https://deltadoreadb2ciot.onmicrosoft.com/iotapi/orkestrator_device https://deltadoreadb2ciot.onmicrosoft.com/iotapi/orkestrator_view https://deltadoreadb2ciot.onmicrosoft.com/iotapi/orkestrator_space https://deltadoreadb2ciot.onmicrosoft.com/iotapi/orkestrator_connector https://deltadoreadb2ciot.onmicrosoft.com/iotapi/orkestrator_endpoint https://deltadoreadb2ciot.onmicrosoft.com/iotapi/rule_management_allowed https://deltadoreadb2ciot.onmicrosoft.com/iotapi/collect_read_datas"
        static let sitesAPI = "https://prod.iotdeltadore.com/sitesmanagement/api/v1/sites?gateway_mac="
    }

    enum ProviderError: Error, Sendable {
        case invalidResponse
        case missingTokenEndpoint
        case missingAccessToken
        case gatewayNotFound
    }

    static func fetchGatewayPassword(
        email: String,
        password: String,
        mac: String,
        session: URLSession
    ) async throws -> String {
        let accessToken = try await fetchAccessToken(
            email: email,
            password: password,
            session: session
        )
        return try await fetchGatewayPasswordWithFallback(
            accessToken: accessToken,
            mac: mac,
            session: session
        )
    }

    static func fetchAccessToken(
        email: String,
        password: String,
        session: URLSession
    ) async throws -> String {
        let tokenEndpoint = try await fetchTokenEndpoint(session: session)
        return try await fetchAccessToken(
            tokenEndpoint: tokenEndpoint,
            email: email,
            password: password,
            session: session
        )
    }

    private static func fetchGatewayPasswordWithFallback(
        accessToken: String,
        mac: String,
        session: URLSession
    ) async throws -> String {
        let candidates = macCandidates(from: mac)
        var lastError: Error?
        for candidate in candidates {
            do {
                return try await fetchGatewayPassword(
                    accessToken: accessToken,
                    mac: candidate,
                    session: session
                )
            } catch ProviderError.gatewayNotFound {
                lastError = ProviderError.gatewayNotFound
                continue
            }
        }
        throw lastError ?? ProviderError.gatewayNotFound
    }

    private static func fetchTokenEndpoint(session: URLSession) async throws -> String {
        guard let url = URL(string: Constants.authURL) else { throw ProviderError.invalidResponse }
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw ProviderError.invalidResponse
        }
        let config = try JSONDecoder().decode(OpenIDConfig.self, from: data)
        guard !config.tokenEndpoint.isEmpty else { throw ProviderError.missingTokenEndpoint }
        return config.tokenEndpoint
    }

    private static func fetchAccessToken(
        tokenEndpoint: String,
        email: String,
        password: String,
        session: URLSession
    ) async throws -> String {
        guard let url = URL(string: tokenEndpoint) else { throw ProviderError.invalidResponse }
        var formData = MultipartFormData()
        formData.addField(name: "username", value: email)
        formData.addField(name: "password", value: password)
        formData.addField(name: "grant_type", value: Constants.authGrantType)
        formData.addField(name: "client_id", value: Constants.authClientId)
        formData.addField(name: "scope", value: Constants.authScope)

        let payload = formData.finalize()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = payload.data
        request.setValue(payload.contentType, forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw ProviderError.invalidResponse
        }
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard !tokenResponse.accessToken.isEmpty else { throw ProviderError.missingAccessToken }
        return tokenResponse.accessToken
    }

    private static func fetchGatewayPassword(
        accessToken: String,
        mac: String,
        session: URLSession
    ) async throws -> String {
        guard let url = URL(string: Constants.sitesAPI + mac) else { throw ProviderError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw ProviderError.invalidResponse
        }
        let sitesResponse = try JSONDecoder().decode(SitesResponse.self, from: data)
        let expectedMac = TydomMac.normalize(mac)
        guard let site = sitesResponse.sites.first(where: {
            guard let gatewayMac = $0.gateway?.mac else { return false }
            return TydomMac.normalize(gatewayMac) == expectedMac
        }),
              let password = site.gateway?.password else {
            throw ProviderError.gatewayNotFound
        }
        return password
    }

    private static func macCandidates(from mac: String) -> [String] {
        var candidates: [String] = []
        let trimmed = mac.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty == false {
            candidates.append(trimmed)
        }

        let normalized = TydomMac.normalize(trimmed)
        if normalized.isEmpty == false, normalized != trimmed {
            candidates.append(normalized)
        }

        if let colonized = TydomMac.colonize(normalized), colonized != trimmed {
            candidates.append(colonized)
        }

        return Array(NSOrderedSet(array: candidates)) as? [String] ?? candidates
    }

}

private struct OpenIDConfig: Decodable {
    let tokenEndpoint: String

    private enum CodingKeys: String, CodingKey {
        case tokenEndpoint = "token_endpoint"
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

private struct SitesResponse: Decodable {
    let sites: [Site]
}

private struct Site: Decodable {
    let gateway: Gateway?
}

private struct Gateway: Decodable {
    let mac: String
    let password: String
}

private struct MultipartFormData {
    private let boundary: String
    private var body = Data()

    init(boundary: String = "Boundary-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    mutating func addField(name: String, value: String) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        body.append("\(value)\r\n")
    }

    mutating func finalize() -> (data: Data, contentType: String) {
        body.append("--\(boundary)--\r\n")
        let contentType = "multipart/form-data; boundary=\(boundary)"
        return (body, contentType)
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
