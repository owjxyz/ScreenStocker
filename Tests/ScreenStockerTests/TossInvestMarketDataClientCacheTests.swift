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

    func testAccessTokenIsReusedAcrossRefreshes() async throws {
        let defaults = UserDefaults(suiteName: "com.tasokiii.ScreenStocker.tests.client.\(UUID().uuidString)")!
        let client = TossInvestMarketDataClient(
            credentialsStore: StubCredentialsStore(credentials: TossInvestCredentials(apiKey: "key", secretKey: "secret")),
            session: Self.makeSession(),
            chartSeriesCacheStore: StockChartSeriesCacheStore(defaults: defaults)
        )
        MockTossInvestURLProtocol.candle1dResponse = Self.makeDailyCandlePageData()

        _ = try await client.quotes(for: ["005930"])
        _ = try await client.quotes(for: ["005930"])

        XCTAssertEqual(MockTossInvestURLProtocol.requestCounts["token"], 1)
        XCTAssertEqual(MockTossInvestURLProtocol.requestCounts["prices"], 2)
    }

    func testSeparatedQuoteAndChartRefreshFetchesPricesOnce() async throws {
        let defaults = UserDefaults(suiteName: "com.tasokiii.ScreenStocker.tests.client.\(UUID().uuidString)")!
        let client = TossInvestMarketDataClient(
            credentialsStore: StubCredentialsStore(credentials: TossInvestCredentials(apiKey: "key", secretKey: "secret")),
            session: Self.makeSession(),
            chartSeriesCacheStore: StockChartSeriesCacheStore(defaults: defaults)
        )
        MockTossInvestURLProtocol.candle1dResponse = Self.makeDailyCandlePageData()
        MockTossInvestURLProtocol.candle1mResponses = [
            Self.makeCandlePageData(
                candles: Self.candles([Date(timeIntervalSince1970: 1_719_020_400)]),
                nextBefore: nil
            )
        ]

        let quotes = try await client.quotes(for: ["005930"])
        let series = await client.chartSeries(for: try XCTUnwrap(quotes["005930"]))

        XCTAssertFalse(series.points.isEmpty)
        XCTAssertEqual(MockTossInvestURLProtocol.requestCounts["token"], 1)
        XCTAssertEqual(MockTossInvestURLProtocol.requestCounts["stocks"], 1)
        XCTAssertEqual(MockTossInvestURLProtocol.requestCounts["prices"], 1)
    }

    func testChartSeriesUsesFreshCacheBeforeRequestingTokenOrCandles() async throws {
        let defaults = UserDefaults(suiteName: "com.tasokiii.ScreenStocker.tests.client.\(UUID().uuidString)")!
        let cacheStore = StockChartSeriesCacheStore(defaults: defaults)
        let timeZone = TimeZone(identifier: "Asia/Seoul")!
        let currentDate = Self.date(year: 2026, month: 6, day: 24, hour: 10, timeZone: timeZone)
        let dayIdentifier = StockChartSeriesCacheStore.dayIdentifier(for: currentDate, timeZone: timeZone)
        cacheStore.save(
            candles: [
                IntradayCandle(
                    timestamp: currentDate,
                    openPrice: 100,
                    highPrice: 101,
                    lowPrice: 99,
                    closePrice: 100,
                    market: "KRX",
                    exchange: "KRX",
                    venue: "KRX"
                )
            ],
            isComplete: true,
            for: "005930",
            dayIdentifier: dayIdentifier,
            timeZoneIdentifier: timeZone.identifier,
            referenceDate: currentDate
        )
        let client = TossInvestMarketDataClient(
            credentialsStore: StubCredentialsStore(credentials: TossInvestCredentials(apiKey: "key", secretKey: "secret")),
            session: Self.makeSession(),
            chartSeriesCacheStore: cacheStore,
            currentDate: { currentDate }
        )
        let quote = StockQuote(
            symbol: "005930",
            displayName: "Samsung Electronics",
            exchangeLabel: "KRX",
            price: 100,
            changePercent: 0,
            currency: "KRW",
            timestamp: currentDate
        )

        let series = await client.chartSeries(for: quote)

        XCTAssertFalse(series.points.isEmpty)
        XCTAssertNil(MockTossInvestURLProtocol.requestCounts["token"])
        XCTAssertNil(MockTossInvestURLProtocol.requestCounts["1m"])
    }

    func testQuotesReuseCachedDailyClosesWhenDailyCandleRequestFails() async throws {
        let defaults = UserDefaults(suiteName: "com.tasokiii.ScreenStocker.tests.client.\(UUID().uuidString)")!
        let cacheStore = StockChartSeriesCacheStore(defaults: defaults)
        let session = Self.makeSession()
        let timeZone = TimeZone(identifier: "Asia/Seoul")!
        let priceTimestamp = Self.date(year: 2026, month: 6, day: 24, hour: 10, timeZone: timeZone)
        let currentDay = Self.date(year: 2026, month: 6, day: 24, hour: 0, timeZone: timeZone)
        let previousDay = Self.date(year: 2026, month: 6, day: 23, hour: 0, timeZone: timeZone)
        let client = TossInvestMarketDataClient(
            credentialsStore: StubCredentialsStore(credentials: TossInvestCredentials(apiKey: "key", secretKey: "secret")),
            session: session,
            chartSeriesCacheStore: cacheStore
        )

        MockTossInvestURLProtocol.priceTimestamps = [
            Self.isoFormatter.string(from: priceTimestamp),
            Self.isoFormatter.string(from: priceTimestamp)
        ]
        MockTossInvestURLProtocol.candle1dResponse = Self.makeCandlePageData(
            candles: Self.candles(
                [currentDay, previousDay],
                closePrice: ["70000", "68000"]
            ),
            nextBefore: nil
        )

        let firstQuotes = try await client.quotes(for: ["005930"])
        MockTossInvestURLProtocol.candle1dResponse = nil
        let secondQuotes = try await client.quotes(for: ["005930"])

        XCTAssertEqual(firstQuotes["005930"]?.changePercent, secondQuotes["005930"]?.changePercent)
        XCTAssertNotNil(secondQuotes["005930"]?.changePercent)
    }

    func testIntradaySeriesUsesCachedMarketDataAfterInitialBackfill() async throws {
        let defaults = UserDefaults(suiteName: "com.tasokiii.ScreenStocker.tests.client.\(UUID().uuidString)")!
        let cacheStore = StockChartSeriesCacheStore(defaults: defaults)
        let session = Self.makeSession()
        let marketTimeZone = TimeZone(identifier: "Asia/Seoul")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = marketTimeZone
        let today = calendar.startOfDay(for: Date())
        let currentDate = calendar.date(byAdding: .hour, value: 10, to: today)!
            .addingTimeInterval(20 * 60)
        let client = TossInvestMarketDataClient(
            credentialsStore: StubCredentialsStore(credentials: TossInvestCredentials(apiKey: "key", secretKey: "secret")),
            session: session,
            chartSeriesCacheStore: cacheStore,
            currentDate: { currentDate }
        )
        MockTossInvestURLProtocol.priceTimestamps = [
            Self.isoFormatter.string(from: currentDate),
            Self.isoFormatter.string(from: currentDate)
        ]

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
        let eight = calendar.date(byAdding: .hour, value: 8, to: today)!
        let nine = calendar.date(byAdding: .hour, value: 9, to: today)!
        let ten = calendar.date(byAdding: .hour, value: 10, to: today)!
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
                candles: Self.candles((0...20).map { ten.addingTimeInterval(TimeInterval($0 * 60)) }),
                nextBefore: ten.addingTimeInterval(-60)
            ),
            Self.makeCandlePageData(
                candles: Self.candles((0...59).map { nine.addingTimeInterval(TimeInterval($0 * 60)) }),
                nextBefore: eight.addingTimeInterval(50 * 60)
            ),
            Self.makeCandlePageData(
                candles: Self.candles((0...50).map { eight.addingTimeInterval(TimeInterval($0 * 60)) }),
                nextBefore: nil
            ),
            Self.makeCandlePageData(
                candles: Self.candles((21...30).map { ten.addingTimeInterval(TimeInterval($0 * 60)) }),
                nextBefore: tenTwenty
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

    func testUSSnapshotUsesDayMarketSeriesDuringDayMarketHours() async throws {
        let defaults = UserDefaults(suiteName: "com.tasokiii.ScreenStocker.tests.client.\(UUID().uuidString)")!
        let cacheStore = StockChartSeriesCacheStore(defaults: defaults)
        let session = Self.makeSession()
        let timeZone = TimeZone(identifier: "America/New_York")!
        let sessionStart = Self.date(year: 2026, month: 1, day: 16, hour: 20, timeZone: timeZone)
        let currentDate = sessionStart.addingTimeInterval(60 * 60)
        let client = TossInvestMarketDataClient(
            credentialsStore: StubCredentialsStore(credentials: TossInvestCredentials(apiKey: "key", secretKey: "secret")),
            session: session,
            chartSeriesCacheStore: cacheStore,
            currentDate: { currentDate }
        )

        MockTossInvestURLProtocol.priceTimestamps = [
            Self.isoFormatter.string(from: currentDate)
        ]
        MockTossInvestURLProtocol.candle1mResponses = [
            Self.makeCandlePageData(
                candles: Self.candles(
                    [
                        sessionStart.addingTimeInterval(10 * 60),
                        sessionStart.addingTimeInterval(20 * 60),
                        sessionStart.addingTimeInterval(30 * 60)
                    ],
                    market: "NASDAQ",
                    exchange: "NASDAQ",
                    venue: "BLUE_OCEAN"
                ),
                nextBefore: nil
            )
        ]
        MockTossInvestURLProtocol.candle1dResponse = Self.makeDailyCandlePageData()

        let snapshot = try await client.snapshot(for: "AAPL")

        XCTAssertEqual(snapshot.series.sessionStart, sessionStart)
        XCTAssertEqual(snapshot.series.sessionEnd, sessionStart.addingTimeInterval(8 * 60 * 60))
        XCTAssertTrue(snapshot.series.sessionDividers.isEmpty)
        XCTAssertEqual(snapshot.series.points.first?.date, sessionStart.addingTimeInterval(10 * 60))
        XCTAssertEqual(snapshot.quote.exchangeLabel, "BLUE_OCEAN")
    }

    func testUSSnapshotUsesStandardSeriesOutsideDayMarketHours() async throws {
        let defaults = UserDefaults(suiteName: "com.tasokiii.ScreenStocker.tests.client.\(UUID().uuidString)")!
        let cacheStore = StockChartSeriesCacheStore(defaults: defaults)
        let session = Self.makeSession()
        let timeZone = TimeZone(identifier: "America/New_York")!
        let dayStart = Self.date(year: 2026, month: 1, day: 16, hour: 0, timeZone: timeZone)
        let extendedStart = Self.date(year: 2026, month: 1, day: 16, hour: 4, timeZone: timeZone)
        let regularOpen = Self.date(year: 2026, month: 1, day: 16, hour: 9, minute: 30, timeZone: timeZone)
        let regularClose = Self.date(year: 2026, month: 1, day: 16, hour: 16, timeZone: timeZone)
        let currentDate = Self.date(year: 2026, month: 1, day: 16, hour: 10, timeZone: timeZone)
        let client = TossInvestMarketDataClient(
            credentialsStore: StubCredentialsStore(credentials: TossInvestCredentials(apiKey: "key", secretKey: "secret")),
            session: session,
            chartSeriesCacheStore: cacheStore,
            currentDate: { currentDate }
        )

        MockTossInvestURLProtocol.priceTimestamps = [
            Self.isoFormatter.string(from: currentDate)
        ]
        MockTossInvestURLProtocol.candle1mResponses = [
            Self.makeCandlePageData(
                candles: Self.candles(
                    [
                        dayStart.addingTimeInterval(20 * 60 + 10 * 60),
                        extendedStart.addingTimeInterval(10 * 60),
                        regularOpen.addingTimeInterval(10 * 60)
                    ],
                    market: "NASDAQ",
                    exchange: "NASDAQ",
                    venue: "NASDAQ"
                ),
                nextBefore: nil
            )
        ]
        MockTossInvestURLProtocol.candle1dResponse = Self.makeDailyCandlePageData()

        let snapshot = try await client.snapshot(for: "AAPL")

        XCTAssertEqual(snapshot.series.sessionStart, extendedStart)
        XCTAssertEqual(snapshot.series.sessionEnd, Self.date(year: 2026, month: 1, day: 16, hour: 20, timeZone: timeZone))
        XCTAssertEqual(snapshot.series.sessionDividers, [regularOpen, regularClose])
        XCTAssertEqual(snapshot.series.points.first?.date, extendedStart.addingTimeInterval(10 * 60))
    }

    func testCompleteCacheBackfillsFiveMinuteIntradayGap() async throws {
        let defaults = UserDefaults(suiteName: "com.tasokiii.ScreenStocker.tests.client.\(UUID().uuidString)")!
        let cacheStore = StockChartSeriesCacheStore(defaults: defaults)
        let session = Self.makeSession()
        let timeZone = TimeZone(identifier: "America/New_York")!
        let extendedStart = Self.date(year: 2026, month: 1, day: 16, hour: 4, timeZone: timeZone)
        let currentDate = Self.date(year: 2026, month: 1, day: 16, hour: 4, minute: 30, timeZone: timeZone)
        let dayIdentifier = StockChartSeriesCacheStore.dayIdentifier(for: extendedStart, timeZone: timeZone)
        cacheStore.save(
            candles: [
                IntradayCandle(
                    timestamp: extendedStart.addingTimeInterval(10 * 60),
                    openPrice: 100,
                    highPrice: 101,
                    lowPrice: 99,
                    closePrice: 100,
                    market: "NASDAQ",
                    exchange: "NASDAQ",
                    venue: "NASDAQ"
                ),
                IntradayCandle(
                    timestamp: extendedStart.addingTimeInterval(16 * 60),
                    openPrice: 100,
                    highPrice: 101,
                    lowPrice: 99,
                    closePrice: 100,
                    market: "NASDAQ",
                    exchange: "NASDAQ",
                    venue: "NASDAQ"
                )
            ],
            isComplete: true,
            for: "AAPL",
            dayIdentifier: dayIdentifier,
            timeZoneIdentifier: timeZone.identifier,
            referenceDate: currentDate
        )
        let client = TossInvestMarketDataClient(
            credentialsStore: StubCredentialsStore(credentials: TossInvestCredentials(apiKey: "key", secretKey: "secret")),
            session: session,
            chartSeriesCacheStore: cacheStore,
            currentDate: { currentDate }
        )

        MockTossInvestURLProtocol.priceTimestamps = [
            Self.isoFormatter.string(from: currentDate)
        ]
        MockTossInvestURLProtocol.candle1mResponses = [
            Self.makeCandlePageData(
                candles: Self.candles(
                    [extendedStart.addingTimeInterval(30 * 60)],
                    market: "NASDAQ",
                    exchange: "NASDAQ",
                    venue: "NASDAQ"
                ),
                nextBefore: extendedStart.addingTimeInterval(29 * 60)
            ),
            Self.makeCandlePageData(
                candles: Self.candles(
                    (11...29).map { extendedStart.addingTimeInterval(TimeInterval($0 * 60)) },
                    market: "NASDAQ",
                    exchange: "NASDAQ",
                    venue: "NASDAQ"
                ),
                nextBefore: extendedStart.addingTimeInterval(10 * 60)
            ),
            Self.makeCandlePageData(
                candles: Self.candles(
                    (0...10).map { extendedStart.addingTimeInterval(TimeInterval($0 * 60)) },
                    market: "NASDAQ",
                    exchange: "NASDAQ",
                    venue: "NASDAQ"
                ),
                nextBefore: nil
            )
        ]
        MockTossInvestURLProtocol.candle1dResponse = Self.makeDailyCandlePageData()

        let snapshot = try await client.snapshot(for: "AAPL")
        let pointTimes = snapshot.series.points.map(\.date)
        let storedEntry = cacheStore.entry(
            for: "AAPL",
            dayIdentifier: dayIdentifier,
            timeZoneIdentifier: timeZone.identifier,
            referenceDate: currentDate
        )

        XCTAssertEqual(MockTossInvestURLProtocol.requestCounts["1m"], 3)
        XCTAssertEqual(pointTimes, [
            extendedStart.addingTimeInterval(10 * 60),
            extendedStart.addingTimeInterval(20 * 60),
            extendedStart.addingTimeInterval(30 * 60)
        ])
        XCTAssertEqual(storedEntry?.candles.count, 31)
        XCTAssertEqual(storedEntry?.isComplete, true)
    }

    func testCompleteKRXCacheBackfillsFiveMinuteIntradayGap() async throws {
        let defaults = UserDefaults(suiteName: "com.tasokiii.ScreenStocker.tests.client.\(UUID().uuidString)")!
        let cacheStore = StockChartSeriesCacheStore(defaults: defaults)
        let session = Self.makeSession()
        let timeZone = TimeZone(identifier: "Asia/Seoul")!
        let sessionStart = Self.date(year: 2026, month: 1, day: 16, hour: 8, timeZone: timeZone)
        let currentDate = Self.date(year: 2026, month: 1, day: 16, hour: 9, minute: 30, timeZone: timeZone)
        let dayIdentifier = StockChartSeriesCacheStore.dayIdentifier(for: sessionStart, timeZone: timeZone)
        cacheStore.save(
            candles: [
                IntradayCandle(
                    timestamp: sessionStart.addingTimeInterval(70 * 60),
                    openPrice: 100,
                    highPrice: 101,
                    lowPrice: 99,
                    closePrice: 100,
                    market: "KRX",
                    exchange: "KRX",
                    venue: "KRX"
                ),
                IntradayCandle(
                    timestamp: sessionStart.addingTimeInterval(76 * 60),
                    openPrice: 100,
                    highPrice: 101,
                    lowPrice: 99,
                    closePrice: 100,
                    market: "KRX",
                    exchange: "KRX",
                    venue: "KRX"
                )
            ],
            isComplete: true,
            for: "005930",
            dayIdentifier: dayIdentifier,
            timeZoneIdentifier: timeZone.identifier,
            referenceDate: currentDate
        )
        let client = TossInvestMarketDataClient(
            credentialsStore: StubCredentialsStore(credentials: TossInvestCredentials(apiKey: "key", secretKey: "secret")),
            session: session,
            chartSeriesCacheStore: cacheStore,
            currentDate: { currentDate }
        )

        MockTossInvestURLProtocol.priceTimestamps = [
            Self.isoFormatter.string(from: currentDate)
        ]
        MockTossInvestURLProtocol.candle1mResponses = [
            Self.makeCandlePageData(
                candles: Self.candles([sessionStart.addingTimeInterval(90 * 60)]),
                nextBefore: sessionStart.addingTimeInterval(89 * 60)
            ),
            Self.makeCandlePageData(
                candles: Self.candles((71...89).map { sessionStart.addingTimeInterval(TimeInterval($0 * 60)) }),
                nextBefore: sessionStart.addingTimeInterval(70 * 60)
            ),
            Self.makeCandlePageData(
                candles: Self.candles((0...70).map { sessionStart.addingTimeInterval(TimeInterval($0 * 60)) }),
                nextBefore: nil
            )
        ]
        MockTossInvestURLProtocol.candle1dResponse = Self.makeDailyCandlePageData()

        let snapshot = try await client.snapshot(for: "005930")
        let pointTimes = snapshot.series.points.map(\.date)
        let storedEntry = cacheStore.entry(
            for: "005930",
            dayIdentifier: dayIdentifier,
            timeZoneIdentifier: timeZone.identifier,
            referenceDate: currentDate
        )

        XCTAssertEqual(MockTossInvestURLProtocol.requestCounts["1m"], 3)
        XCTAssertEqual(pointTimes, [
            sessionStart.addingTimeInterval(10 * 60),
            sessionStart.addingTimeInterval(20 * 60),
            sessionStart.addingTimeInterval(30 * 60),
            sessionStart.addingTimeInterval(40 * 60),
            sessionStart.addingTimeInterval(50 * 60),
            sessionStart.addingTimeInterval(60 * 60),
            sessionStart.addingTimeInterval(70 * 60),
            sessionStart.addingTimeInterval(80 * 60),
            sessionStart.addingTimeInterval(90 * 60)
        ])
        XCTAssertEqual(storedEntry?.candles.count, 91)
        XCTAssertEqual(storedEntry?.isComplete, true)
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

    private static func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int = 0,
        timeZone: TimeZone
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(
            from: DateComponents(
                timeZone: timeZone,
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
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
            Self.requestCounts["token", default: 0] += 1
            response = Self.tokenResponse()
        case "/api/v1/stocks":
            Self.requestCounts["stocks", default: 0] += 1
            response = Self.stockInfoResponse(for: Self.requestedSymbol(from: url))
        case "/api/v1/prices":
            Self.requestCounts["prices", default: 0] += 1
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
        try! JSONSerialization.data(
            withJSONObject: ["access_token": "token", "expires_in": 3_600],
            options: []
        )
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
