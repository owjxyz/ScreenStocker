import Foundation

struct StockMarketSnapshot: Equatable {
    let quote: StockQuote
    let series: StockChartSeries
}

protocol TossInvestCredentialsProviding {
    var credentials: TossInvestCredentials? { get }
}

enum TossInvestMarketDataError: LocalizedError {
    case missingCredentials
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Toss Invest Open API credentials are missing."
        case .invalidResponse:
            return "The Toss Invest Open API response could not be read."
        case .apiError(let message):
            return message
        }
    }
}

extension TossInvestCredentialsStore: TossInvestCredentialsProviding {}

final class TossInvestMarketDataClient {
    private enum TradingVenue {
        case krx
        case nxt
        case us
    }

    private enum TradingSessionKind {
        case standard
        case usDayMarket

        var cacheIdentifier: String {
            switch self {
            case .standard:
                return StockChartSeriesCacheStore.defaultSessionIdentifier
            case .usDayMarket:
                return "usDayMarket"
            }
        }
    }

    private struct TradingSessionWindow {
        let start: Date
        let end: Date
        let dividerAfter: Date?
    }

    private struct TokenResponse: Decodable {
        let accessToken: String

        private enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
        }
    }

    private struct ErrorEnvelope: Decodable {
        struct APIError: Decodable {
            let code: String?
            let message: String?
        }

        let error: APIError?
    }

    private struct OAuthErrorResponse: Decodable {
        let error: String?
        let errorDescription: String?

        private enum CodingKeys: String, CodingKey {
            case error
            case errorDescription = "error_description"
        }
    }

    private struct PriceEnvelope: Decodable {
        let result: [PriceResponse]
    }

    private struct StockInfoEnvelope: Decodable {
        let result: [StockInfoResponse]
    }

    private struct PriceResponse: Decodable {
        let symbol: String
        let timestamp: Date?
        let lastPrice: Decimal
        let currency: String

        private enum CodingKeys: String, CodingKey {
            case symbol
            case timestamp
            case lastPrice
            case currency
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            symbol = try container.decode(String.self, forKey: .symbol)
            timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp)
            lastPrice = try container.decodeDecimal(forKey: .lastPrice)
            currency = try container.decode(String.self, forKey: .currency)
        }
    }

    private struct StockInfoResponse: Decodable {
        let symbol: String
        let name: String
        let englishName: String
        let market: String
        let status: String
        let currency: String

        var localizedDisplayName: String {
            if Locale.preferredLanguages.first?.hasPrefix("ko") == true {
                return name
            }
            return englishName.isEmpty ? name : englishName
        }
    }

    private struct CandleEnvelope: Decodable {
        let result: CandlePageResponse
    }

    private struct CandlePageResponse: Decodable {
        let candles: [CandleResponse]
        let nextBefore: Date?
    }

    private struct CandleResponse: Decodable {
        let timestamp: Date
        let openPrice: Decimal
        let highPrice: Decimal?
        let lowPrice: Decimal?
        let closePrice: Decimal
        let market: String?
        let exchange: String?
        let venue: String?

        private enum CodingKeys: String, CodingKey {
            case timestamp
            case openPrice
            case highPrice
            case lowPrice
            case closePrice
            case market
            case exchange
            case venue
            case tradingVenue
            case marketCode
            case exchangeCode
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            timestamp = try container.decode(Date.self, forKey: .timestamp)
            openPrice = try container.decodeDecimal(forKey: .openPrice)
            highPrice = try container.decodeDecimalIfPresent(forKey: .highPrice)
            lowPrice = try container.decodeDecimalIfPresent(forKey: .lowPrice)
            closePrice = try container.decodeDecimal(forKey: .closePrice)
            market = try container.decodeIfPresent(String.self, forKey: .market)
                ?? container.decodeIfPresent(String.self, forKey: .marketCode)
            exchange = try container.decodeIfPresent(String.self, forKey: .exchange)
                ?? container.decodeIfPresent(String.self, forKey: .exchangeCode)
            venue = try container.decodeIfPresent(String.self, forKey: .venue)
                ?? container.decodeIfPresent(String.self, forKey: .tradingVenue)
        }

        init(
            timestamp: Date,
            openPrice: Decimal,
            highPrice: Decimal?,
            lowPrice: Decimal?,
            closePrice: Decimal,
            market: String?,
            exchange: String?,
            venue: String?
        ) {
            self.timestamp = timestamp
            self.openPrice = openPrice
            self.highPrice = highPrice
            self.lowPrice = lowPrice
            self.closePrice = closePrice
            self.market = market
            self.exchange = exchange
            self.venue = venue
        }

        var trackingExchangeLabel: String? {
            TossInvestMarketDataClient.normalizedExchangeLabel(from: venue)
                ?? TossInvestMarketDataClient.normalizedExchangeLabel(from: exchange)
                ?? TossInvestMarketDataClient.normalizedExchangeLabel(from: market)
        }
    }

    private let credentialsStore: any TossInvestCredentialsProviding
    private let session: URLSession
    private let chartSeriesCacheStore: StockChartSeriesCacheStore
    private let currentDate: () -> Date
    private let baseURL = URL(string: "https://openapi.tossinvest.com")!
    private let decoder: JSONDecoder
    private static let maximumIntradayCandleGap: TimeInterval = 5 * 60

    init(
        credentialsStore: any TossInvestCredentialsProviding = TossInvestCredentialsStore(),
        session: URLSession = .shared,
        chartSeriesCacheStore: StockChartSeriesCacheStore = StockChartSeriesCacheStore(),
        currentDate: @escaping () -> Date = Date.init
    ) {
        self.credentialsStore = credentialsStore
        self.session = session
        self.chartSeriesCacheStore = chartSeriesCacheStore
        self.currentDate = currentDate
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            try Self.decodeDate(from: decoder)
        }
        self.decoder = decoder
    }

    func quotes(for symbols: [String]) async throws -> [String: StockQuote] {
        let normalizedSymbols = symbols.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }
        guard !normalizedSymbols.isEmpty else { return [:] }

        let token = try await issueAccessToken()
        let stockInfos = (try? await fetchStockInfos(symbols: normalizedSymbols, token: token)) ?? []
        let stockInfoBySymbol = Dictionary(uniqueKeysWithValues: stockInfos.map { ($0.symbol, $0) })
        let prices = try await fetchPrices(symbols: normalizedSymbols, token: token)
        let previousCloses = await previousDailyCloses(for: prices, token: token)

        return Dictionary(uniqueKeysWithValues: prices.map { price in
            (
                price.symbol,
                StockQuote(
                    symbol: price.symbol,
                    displayName: stockInfoBySymbol[price.symbol]?.localizedDisplayName,
                    exchangeLabel: marketLabel(for: stockInfoBySymbol[price.symbol]?.market, symbol: price.symbol),
                    price: price.lastPrice,
                    changePercent: changePercent(price: price.lastPrice, baseline: previousCloses[price.symbol]),
                    currency: price.currency,
                    timestamp: price.timestamp
                )
            )
        })
    }

    func snapshot(for symbol: String) async throws -> StockMarketSnapshot {
        let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedSymbol.isEmpty else {
            throw TossInvestMarketDataError.invalidResponse
        }

        let token = try await issueAccessToken()
        let stockInfos = (try? await fetchStockInfos(symbols: [normalizedSymbol], token: token)) ?? []
        let stockInfo = stockInfos.first
        guard let price = try await fetchPrices(symbols: [normalizedSymbol], token: token).first else {
            throw TossInvestMarketDataError.invalidResponse
        }

        let tradingVenue = tradingVenue(for: price.symbol, market: stockInfo?.market)
        let sessionKind = activeSessionKind(for: tradingVenue, referenceDate: currentDate())
        let dailyCandles = (try? await fetchDailyCandlePage(symbol: price.symbol, token: token).candles) ?? []
        let series = await intradaySeriesForSnapshot(
            symbol: price.symbol,
            token: token,
            venue: tradingVenue,
            sessionKind: sessionKind,
            latestQuoteTimestamp: price.timestamp
        )
        let changePercent = changePercent(
            price: price.lastPrice,
            baseline: previousClose(for: price, dailyCandles: dailyCandles)
        )
        let quote = StockQuote(
            symbol: price.symbol,
            displayName: stockInfo?.localizedDisplayName,
            exchangeLabel: series.trackingExchangeLabel ?? marketLabel(for: stockInfo?.market, symbol: price.symbol),
            price: price.lastPrice,
            changePercent: changePercent,
            currency: price.currency,
            timestamp: price.timestamp
        )
        return StockMarketSnapshot(quote: quote, series: series)
    }

    private func intradaySeriesForSnapshot(
        symbol: String,
        token: String,
        venue: TradingVenue,
        sessionKind: TradingSessionKind,
        latestQuoteTimestamp: Date?
    ) async -> StockChartSeries {
        let referenceDate = currentDate()
        if let cachedEntry = cachedActiveIntradayEntry(
            symbol: symbol,
            venue: venue,
            sessionKind: sessionKind,
            referenceDate: referenceDate
        ) {
            let latestCachedTimestamp = cachedEntry.candles.map(\.timestamp).max()
            let shouldFetchNewCandles = latestQuoteTimestamp.map { quoteTimestamp in
                latestCachedTimestamp.map { quoteTimestamp > $0 } ?? true
            } ?? false

            if !shouldFetchNewCandles {
                return makeIntradaySeries(
                    symbol: symbol,
                    venue: venue,
                    sessionKind: sessionKind,
                    candles: cachedEntry.candles
                )
            }

            if let series = try? await fetchIntradaySeries(
                symbol: symbol,
                token: token,
                venue: venue,
                sessionKind: sessionKind
            ), !series.points.isEmpty {
                return series
            }

            return makeIntradaySeries(
                symbol: symbol,
                venue: venue,
                sessionKind: sessionKind,
                candles: cachedEntry.candles
            )
        }

        if let series = try? await fetchIntradaySeries(
            symbol: symbol,
            token: token,
            venue: venue,
            sessionKind: sessionKind
        ), !series.points.isEmpty {
            return series
        }

        if let latestEntry = latestIntradayEntry(symbol: symbol, venue: venue, sessionKind: sessionKind) {
            return makeIntradaySeries(
                symbol: symbol,
                venue: venue,
                sessionKind: sessionKind,
                candles: latestEntry.candles
            )
        }

        return StockChartSeries(symbol: symbol, points: [])
    }

    func snapshots(for symbols: [String]) async throws -> [String: StockMarketSnapshot] {
        let quotes = try await quotes(for: symbols)
        return Dictionary(uniqueKeysWithValues: quotes.map { symbol, quote in
            (symbol, StockMarketSnapshot(quote: quote, series: StockChartSeries(symbol: symbol, points: [])))
        })
    }

    func stockInfo(for rawSymbol: String) async throws -> StockSymbolSearchResult {
        guard let normalizedSymbol = StockSymbolInput.normalizedSymbol(from: rawSymbol) else {
            throw TossInvestMarketDataError.apiError(StockSymbolInput.validationMessage)
        }

        let token = try await issueAccessToken()
        guard let stockInfo = try await fetchStockInfos(symbols: [normalizedSymbol], token: token).first(where: {
            $0.symbol.caseInsensitiveCompare(normalizedSymbol) == .orderedSame
        }) else {
            throw TossInvestMarketDataError.apiError("No stock was found for \(normalizedSymbol).")
        }

        guard stockInfo.status == "ACTIVE" else {
            throw TossInvestMarketDataError.apiError("\(normalizedSymbol) is not an active listed stock.")
        }

        return StockSymbolSearchResult(
            symbol: stockInfo.symbol,
            name: stockInfo.localizedDisplayName,
            exchange: stockInfo.market,
            country: StockSymbolInput.marketKind(for: stockInfo.symbol) == .krx ? "KR" : "US",
            currency: stockInfo.currency,
            type: stockInfo.status
        )
    }

    private func issueAccessToken() async throws -> String {
        guard let credentials = credentialsStore.credentials else {
            throw TossInvestMarketDataError.missingCredentials
        }

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "client_credentials"),
            URLQueryItem(name: "client_id", value: credentials.apiKey),
            URLQueryItem(name: "client_secret", value: credentials.secretKey)
        ]

        var request = URLRequest(url: baseURL.appendingPathComponent("oauth2/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let data = try await validatedData(for: request)
        return try decoder.decode(TokenResponse.self, from: data).accessToken
    }

    private func fetchPrices(symbols: [String], token: String) async throws -> [PriceResponse] {
        var components = URLComponents(url: apiURL(path: "prices"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "symbols", value: symbols.joined(separator: ","))
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let data = try await validatedData(for: request)
        return try decoder.decode(PriceEnvelope.self, from: data).result
    }

    private func fetchStockInfos(symbols: [String], token: String) async throws -> [StockInfoResponse] {
        var components = URLComponents(url: apiURL(path: "stocks"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "symbols", value: symbols.joined(separator: ","))
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let data = try await validatedData(for: request)
        return try decoder.decode(StockInfoEnvelope.self, from: data).result
    }

    private func fetchIntradaySeries(
        symbol: String,
        token: String,
        venue: TradingVenue,
        sessionKind: TradingSessionKind
    ) async throws -> StockChartSeries {
        let firstPage = try await fetchCandlePage(
            symbol: symbol,
            token: token,
            interval: "1m",
            count: 200,
            before: nil
        )
        guard !firstPage.candles.isEmpty else {
            return StockChartSeries(symbol: symbol, points: [])
        }

        let marketTimeZone = Self.marketTimeZone(for: venue)
        let latestCandleTimestamp = firstPage.candles
            .map(\.timestamp)
            .max() ?? Date()
        let fetchBounds = tradingSessionBounds(
            for: symbol,
            venue: venue,
            sessionKind: sessionKind,
            on: latestCandleTimestamp
        )
        let dayIdentifier = Self.dayIdentifier(for: fetchBounds.start, timeZone: marketTimeZone)
        let firstPageCandles = firstPage.candles
            .filter { $0.timestamp >= fetchBounds.start && $0.timestamp <= fetchBounds.end }
            .map(Self.intradayCandle(from:))
        let cachedEntry = chartSeriesCacheStore.entry(
            for: symbol,
            dayIdentifier: dayIdentifier,
            timeZoneIdentifier: marketTimeZone.identifier,
            sessionIdentifier: sessionKind.cacheIdentifier,
            referenceDate: latestCandleTimestamp
        )

        if let cachedEntry, cachedEntry.isComplete {
            let initialMergedCandles = Self.mergedCandles(cachedEntry.candles, firstPageCandles)
            let shouldBackfill = hasLargeIntradayGap(
                in: initialMergedCandles,
                symbol: symbol,
                venue: venue,
                sessionKind: sessionKind,
                referenceDate: latestCandleTimestamp
            )
            let mergedCandles: [IntradayCandle]

            if shouldBackfill {
                let backfilledCandles = try await fetchSessionMinuteCandles(
                    symbol: symbol,
                    token: token,
                    firstPage: firstPage,
                    sessionStart: fetchBounds.start
                )
                let rawCandles = backfilledCandles
                    .filter { $0.timestamp >= fetchBounds.start && $0.timestamp <= fetchBounds.end }
                    .map(Self.intradayCandle(from:))
                mergedCandles = Self.mergedCandles(cachedEntry.candles, rawCandles)
            } else {
                mergedCandles = initialMergedCandles
            }

            let hasIncompleteGap = hasLargeIntradayGap(
                in: mergedCandles,
                symbol: symbol,
                venue: venue,
                sessionKind: sessionKind,
                referenceDate: latestCandleTimestamp
            )

            chartSeriesCacheStore.save(
                candles: mergedCandles,
                isComplete: !hasIncompleteGap,
                for: symbol,
                dayIdentifier: dayIdentifier,
                timeZoneIdentifier: marketTimeZone.identifier,
                sessionIdentifier: sessionKind.cacheIdentifier,
                referenceDate: latestCandleTimestamp
            )
            return makeIntradaySeries(
                symbol: symbol,
                venue: venue,
                sessionKind: sessionKind,
                candles: mergedCandles
            )
        }

        let candles = try await fetchSessionMinuteCandles(
            symbol: symbol,
            token: token,
            firstPage: firstPage,
            sessionStart: fetchBounds.start
        )
        let rawCandles = candles
            .filter { $0.timestamp >= fetchBounds.start && $0.timestamp <= fetchBounds.end }
            .map(Self.intradayCandle(from:))
        guard !rawCandles.isEmpty || cachedEntry != nil else {
            return StockChartSeries(symbol: symbol, points: [])
        }
        let mergedCandles = Self.mergedCandles(cachedEntry?.candles ?? [], rawCandles)
        let hasIncompleteGap = hasLargeIntradayGap(
            in: mergedCandles,
            symbol: symbol,
            venue: venue,
            sessionKind: sessionKind,
            referenceDate: latestCandleTimestamp
        )

        chartSeriesCacheStore.save(
            candles: mergedCandles,
            isComplete: !hasIncompleteGap,
            for: symbol,
            dayIdentifier: dayIdentifier,
            timeZoneIdentifier: marketTimeZone.identifier,
            sessionIdentifier: sessionKind.cacheIdentifier,
            referenceDate: latestCandleTimestamp
        )

        return makeIntradaySeries(
            symbol: symbol,
            venue: venue,
            sessionKind: sessionKind,
            candles: mergedCandles
        )
    }

    private func makeIntradaySeries(
        symbol: String,
        venue: TradingVenue,
        sessionKind: TradingSessionKind,
        candles: [IntradayCandle]
    ) -> StockChartSeries {
        let rawCandles = candles
            .sorted { $0.timestamp < $1.timestamp }
            .map(Self.candleResponse(from:))
        let (sessionStart, sessionEnd, sessionDividers) = sessionBoundsForLatestAvailableCandles(
            rawCandles,
            symbol: symbol,
            venue: venue,
            sessionKind: sessionKind
        )
        let filteredCandles = rawCandles
            .filter { $0.timestamp >= sessionStart && $0.timestamp <= sessionEnd }
            .sorted { $0.timestamp < $1.timestamp }
        let points = aggregateTenMinuteCandles(filteredCandles, sessionStart: sessionStart)
        return StockChartSeries(
            symbol: symbol,
            points: points,
            sessionStart: sessionStart,
            sessionEnd: sessionEnd,
            sessionDividers: sessionDividers,
            trackingExchangeLabel: latestTrackingExchangeLabel(in: filteredCandles)
        )
    }

    private func cachedActiveIntradayEntry(
        symbol: String,
        venue: TradingVenue,
        sessionKind: TradingSessionKind,
        referenceDate: Date
    ) -> IntradaySeriesCacheEntry? {
        let marketTimeZone = Self.marketTimeZone(for: venue)
        return chartSeriesCacheStore.activeSessionEntry(
            for: symbol,
            timeZoneIdentifier: marketTimeZone.identifier,
            sessionIdentifier: sessionKind.cacheIdentifier,
            referenceDate: referenceDate
        )
    }

    private func latestIntradayEntry(
        symbol: String,
        venue: TradingVenue,
        sessionKind: TradingSessionKind
    ) -> IntradaySeriesCacheEntry? {
        let marketTimeZone = Self.marketTimeZone(for: venue)
        return chartSeriesCacheStore.latestEntry(
            for: symbol,
            timeZoneIdentifier: marketTimeZone.identifier,
            sessionIdentifier: sessionKind.cacheIdentifier
        )
    }

    private func fetchSessionMinuteCandles(
        symbol: String,
        token: String,
        firstPage: CandlePageResponse,
        sessionStart: Date
    ) async throws -> [CandleResponse] {
        var allCandles = firstPage.candles
        var before = firstPage.nextBefore
        var pageCount = 1

        while before != nil && pageCount < 8 {
            let earliestTimestamp = allCandles.map(\.timestamp).min()
            if let earliestTimestamp, earliestTimestamp <= sessionStart {
                break
            }

            let page = try await fetchCandlePage(
                symbol: symbol,
                token: token,
                interval: "1m",
                count: 200,
                before: before
            )
            allCandles.append(contentsOf: page.candles)
            before = page.nextBefore
            pageCount += 1
        }

        return allCandles
    }

    private func fetchDailyCandlePage(symbol: String, token: String) async throws -> CandlePageResponse {
        try await fetchCandlePage(
            symbol: symbol,
            token: token,
            interval: "1d",
            count: 5,
            before: nil
        )
    }

    private func fetchCandlePage(
        symbol: String,
        token: String,
        interval: String,
        count: Int,
        before: Date?
    ) async throws -> CandlePageResponse {
        var components = URLComponents(url: apiURL(path: "candles"), resolvingAgainstBaseURL: false)!
        var queryItems = [
            URLQueryItem(name: "symbol", value: symbol),
            URLQueryItem(name: "interval", value: interval),
            URLQueryItem(name: "count", value: "\(count)"),
            URLQueryItem(name: "adjusted", value: "true")
        ]
        if let before {
            queryItems.append(URLQueryItem(name: "before", value: Self.queryDateFormatter.string(from: before)))
        }
        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let data = try await validatedData(for: request)
        return try decoder.decode(CandleEnvelope.self, from: data).result
    }

    private func previousDailyCloses(for prices: [PriceResponse], token: String) async -> [String: Decimal] {
        var previousCloses: [String: Decimal] = [:]
        for price in prices {
            guard let dailyCandles = try? await fetchDailyCandlePage(symbol: price.symbol, token: token).candles,
                  let previousClose = previousClose(for: price, dailyCandles: dailyCandles) else {
                continue
            }
            previousCloses[price.symbol] = previousClose
        }
        return previousCloses
    }

    private func previousClose(for price: PriceResponse, dailyCandles: [CandleResponse]) -> Decimal? {
        let sortedCandles = dailyCandles.sorted { $0.timestamp > $1.timestamp }
        guard !sortedCandles.isEmpty else { return nil }

        guard let priceTimestamp = price.timestamp else {
            return sortedCandles.dropFirst().first?.closePrice ?? sortedCandles.first?.closePrice
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.marketTimeZone(for: .krx)
        let priceDay = calendar.startOfDay(for: priceTimestamp)

        if let previousTradingDayCandle = sortedCandles.first(where: {
            calendar.startOfDay(for: $0.timestamp) < priceDay
        }) {
            return previousTradingDayCandle.closePrice
        }

        return sortedCandles.dropFirst().first?.closePrice
    }

    private func changePercent(price: Decimal?, baseline: Decimal?) -> Decimal? {
        guard let price, let baseline, baseline != 0 else { return nil }
        return ((price - baseline) / baseline) * 100
    }

    private func sessionBoundsForLatestAvailableCandles(
        _ candles: [CandleResponse],
        symbol: String,
        venue: TradingVenue,
        sessionKind: TradingSessionKind
    ) -> (start: Date, end: Date, dividers: [Date]) {
        let sortedCandles = candles.sorted { $0.timestamp > $1.timestamp }
        guard let latestCandle = sortedCandles.first else {
            return tradingSessionBounds(
                for: symbol,
                venue: venue,
                sessionKind: sessionKind,
                on: Date()
            )
        }

        if venue == .us {
            return tradingSessionBounds(
                for: symbol,
                venue: venue,
                sessionKind: sessionKind,
                on: latestCandle.timestamp
            )
        }

        let sessionWindows = tradingSessionWindows(
            for: symbol,
            venue: venue,
            sessionKind: sessionKind,
            on: latestCandle.timestamp
        )
        let activeWindows = sessionWindows.filter { window in
            sortedCandles.contains(where: { $0.timestamp >= window.start && $0.timestamp <= window.end })
        }

        guard !activeWindows.isEmpty else {
            return tradingSessionBounds(
                for: symbol,
                venue: venue,
                sessionKind: sessionKind,
                on: latestCandle.timestamp
            )
        }

        return (
            start: activeWindows.first!.start,
            end: activeWindows.last!.end,
            dividers: activeWindows.dropLast().compactMap(\.dividerAfter)
        )
    }

    private func tradingSessionBounds(
        for symbol: String,
        venue: TradingVenue,
        sessionKind: TradingSessionKind,
        on date: Date
    ) -> (start: Date, end: Date, dividers: [Date]) {
        let windows = tradingSessionWindows(for: symbol, venue: venue, sessionKind: sessionKind, on: date)
        guard let firstWindow = windows.first, let lastWindow = windows.last else {
            return (date, date, [])
        }

        return (
            start: firstWindow.start,
            end: lastWindow.end,
            dividers: windows.dropLast().compactMap(\.dividerAfter)
        )
    }

    private func tradingSessionWindows(
        for symbol: String,
        venue: TradingVenue,
        sessionKind: TradingSessionKind,
        on date: Date
    ) -> [TradingSessionWindow] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.marketTimeZone(for: venue)

        switch venue {
        case .krx:
            let preStart = Self.sessionDate(matching: date, hour: 8, minute: 0, calendar: calendar)
            let preEnd = Self.sessionDate(matching: date, hour: 8, minute: 50, calendar: calendar)
            let regularStart = Self.sessionDate(matching: date, hour: 9, minute: 0, calendar: calendar)
            let regularEnd = Self.sessionDate(matching: date, hour: 15, minute: 30, calendar: calendar)
            let afterStart = Self.sessionDate(matching: date, hour: 15, minute: 40, calendar: calendar)
            let afterEnd = Self.sessionDate(matching: date, hour: 20, minute: 0, calendar: calendar)
            return [
                TradingSessionWindow(start: preStart, end: preEnd, dividerAfter: regularStart),
                TradingSessionWindow(start: regularStart, end: regularEnd, dividerAfter: regularEnd),
                TradingSessionWindow(start: afterStart, end: afterEnd, dividerAfter: nil)
            ]
        case .nxt:
            let preStart = Self.sessionDate(matching: date, hour: 8, minute: 0, calendar: calendar)
            let preEnd = Self.sessionDate(matching: date, hour: 8, minute: 50, calendar: calendar)
            let regularStart = Self.sessionDate(matching: date, hour: 9, minute: 0, second: 30, calendar: calendar)
            let regularEnd = Self.sessionDate(matching: date, hour: 15, minute: 20, calendar: calendar)
            let afterStart = Self.sessionDate(matching: date, hour: 15, minute: 40, calendar: calendar)
            let afterEnd = Self.sessionDate(matching: date, hour: 20, minute: 0, calendar: calendar)
            return [
                TradingSessionWindow(start: preStart, end: preEnd, dividerAfter: regularStart),
                TradingSessionWindow(start: regularStart, end: regularEnd, dividerAfter: regularEnd),
                TradingSessionWindow(start: afterStart, end: afterEnd, dividerAfter: nil)
            ]
        case .us:
            if sessionKind == .usDayMarket {
                let dayMarketStart: Date
                let dayMarketEnd: Date
                let hour = calendar.component(.hour, from: date)
                if hour >= 20 {
                    dayMarketStart = Self.sessionDate(matching: date, hour: 20, minute: 0, calendar: calendar)
                    dayMarketEnd = calendar.date(
                        byAdding: .hour,
                        value: 8,
                        to: dayMarketStart
                    ) ?? dayMarketStart
                } else {
                    dayMarketEnd = Self.sessionDate(matching: date, hour: 4, minute: 0, calendar: calendar)
                    dayMarketStart = calendar.date(
                        byAdding: .hour,
                        value: -8,
                        to: dayMarketEnd
                    ) ?? dayMarketEnd
                }
                return [
                    TradingSessionWindow(start: dayMarketStart, end: dayMarketEnd, dividerAfter: nil)
                ]
            }

            let extendedStart = Self.sessionDate(matching: date, hour: 4, minute: 0, calendar: calendar)
            let regularOpen = Self.sessionDate(matching: date, hour: 9, minute: 30, calendar: calendar)
            let regularClose = Self.sessionDate(matching: date, hour: 16, minute: 0, calendar: calendar)
            let extendedEnd = Self.sessionDate(matching: date, hour: 20, minute: 0, calendar: calendar)
            return [
                TradingSessionWindow(start: extendedStart, end: regularOpen, dividerAfter: regularOpen),
                TradingSessionWindow(start: regularOpen, end: regularClose, dividerAfter: regularClose),
                TradingSessionWindow(start: regularClose, end: extendedEnd, dividerAfter: nil)
            ]
        }
    }

    private func latestTrackingExchangeLabel(in candles: [CandleResponse]) -> String? {
        candles
            .sorted { $0.timestamp > $1.timestamp }
            .lazy
            .compactMap(\.trackingExchangeLabel)
            .first
    }

    private func aggregateTenMinuteCandles(
        _ candles: [CandleResponse],
        sessionStart: Date
    ) -> [StockTimeSeriesPoint] {
        guard !candles.isEmpty else { return [] }

        let groupedCandles = Dictionary(grouping: candles.filter { $0.timestamp > sessionStart }) { candle in
            Int(ceil(candle.timestamp.timeIntervalSince(sessionStart) / 600))
        }

        return groupedCandles.keys.sorted().compactMap { bucket in
            guard let bucketCandles = groupedCandles[bucket]?.sorted(by: { $0.timestamp < $1.timestamp }),
                  let first = bucketCandles.first,
                  let last = bucketCandles.last else {
                return nil
            }

            let high = bucketCandles
                .map { $0.highPrice ?? max($0.openPrice, $0.closePrice) }
                .max() ?? max(first.openPrice, last.closePrice)
            let low = bucketCandles
                .map { $0.lowPrice ?? min($0.openPrice, $0.closePrice) }
                .min() ?? min(first.openPrice, last.closePrice)

            return StockTimeSeriesPoint(
                date: sessionStart.addingTimeInterval(TimeInterval(bucket * 600)),
                open: first.openPrice,
                high: high,
                low: low,
                close: last.closePrice
            )
        }
    }

    private static func intradayCandle(from candle: CandleResponse) -> IntradayCandle {
        IntradayCandle(
            timestamp: candle.timestamp,
            openPrice: candle.openPrice,
            highPrice: candle.highPrice,
            lowPrice: candle.lowPrice,
            closePrice: candle.closePrice,
            market: candle.market,
            exchange: candle.exchange,
            venue: candle.venue
        )
    }

    private static func candleResponse(from candle: IntradayCandle) -> CandleResponse {
        CandleResponse(
            timestamp: candle.timestamp,
            openPrice: candle.openPrice,
            highPrice: candle.highPrice,
            lowPrice: candle.lowPrice,
            closePrice: candle.closePrice,
            market: candle.market,
            exchange: candle.exchange,
            venue: candle.venue
        )
    }

    private static func mergedCandles(_ cachedCandles: [IntradayCandle], _ newCandles: [IntradayCandle]) -> [IntradayCandle] {
        var mergedByTimestamp: [Date: IntradayCandle] = [:]
        for candle in cachedCandles {
            mergedByTimestamp[candle.timestamp] = candle
        }
        for candle in newCandles {
            mergedByTimestamp[candle.timestamp] = candle
        }
        return mergedByTimestamp.values.sorted { $0.timestamp < $1.timestamp }
    }

    private func hasLargeIntradayGap(
        in candles: [IntradayCandle],
        symbol: String,
        venue: TradingVenue,
        sessionKind: TradingSessionKind,
        referenceDate: Date
    ) -> Bool {
        let windows = tradingSessionWindows(
            for: symbol,
            venue: venue,
            sessionKind: sessionKind,
            on: referenceDate
        )
        let timestampsByWindow = windows.map { window in
            candles
                .map(\.timestamp)
                .filter { $0 >= window.start && $0 <= window.end }
                .sorted()
        }

        if timestampsByWindow.contains(where: {
            Self.hasLargeGap(in: $0, maximumGap: Self.maximumIntradayCandleGap)
        }) {
            return true
        }

        let populatedWindowIndexes = timestampsByWindow.enumerated().compactMap { index, timestamps in
            timestamps.isEmpty ? nil : index
        }
        guard let firstPopulatedWindow = populatedWindowIndexes.first,
              let lastPopulatedWindow = populatedWindowIndexes.last,
              firstPopulatedWindow < lastPopulatedWindow else {
            return false
        }

        return timestampsByWindow[firstPopulatedWindow...lastPopulatedWindow].contains { $0.isEmpty }
    }

    private static func hasLargeGap(in timestamps: [Date], maximumGap: TimeInterval) -> Bool {
        return zip(timestamps, timestamps.dropFirst()).contains { previous, current in
            current.timeIntervalSince(previous) > maximumGap
        }
    }

    private static func marketTimeZone(for venue: TradingVenue) -> TimeZone {
        switch venue {
        case .krx, .nxt:
            return TimeZone(identifier: "Asia/Seoul") ?? .current
        case .us:
            return TimeZone(identifier: "America/New_York") ?? .current
        }
    }

    private func tradingVenue(for symbol: String, market: String?) -> TradingVenue {
        let marketName = market?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        if marketName.contains("NXT") {
            return .nxt
        }

        switch StockSymbolInput.marketKind(for: symbol) {
        case .krx:
            return .krx
        case .us:
            return .us
        }
    }

    private func activeSessionKind(for venue: TradingVenue, referenceDate: Date) -> TradingSessionKind {
        guard venue == .us else {
            return .standard
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.marketTimeZone(for: venue)
        let hour = calendar.component(.hour, from: referenceDate)
        return hour >= 20 || hour < 4 ? .usDayMarket : .standard
    }

    private func marketLabel(for market: String?, symbol: String) -> String? {
        if let label = Self.normalizedExchangeLabel(from: market) {
            return label
        }

        return StockSymbolInput.marketKind(for: symbol) == .krx ? "KRX" : "US"
    }

    private static func normalizedExchangeLabel(from value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else { return nil }
        if normalized.contains("NXT") {
            return "NXT"
        }
        if normalized.contains("KRX") {
            return "KRX"
        }
        return normalized
    }

    private static func sessionDate(matching date: Date, hour: Int, minute: Int, second: Int = 0, calendar: Calendar) -> Date {
        calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: second,
            of: date
        ) ?? date
    }

    private static func dayIdentifier(for date: Date, timeZone: TimeZone) -> String {
        StockChartSeriesCacheStore.dayIdentifier(for: date, timeZone: timeZone)
    }

    private static let queryDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private func validatedData(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TossInvestMarketDataError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let oauthError = try? decoder.decode(OAuthErrorResponse.self, from: data),
               oauthError.error != nil || oauthError.errorDescription != nil {
                let code = oauthError.error.map { "\($0): " } ?? ""
                throw TossInvestMarketDataError.apiError("\(code)\(oauthError.errorDescription ?? "Request failed.")")
            }

            if let envelope = try? decoder.decode(ErrorEnvelope.self, from: data),
               let error = envelope.error {
                let code = error.code.map { "\($0): " } ?? ""
                throw TossInvestMarketDataError.apiError("\(code)\(error.message ?? "Request failed.")")
            }
            throw TossInvestMarketDataError.apiError("Request failed with HTTP \(httpResponse.statusCode).")
        }
        return data
    }

    private func apiURL(path: String) -> URL {
        baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("v1")
            .appendingPathComponent(path)
    }

    private static func decodeDate(from decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        let withFractionalSeconds = ISO8601DateFormatter()
        withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let withoutFractionalSeconds = ISO8601DateFormatter()
        withoutFractionalSeconds.formatOptions = [.withInternetDateTime]

        for formatter in [withFractionalSeconds, withoutFractionalSeconds] {
            if let date = formatter.date(from: value) {
                return date
            }
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Expected ISO 8601 date string, got \(value)."
        )
    }
}

private extension KeyedDecodingContainer {
    func decodeDecimal(forKey key: Key) throws -> Decimal {
        if let stringValue = try? decode(String.self, forKey: key),
           let decimal = Decimal(string: stringValue) {
            return decimal
        }

        if let doubleValue = try? decode(Double.self, forKey: key) {
            return Decimal(doubleValue)
        }

        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: self,
            debugDescription: "Expected decimal string or number."
        )
    }

    func decodeDecimalIfPresent(forKey key: Key) throws -> Decimal? {
        if let stringValue = try? decodeIfPresent(String.self, forKey: key) {
            return Decimal(string: stringValue)
        }

        if let doubleValue = try? decodeIfPresent(Double.self, forKey: key) {
            return Decimal(doubleValue)
        }

        return nil
    }
}
