import Foundation

actor APIClient {

    static let shared = APIClient()

    var baseURL = "http://localhost:8000"

    // MARK: - Errors

    enum APIError: LocalizedError {
        case invalidURL
        case httpError(statusCode: Int, data: Data)
        case decodingError(Error)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid URL"
            case .httpError(let statusCode, _):
                return "HTTP error \(statusCode)"
            case .decodingError(let error):
                return "Decoding error: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Private Request Helper

    private func request<T: Decodable>(
        _ method: String,
        path: String,
        body: (any Encodable)? = nil,
        token: String? = nil
    ) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = token {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            let encoder = JSONEncoder()
            urlRequest.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.httpError(statusCode: -1, data: data)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode, data: data)
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Public Methods

    func authenticate(userId: String) async throws -> AuthTokenResponse {
        let body = AuthTokenRequest(userId: userId)
        return try await request("POST", path: "/auth/token", body: body)
    }

    func postIngest(batches: [Batch], userId: String, token: String) async throws -> IngestResponse {
        let body = IngestRequest(userId: userId, batches: batches)
        return try await request("POST", path: "/ingest", body: body, token: token)
    }

    func getEarnings(token: String) async throws -> EarningsResponse {
        return try await request("GET", path: "/me/earnings", token: token)
    }

    func exportData(token: String) async throws -> ExportResponse {
        return try await request("GET", path: "/me/export", token: token)
    }

    func deleteData(token: String) async throws -> DeleteResponse {
        return try await request("POST", path: "/me/delete", token: token)
    }

    func requestPayout(amount: Double?, token: String) async throws -> PayoutResponse {
        let body = PayoutRequestBody(amount: amount)
        return try await request("POST", path: "/payouts/request", body: body, token: token)
    }
}
