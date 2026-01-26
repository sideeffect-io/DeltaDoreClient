import Foundation

public struct TydomCloudSitesProvider {
    struct Constants {
        static let siteAccessListAPI = "https://prod.iotdeltadore.com/sitesmanagement/api/v1/siteaccesslist"
    }

    public struct Site: Sendable, Equatable {
        public let id: String
        public let name: String
        public let gateways: [Gateway]
    }

    public struct Gateway: Sendable, Equatable {
        public let mac: String
        public let name: String?
    }

    public enum ProviderError: Error, Sendable {
        case invalidResponse
        case missingAccessToken
    }

    public static func fetchSites(
        email: String,
        password: String,
        session: URLSession
    ) async throws -> [Site] {
        let accessToken = try await TydomCloudPasswordProvider.fetchAccessToken(
            email: email,
            password: password,
            session: session
        )
        return try await fetchSites(accessToken: accessToken, session: session)
    }

    public static func fetchSites(
        accessToken: String,
        session: URLSession
    ) async throws -> [Site] {
        guard let url = URL(string: Constants.siteAccessListAPI) else { throw ProviderError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw ProviderError.invalidResponse
        }
        let decoded = try JSONDecoder().decode(SiteAccessListResponse.self, from: data)
        return decoded.sites.map { site in
            Site(
                id: site.id,
                name: site.name,
                gateways: site.gateways.map { gateway in
                    Gateway(mac: TydomMac.normalize(gateway.mac), name: gateway.name)
                }
            )
        }
    }
}

private struct SiteAccessListResponse: Decodable {
    let sites: [SiteAccess]
}

private struct SiteAccess: Decodable {
    let id: String
    let name: String
    let gateways: [GatewayAccess]
}

private struct GatewayAccess: Decodable {
    let mac: String
    let name: String?
}
