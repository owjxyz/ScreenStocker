import Foundation
import XCTest

final class TossInvestMarketDataClientCacheTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        MockTossInvestURLProtocol.requestCounts = [:]
        MockTossInvestURLProtocol.candle1mResponses = []
        MockTossInvestURLProtocol.candle1dResponse = nil
        MockTossInvestURLProtocol.priceTimestamps = []
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
        XCTAssertEqual(MockTossInvestURLProtocol.requestCounts["1m"], 3)
    }

    func testIntradaySeriesFetchesNewCandlesWhenQuoteIsNewerThanCachedGraph() async throws {
        let defaults = UserDefaults(suiteName: "com.tasokiii.ScreenStocker.tests.client.\(UUID().uuidString)")!
        let cacheStore = StockChartSeriesCacheStore(defaults: defaults)
        let session = Self.makeSession()
        let marketTimeZone = TimeZone(identifier: "Asia/Seoul")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = marketTimeZone
        let today = calendar.startOfDay(for: Date())
        let ten = calendar.date(byAdding: .hour, value: 10, to: today)!
        let tenTen = ten.addingTimeInterval(10 * 60)
        let tenTwenty = ten.addingTimeInterval(20 * 60)
        let tenThirty = ten.addingTimeInterval(30 * 60)
        let client = TossInvestMarketDataClient(
            credentialsStore: StubCredentialsStore(credentials: TossInvestCredentials(apiKey: "key", secretKey: "secret")),
            session: session,
            chartSeriesCacheStore: cacheStore
        )

        MockTossInvestURLProtocol.priceTimestamps = [
            Self.isoFormatter.string(from: tenTwenty),
            Self.isoFormatter.string(from: tenThirty)
        ]
        MockTossInvestURLProtocol.candle1mResponses = [
            Self.makeCandlePageData(
                candles: Self.candles([ten, tenTen, tenTwenty]),
                nextBefore: ten.addingTimeInterval(-10 * 60)
            ),
            Self.makeCandlePageData(
                candles: Self.candles([
                    calendar.date(byAdding: .hour, value: 9, to: today)!.addingTimeInterval(20 * 60),
                    calendar.date(byAdding: .hour, value: 9, to: today)!.addingTimeInterval(30 * 60),
                    calendar.date(byAdding: .hour, value: 9, to: today)!.addingTimeInterval(40 * 60)
                ]),
                nextBefore: calendar.date(byAdding: .hour, value: 8, to: today)!.addingTimeInterval(50 * 60)
            ),
            Self.makeCandlePageData(
                candles: Self.candles([
                    calendar.date(byAdding: .hour, value: 7, to: today)!.addingTimeInterval(40 * 60),
                    calendar.date(byAdding: .hour, value: 7, to: today)!.addingTimeInterval(50 * 60),
                    calendar.date(byAdding: .hour, value: 8, to: today)!
                ]),
                nextBefore: nil
            ),
            Self.makeCandlePageData(
                candles: Self.candles([tenTen, tenTwenty, tenThirty]),
                nextBefore: ten
            )
        ]
        MockTossInvestURLProtocol.candle1dResponse = Self.makeDailyCandlePageData()

        let firstSnapshot = try await client.snapshot(for: "005930")
        let secondSnapshot = try await client.snapshot(for: "005930")

        XCTAssertFalse(firstSnapshot.series.points.isEmpty)
        XCTAssertGreaterThan(secondSnapshot.series.points.count, firstSnapshot.series.points.count)
        XCTAssertEqual(secondSnapshot.series.points.last?.date, tenThirty)
        XCTAssertEqual(MockTossInvestURLProtocol.requestCounts["1m"], 4)
    }

    func testKRXIntradaySeriesMatchesTossTenMinuteChartBoundaries() async throws {
        let defaults = UserDefaults(suiteName: "com.tasokiii.ScreenStocker.tests.client.\(UUID().uuidString)")!
        let cacheStore = StockChartSeriesCacheStore(defaults: defaults)
        let session = Self.makeSession()
        let marketTimeZone = TimeZone(identifier: "Asia/Seoul")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = marketTimeZone
        let today = calendar.startOfDay(for: Date())
        let sessionStart = calendar.date(byAdding: .hour, value: 8, to: today)!
        let client = TossInvestMarketDataClient(
            credentialsStore: StubCredentialsStore(credentials: TossInvestCredentials(apiKey: "key", secretKey: "secret")),
            session: session,
            chartSeriesCacheStore: cacheStore
        )
        let sessionMinuteTimestamps = Self.krxSessionMinuteTimestamps(on: today, calendar: calendar)
            .sorted(by: >)
        MockTossInvestURLProtocol.candle1mResponses = stride(from: 0, to: sessionMinuteTimestamps.count, by: 200).map { offset in
            let pageTimestamps = Array(sessionMinuteTimestamps[offset..<min(offset + 200, sessionMinuteTimestamps.count)])
            let nextBefore = pageTimestamps.last.map { $0.addingTimeInterval(-1) }
            return Self.makeCandlePageData(
                candles: Self.candles(pageTimestamps),
                nextBefore: offset + 200 < sessionMinuteTimestamps.count ? nextBefore : nil
            )
        }
        MockTossInvestURLProtocol.candle1dResponse = Self.makeDailyCandlePageData()

        let snapshot = try await client.snapshot(for: "005930")
        let pointTimes = snapshot.series.points.map(\.date)

        XCTAssertEqual(pointTimes.count, 72)
        XCTAssertEqual(pointTimes.first, sessionStart.addingTimeInterval(10 * 60))
        XCTAssertEqual(pointTimes.last, sessionStart.addingTimeInterval(12 * 60 * 60))
        XCTAssertFalse(pointTimes.contains(sessionStart))
    }

    func testUSSnapshotReturnsQuoteWhenIntradayCandlesAreUnavailable() async throws {
        let defaults = UserDefaults(suiteName: "com.tasokiii.ScreenStocker.tests.client.\(UUID().uuidString)")!
        let cacheStore = StockChartSeriesCacheStore(defaults: defaults)
        let session = Self.makeSession()
        let client = TossInvestMarketDataClient(
            credentialsStore: StubCredentialsStore(credentials: TossInvestCredentials(apiKey: "key", secretKey: "secret")),
            session: session,
            chartSeriesCacheStore: cacheStore
        )

        MockTossInvestURLProtocol.candle1mResponses = []
        MockTossInvestURLProtocol.candle1dResponse = Self.makeDailyCandlePageData()

        let snapshot = try await client.snapshot(for: "AAPL")

        XCTAssertEqual(snapshot.quote.symbol, "AAPL")
        XCTAssertEqual(snapshot.quote.exchangeLabel, "NASDAQ")
        XCTAssertEqual(snapshot.quote.price, Decimal(string: "212.45"))
        XCTAssertTrue(snapshot.series.points.isEmpty)
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

    private static func candles(
        _ timestamps: [Date],
        closePrice: [String]? = nil,
        market: String = "KRX",
        exchange: String = "KRX",
        venue: String = "KRX"
    ) -> [[String: String]] {
        timestamps.enumerated().map { index, timestamp in
            [
                "timestamp": isoFormatter.string(from: timestamp),
                "openPrice": "100",
                "highPrice": "101",
                "lowPrice": "99",
                "closePrice": closePrice?[safe: index] ?? "100",
                "market": market,
                "exchange": exchange,
                "venue": venue
            ]
        }
    }

    private static func krxSessionMinuteTimestamps(on dayStart: Date, calendar: Calendar) -> [Date] {
        var timestamps: [Date] = []
        appendMinuteTimestamps(
            to: &timestamps,
            dayStart: dayStart,
            calendar: calendar,
            startMinute: 8 * 60,
            endMinute: 8 * 60 + 50
        )
        appendMinuteTimestamps(
            to: &timestamps,
            dayStart: dayStart,
            calendar: calendar,
            startMinute: 9 * 60,
            endMinute: 15 * 60 + 30
        )
        appendMinuteTimestamps(
            to: &timestamps,
            dayStart: dayStart,
            calendar: calendar,
            startMinute: 15 * 60 + 40,
            endMinute: 20 * 60
        )
        return timestamps
    }

    private static func appendMinuteTimestamps(
        to timestamps: inout [Date],
        dayStart: Date,
        calendar: Calendar,
        startMinute: Int,
        endMinute: Int
    ) {
        for minuteOffset in startMinute...endMinute {
            guard let timestamp = calendar.date(byAdding: .minute, value: minuteOffset, to: dayStart) else {
                continue
            }
            timestamps.append(timestamp)
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
    static var priceTimestamps: [String] = []

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
            response = Self.stockInfoResponse(for: Self.requestedSymbol(from: url))
        case "/api/v1/prices":
            response = Self.priceResponse(for: Self.requestedSymbol(from: url))
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

    private static func stockInfoResponse(for symbol: String) -> Data {
        let isUSSymbol = StockSymbolInput.marketKind(for: symbol) == .us
        return try! JSONSerialization.data(withJSONObject: [
            "result": [
                [
                    "symbol": symbol,
                    "name": isUSSymbol ? "Apple" : "삼성전자",
                    "englishName": isUSSymbol ? "Apple" : "Samsung Electronics",
                    "market": isUSSymbol ? "NASDAQ" : "KRX",
                    "status": "ACTIVE",
                    "currency": isUSSymbol ? "USD" : "KRW"
                ]
            ]
        ], options: [])
    }

    private static func priceResponse(for symbol: String) -> Data {
        let isUSSymbol = StockSymbolInput.marketKind(for: symbol) == .us
        let timestamp = priceTimestamps.isEmpty
            ? (isUSSymbol ? "2026-06-22T20:00:00-04:00" : "2024-06-22T10:59:00+09:00")
            : priceTimestamps.removeFirst()
        return try! JSONSerialization.data(withJSONObject: [
            "result": [
                [
                    "symbol": symbol,
                    "timestamp": timestamp,
                    "lastPrice": isUSSymbol ? "212.45" : "70000",
                    "currency": isUSSymbol ? "USD" : "KRW"
                ]
            ]
        ], options: [])
    }

    private static func requestedSymbol(from url: URL) -> String {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "symbols" || $0.name == "symbol" })?
            .value?
            .split(separator: ",")
            .first
            .map(String.init) ?? "005930"
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
