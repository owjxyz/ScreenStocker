import Foundation

enum StockSymbolInput {
    enum MarketKind {
        case krx
        case us
    }

    static func normalizedSymbol(from rawValue: String) -> String? {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else { return nil }

        if marketKind(for: normalized) == .krx {
            return normalized
        }

        if normalized.range(of: #"^(?=.*[A-Z])[A-Z0-9.-]{1,16}$"#, options: .regularExpression) != nil {
            return normalized
        }

        return nil
    }

    static func marketKind(for normalizedSymbol: String) -> MarketKind {
        normalizedSymbol.range(of: #"^\d[A-Z\d]{5}$"#, options: .regularExpression) != nil ? .krx : .us
    }

    static let validationMessage = "Enter a KRX 6-character code like 005930 or 46520A or a US ticker like AAPL."
}
