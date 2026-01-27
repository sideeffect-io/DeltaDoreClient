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

    init(from decoder: Decoder) throws {
        var decodedSites: [SiteAccess]?
        let keyed = try? decoder.container(keyedBy: DynamicCodingKeys.self)
        if let keyed {
            decodedSites = decodedSites ?? (try? keyed.decode([SiteAccess].self, forKey: DynamicCodingKeys("sites")))
            decodedSites = decodedSites ?? (try? keyed.decode([SiteAccess].self, forKey: DynamicCodingKeys("siteAccessList")))
            if decodedSites == nil,
               let dataContainer = try? keyed.nestedContainer(
                   keyedBy: DynamicCodingKeys.self,
                   forKey: DynamicCodingKeys("data")
               ) {
                decodedSites = decodedSites ?? (try? dataContainer.decode([SiteAccess].self, forKey: DynamicCodingKeys("sites")))
                decodedSites = decodedSites ?? (try? dataContainer.decode([SiteAccess].self, forKey: DynamicCodingKeys("siteAccessList")))
            }
        }

        if decodedSites == nil {
            let single = try decoder.singleValueContainer()
            decodedSites = try? single.decode([SiteAccess].self)
        }

        if let decodedSites {
            self.sites = decodedSites
        } else {
            let context = DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Unsupported site access list response format."
            )
            throw DecodingError.dataCorrupted(context)
        }
    }
}

private struct DynamicCodingKeys: CodingKey, Hashable {
    var stringValue: String
    var intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
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
