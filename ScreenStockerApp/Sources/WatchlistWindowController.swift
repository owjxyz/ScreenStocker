import AppKit
import SwiftUI

final class WatchlistWindowController: NSWindowController {
    init(preferences: StockerPreferences) {
        let viewModel = WatchlistViewModel(preferences: preferences)
        let hostingController = NSHostingController(rootView: WatchlistRootView(viewModel: viewModel))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "ScreenStocker"
        window.isReleasedWhenClosed = false
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.backgroundColor = .windowBackgroundColor
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 880, height: 560))
        window.minSize = NSSize(width: 760, height: 500)

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
final class WatchlistViewModel: ObservableObject {
    enum Section: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case watchlist = "Watchlist"
        case saver = "Screen Saver"

        var id: String { rawValue }

        var symbolName: String {
            switch self {
            case .overview:
                return "rectangle.grid.2x2"
            case .watchlist:
                return "star"
            case .saver:
                return "display"
            }
        }
    }

    @Published var selectedSection: Section = .overview
    @Published var selectedSymbol: String
    @Published var statusMessage = "Ready."

    let symbols: [String]
    private let preferences: StockerPreferences

    init(preferences: StockerPreferences) {
        self.preferences = preferences
        self.symbols = preferences.registeredSymbols
        self.selectedSymbol = preferences.selectedSymbol ?? preferences.symbolForScreenSaverDisplay ?? MarketDataCatalog.symbols[0]
        preferences.registeredSymbols = symbols
    }

    var selectedQuote: StockQuote {
        MarketDataCatalog.quote(for: selectedSymbol)
    }

    var selectedSeries: StockChartSeries {
        MarketDataCatalog.chartSeries(for: selectedSymbol)
    }

    func selectSymbol(_ symbol: String) {
        selectedSymbol = symbol
        preferences.selectedSymbol = symbol
        statusMessage = "\(symbol) selected for the screen saver."
    }

    func performAction(_ title: String) {
        statusMessage = "\(title) selected."
    }
}

private struct WatchlistRootView: View {
    @ObservedObject var viewModel: WatchlistViewModel

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            content
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    viewModel.performAction("Add Symbol")
                } label: {
                    Label("Add Symbol", systemImage: "plus")
                }

                Button {
                    viewModel.performAction("Remove")
                } label: {
                    Label("Remove", systemImage: "minus")
                }
                .disabled(viewModel.selectedSection != .watchlist)
            }

            ToolbarItemGroup {
                Button {
                    viewModel.performAction("Preview Screen Saver")
                } label: {
                    Label("Preview Screen Saver", systemImage: "play.rectangle")
                }

                Button {
                    viewModel.performAction("Install Screen Saver")
                } label: {
                    Label("Install Screen Saver", systemImage: "display.and.arrow.down")
                }
            }
        }
    }

    private var sidebar: some View {
        List(selection: $viewModel.selectedSection) {
            Section("ScreenStocker") {
                ForEach(WatchlistViewModel.Section.allCases) { section in
                    Label(section.rawValue, systemImage: section.symbolName)
                        .tag(section)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("ScreenStocker")
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.selectedSection {
        case .overview:
            OverviewView(viewModel: viewModel)
                .navigationTitle("Overview")
        case .watchlist:
            WatchlistView(viewModel: viewModel)
                .navigationTitle("Watchlist")
        case .saver:
            ScreenSaverSettingsView(viewModel: viewModel)
                .navigationTitle("Screen Saver")
        }
    }
}

private struct OverviewView: View {
    @ObservedObject var viewModel: WatchlistViewModel

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 18) {
                HeaderBlock(
                    title: "Market Dashboard",
                    subtitle: "Monitor the selected symbol and screen saver presentation."
                )

                PreviewCard(quote: viewModel.selectedQuote, series: viewModel.selectedSeries)

                HStack(spacing: 10) {
                    CommandButton(title: "Preview Saver", systemImage: "play.rectangle") {
                        viewModel.performAction("Preview Saver")
                    }
                    CommandButton(title: "Arrange Layout", systemImage: "square.grid.2x2") {
                        viewModel.performAction("Arrange Layout")
                    }
                    CommandButton(title: "Export Snapshot", systemImage: "square.and.arrow.down") {
                        viewModel.performAction("Export Snapshot")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                HeaderBlock(title: "Watchlist", subtitle: "Symbols available for the screen saver.")

                ForEach(viewModel.symbols, id: \.self) { symbol in
                    SymbolRow(
                        quote: MarketDataCatalog.quote(for: symbol),
                        isSelected: symbol == viewModel.selectedSymbol
                    ) {
                        viewModel.selectSymbol(symbol)
                    }
                }

                Spacer()
            }
            .frame(width: 250)
        }
        .padding(28)
    }
}

private struct WatchlistView: View {
    @ObservedObject var viewModel: WatchlistViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HeaderBlock(title: "Watchlist", subtitle: "Manage the symbols shown in the screen saver.")

            HStack(spacing: 10) {
                CommandButton(title: "Add Symbol", systemImage: "plus") {
                    viewModel.performAction("Add Symbol")
                }
                CommandButton(title: "Remove", systemImage: "minus") {
                    viewModel.performAction("Remove")
                }
                CommandButton(title: "Reorder", systemImage: "arrow.up.arrow.down") {
                    viewModel.performAction("Reorder")
                }
                Spacer()
                CommandButton(title: "Import List", systemImage: "tray.and.arrow.down") {
                    viewModel.performAction("Import List")
                }
            }

            List(viewModel.symbols, id: \.self, selection: $viewModel.selectedSymbol) { symbol in
                SymbolRow(
                    quote: MarketDataCatalog.quote(for: symbol),
                    isSelected: symbol == viewModel.selectedSymbol
                ) {
                    viewModel.selectSymbol(symbol)
                }
                .padding(.vertical, 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Text("\(viewModel.symbols.count) symbols")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Save Selection") {
                    viewModel.selectSymbol(viewModel.selectedSymbol)
                }
            }
        }
        .padding(28)
    }
}

private struct ScreenSaverSettingsView: View {
    @ObservedObject var viewModel: WatchlistViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HeaderBlock(title: "Screen Saver", subtitle: "Choose how the selected symbol appears on screen.")

            PreviewCard(quote: viewModel.selectedQuote, series: viewModel.selectedSeries)
                .frame(height: 300)

            HStack(spacing: 10) {
                Picker("Display", selection: $viewModel.selectedSymbol) {
                    ForEach(viewModel.symbols, id: \.self) { symbol in
                        Text(symbol).tag(symbol)
                    }
                }
                .frame(width: 180)
                .onChange(of: viewModel.selectedSymbol) { symbol in
                    viewModel.selectSymbol(symbol)
                }

                CommandButton(title: "Dim Mode", systemImage: "moon") {
                    viewModel.performAction("Dim Mode")
                }
                CommandButton(title: "Chart Style", systemImage: "chart.xyaxis.line") {
                    viewModel.performAction("Chart Style")
                }
                CommandButton(title: "Install Saver", systemImage: "display.and.arrow.down") {
                    viewModel.performAction("Install Saver")
                }
            }
        }
        .padding(28)
    }
}

private struct HeaderBlock: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CommandButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
    }
}

private struct SymbolRow: View {
    let quote: StockQuote
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(quote.symbol)
                        .font(.body.monospacedDigit().weight(.semibold))
                    Text("Market status")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(quote.priceText)
                        .font(.body.monospacedDigit())
                    Text(quote.changePercentText)
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(quote.changePercent >= 0 ? .red : .blue)
                }

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct PreviewCard: View {
    let quote: StockQuote
    let series: StockChartSeries

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(quote.symbol)
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(quote.priceText)
                            .font(.system(size: 58, weight: .bold))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                        Text(quote.changePercentText)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(quote.changePercent >= 0 ? .red : .blue)
                    }
                    Spacer()
                    Text("KRX")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.12), in: Capsule())
                }

                MiniLineChart(series: series, lineColor: quote.changePercent >= 0 ? .red : .blue)
            }
            .padding(26)
        }
        .frame(minHeight: 260)
    }
}

private struct MiniLineChart: View {
    let series: StockChartSeries
    let lineColor: Color

    var body: some View {
        GeometryReader { proxy in
            let points = normalizedPoints(in: proxy.size)
            Path { path in
                guard let firstPoint = points.first else { return }
                path.move(to: firstPoint)
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(lineColor, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
        .frame(minHeight: 90)
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        let values = series.points.map { NSDecimalNumber(decimal: $0.close).doubleValue }
        guard values.count > 1,
              let minValue = values.min(),
              let maxValue = values.max() else {
            return []
        }

        let range = max(maxValue - minValue, 1)
        return values.enumerated().map { index, value in
            let x = CGFloat(index) / CGFloat(values.count - 1) * size.width
            let yRatio = (value - minValue) / range
            let y = size.height - CGFloat(yRatio) * size.height
            return CGPoint(x: x, y: y)
        }
    }
}
