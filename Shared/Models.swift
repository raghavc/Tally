import Foundation

struct Batch: Codable, Identifiable {
    let id: Int64?
    let text: String
    let appContext: String?
    let wpm: Double?
    let backspaceRate: Double?
    let timestamp: String  // ISO 8601
    let locale: String

    enum CodingKeys: String, CodingKey {
        case id, text
        case appContext = "app_context"
        case wpm
        case backspaceRate = "backspace_rate"
        case timestamp = "ts"
        case locale
    }
}

struct IngestRequest: Codable {
    let userId: String
    let batches: [Batch]
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case batches
    }
}

struct IngestResponse: Codable {
    let accepted: Int
    let tokensCounted: Int
    enum CodingKeys: String, CodingKey {
        case accepted
        case tokensCounted = "tokens_counted"
    }
}

struct EarningsResponse: Codable {
    let tokenCount: Int
    let balance: Double
    let lifetimeEarnings: Double
    let payRate: Double
    let payoutHistory: [PayoutRecord]
    enum CodingKeys: String, CodingKey {
        case tokenCount = "token_count"
        case balance
        case lifetimeEarnings = "lifetime_earnings"
        case payRate = "pay_rate"
        case payoutHistory = "payout_history"
    }
}

struct PayoutRecord: Codable, Identifiable {
    var id: String { payoutId ?? UUID().uuidString }
    let amount: Double
    let status: String
    let requestedAt: String?
    let payoutId: String?
    enum CodingKeys: String, CodingKey {
        case amount, status
        case requestedAt = "requested_at"
        case payoutId = "payout_id"
    }
}

struct ExportResponse: Codable {
    let userId: String
    let batches: [Batch]
    let earnings: EarningsResponse
    let exportedAt: String
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case batches, earnings
        case exportedAt = "exported_at"
    }
}

struct PayoutRequestBody: Codable {
    let amount: Double?
}

struct PayoutResponse: Codable {
    let status: String
    let amount: Double
    let payoutId: String?
    enum CodingKeys: String, CodingKey {
        case status, amount
        case payoutId = "payout_id"
    }
}

struct DeleteResponse: Codable {
    let deleted: Bool
    let message: String?
}

struct AuthTokenRequest: Codable {
    let userId: String
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
    }
}

struct AuthTokenResponse: Codable {
    let token: String
    let userId: String
    enum CodingKeys: String, CodingKey {
        case token
        case userId = "user_id"
    }
}
