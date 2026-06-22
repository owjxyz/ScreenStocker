import Foundation
import XCTest

final class TossInvestMarketDataClientCacheTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        MockTossInvestURLProtocol.requestCounts = [:]
        MockTossInvestURLProtocol.candle1mResponses = []
        MockTossInvestURLProtocol.candle1dResponse = nil
    }

    func testIntradaySeriesUsesCachedMarketDataAfterInitialBackfill() async throws {
        let defaults = UserDefaults(suiteName: "com.tasokiii.ScreenStocker.tests.client.\(UUID().uuidString)")!
        let cacheStore = StockChartSeriesCacheStore(defaults: defaults)
        let session = Self.makeSession()
        let marketTimeZone = TimeZone(identifier: "Asia/Seoul")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = marketTimeZone
        let today = calendar.startOfDay(for: Date())
        let client = TossInvestMarketDataClient(
            credentialsStore: StubCredentialsStore(credentials: TossInvestCredentials(apiKey: "key", secretKey: "secret")),
            session: session,
            chartSeriesCacheStore: cacheStore
        )

        MockTossInvestURLProtocol.candle1mResponses = [
            Self.makeCandlePageData(
                candles: Self.candles(
                    [
                        calendar.date(byAdding: .hour, value: 10, to: today)!,
                        calendar.date(byAdding: .hour, value: 10, to: today)!.addingTimeInterval(10 * 60),
                        calendar.date(byAdding: .hour, value: 10, to: today)!.addingTimeInterval(20 * 60)
                    ]
                ),
                nextBefore: calendar.date(byAdding: .hour, value: 10, to: today)!.addingTimeInterval(-10 * 60)
            ),
            Self.makeCandlePageData(
                candles: Self.candles(
                    [
                        calendar.date(byAdding: .hour, value: 9, to: today)!.addingTimeInterval(20 * 60),
                        calendar.date(byAdding: .hour, value: 9, to: today)!.addingTimeInterval(30 * 60),
                        calendar.date(byAdding: .hour, value: 9, to: today)!.addingTimeInterval(40 * 60)
                    ]
                ),
                nextBefore: calendar.date(byAdding: .hour, value: 8, to: today)!.addingTimeInterval(50 * 60)
            ),
            Self.makeCandlePageData(
                candles: Self.candles(
                    [
                        calendar.date(byAdding: .hour, value: 7, to: today)!.addingTimeInterval(40 * 60),
                        calendar.date(byAdding: .hour, value: 7, to: today)!.addingTimeInterval(50 * 60),
                        calendar.date(byAdding: .hour, value: 8, to: today)!
                    ]
                ),
                nextBefore: nil
            ),
            Self.makeCandlePageData(
                candles: Self.candles(
                    [
                        calendar.date(byAdding: .hour, value: 10, to: today)!,
                        calendar.date(byAdding: .hour, value: 10, to: today)!.addingTimeInterval(10 * 60),
                        calendar.date(byAdding: .hour, value: 10, to: today)!.addingTimeInterval(20 * 60)
                    ]
                ),
                nextBefore: calendar.date(byAdding: .hour, value: 10, to: today)!.addingTimeInterval(-10 * 60)
            )
        ]
        MockTossInvestURLProtocol.candle1dResponse = Self.makeDailyCandlePageData()

        let firstSnapshot = try await client.snapshot(for: "005930")
        let secondSnapshot = try await client.snapshot(for: "005930")

        XCTAssertFalse(firstSnapshot.series.points.isEmpty)
        XCTAssertEqual(firstSnapshot.series.points.count, secondSnapshot.series.points.count)
        XCTAssertEqual(MockTossInvestURLProtocol.requestCounts["1m"], 4)
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockTossInvestURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func makeCandlePageData(candles: [[String: String]], nextBefore: Date?) -> Data {
        var result: [String: Any] = ["candles": candles]
        if let nextBefore {
            result["nextBefore"] = isoFormatter.string(from: nextBefore)
        }
        return try! JSONSerialization.data(withJSONObject: ["result": result], options: [])
    }

    private static func makeDailyCandlePageData() -> Data {
        let candles = Self.candles(
            [
                Date(timeIntervalSince1970: 0),
                Date(timeIntervalSince1970: -86_400)
            ],
            closePrice: ["69000", "68000"]
        )
        return try! JSONSerialization.data(withJSONObject: ["result": ["candles": candles]], options: [])
    }

    private static func candles(_ timestamps: [Date], closePrice: [String]? = nil) -> [[String: String]] {
        timestamps.enumerated().map { index, timestamp in
            [
                "timestamp": isoFormatter.string(from: timestamp),
                "openPrice": "100",
                "highPrice": "101",
                "lowPrice": "99",
                "closePrice": closePrice?[safe: index] ?? "100",
                "market": "KRX",
                "exchange": "KRX",
                "venue": "KRX"
            ]
        }
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private struct StubCredentialsStore: TossInvestCredentialsProviding {
    let credentials: TossInvestCredentials?
}

private final class MockTossInvestURLProtocol: URLProtocol {
    static var requestCounts: [String: Int] = [:]
    static var candle1mResponses: [Data] = []
    static var candle1dResponse: Data?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let path = url.path
        let response: Data?

        switch path {
        case "/oauth2/token":
            response = Self.tokenResponse()
        case "/api/v1/stocks":
            response = Self.stockInfoResponse()
        case "/api/v1/prices":
            response = Self.priceResponse()
        case "/api/v1/candles":
            let interval = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "interval" })?
                .value
            if interval == "1m" {
                Self.requestCounts["1m", default: 0] += 1
                response = Self.candle1mResponses.isEmpty ? nil : Self.candle1mResponses.removeFirst()
            } else {
                response = Self.candle1dResponse
            }
        default:
            response = nil
        }

        guard let responseData = response else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func tokenResponse() -> Data {
        try! JSONSerialization.data(withJSONObject: ["access_token": "token"], options: [])
    }

    private static func stockInfoResponse() -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "result": [
                [
                    "symbol": "005930",
                    "name": "삼성전자",
                    "englishName": "Samsung Electronics",
                    "market": "KRX",
                    "status": "ACTIVE",
                    "currency": "KRW"
                ]
            ]
        ], options: [])
    }

    private static func priceResponse() -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "result": [
                [
                    "symbol": "005930",
                    "timestamp": "2024-06-22T10:59:00+09:00",
                    "lastPrice": "70000",
                    "currency": "KRW"
                ]
            ]
        ], options: [])
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
