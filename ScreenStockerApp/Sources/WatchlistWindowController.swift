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

private final class ChartStyleWindowController: NSWindowController {
    init(currentStyle: ScreenSaverChartStyle, onSelect: @escaping (ScreenSaverChartStyle) -> Void) {
        let hostingController = NSHostingController(
            rootView: ChartStyleSelectionView(currentStyle: currentStyle, onSelect: onSelect)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Chart Style"
        window.isReleasedWhenClosed = false
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.backgroundColor = .windowBackgroundColor
        window.setContentSize(NSSize(width: 360, height: 220))
        window.minSize = NSSize(width: 320, height: 200)

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
    @Published var appearanceMode: ScreenSaverAppearanceMode
    @Published var chartStyle: ScreenSaverChartStyle
    @Published var statusMessage = "Ready."

    let symbols: [String]
    private let preferences: StockerPreferences
    private let installer = ScreenSaverInstaller()
    private var chartStyleWindowController: ChartStyleWindowController?

    init(preferences: StockerPreferences) {
        self.preferences = preferences
        self.symbols = preferences.registeredSymbols
        self.selectedSymbol = preferences.selectedSymbol ?? preferences.symbolForScreenSaverDisplay ?? MarketDataCatalog.symbols[0]
        self.appearanceMode = preferences.appearanceMode
        self.chartStyle = preferences.chartStyle
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

    func toggleAppearanceMode() {
        appearanceMode = appearanceMode.next
        preferences.appearanceMode = appearanceMode
        statusMessage = "Dim Mode set to \(appearanceMode.title)."
    }

    func openChartStyleWindow() {
        if chartStyleWindowController == nil {
            chartStyleWindowController = ChartStyleWindowController(
                currentStyle: chartStyle,
                onSelect: { [weak self] style in
                    self?.selectChartStyle(style)
                }
            )
        }

        chartStyleWindowController?.showWindow(nil)
        chartStyleWindowController?.window?.makeKeyAndOrderFront(nil)
        statusMessage = "Chart Style selected."
    }

    func selectChartStyle(_ style: ScreenSaverChartStyle) {
        chartStyle = style
        preferences.chartStyle = style
        chartStyleWindowController?.close()
        chartStyleWindowController = nil
        statusMessage = "\(style.title) selected."
    }

    func installScreenSaver() {
        preferences.selectedSymbol = selectedSymbol
        preferences.appearanceMode = appearanceMode
        preferences.chartStyle = chartStyle

        do {
            try installer.reinstall()
            statusMessage = "Screen saver installed with \(appearanceMode.title) and \(chartStyle.title)."
        } catch {
            statusMessage = "Install failed: \(error.localizedDescription)"
        }
    }

    func saveSelectionToScreenSaver() {
        preferences.selectedSymbol = selectedSymbol
        preferences.appearanceMode = appearanceMode
        preferences.chartStyle = chartStyle

        do {
            try installer.reinstall()
            statusMessage = "\(selectedSymbol) saved and applied to the screen saver."
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
        }
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
                    viewModel.installScreenSaver()
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
                SaveSelectionButton {
                    viewModel.saveSelectionToScreenSaver()
                }
            }
        }
        .padding(28)
    }
}

private struct ScreenSaverSettingsView: View {
    @ObservedObject var viewModel: WatchlistViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HeaderBlock(title: "Screen Saver", subtitle: "Choose how the selected symbol appears on screen.")

            PreviewCard(
                quote: viewModel.selectedQuote,
                series: viewModel.selectedSeries,
                appearanceMode: viewModel.appearanceMode,
                chartStyle: viewModel.chartStyle
            )
                .frame(height: 280)

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

                AppearanceModeButton(mode: viewModel.appearanceMode) {
                    viewModel.toggleAppearanceMode()
                }
                CommandButton(title: "Chart Style", systemImage: "chart.xyaxis.line") {
                    viewModel.openChartStyleWindow()
                }
                PrimaryCommandButton(title: "Install Saver", systemImage: "display.and.arrow.down") {
                    viewModel.installScreenSaver()
                }
            }
        }
        .padding(28)
    }
}

private struct ChartStyleSelectionView: View {
    let currentStyle: ScreenSaverChartStyle
    let onSelect: (ScreenSaverChartStyle) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HeaderBlock(
                title: "Chart Style",
                subtitle: "Select the chart presentation used by the screen saver."
            )

            VStack(spacing: 10) {
                ForEach(ScreenSaverChartStyle.allCases, id: \.rawValue) { style in
                    ChartStyleButton(
                        style: style,
                        isApplied: style == currentStyle,
                        onSelect: onSelect
                    )
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(minWidth: 320, minHeight: 200)
    }
}

private struct ChartStyleButton: View {
    let style: ScreenSaverChartStyle
    let isApplied: Bool
    let onSelect: (ScreenSaverChartStyle) -> Void

    var body: some View {
        Button {
            onSelect(style)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: style.systemImage)
                    .font(.title3)
                    .foregroundStyle(isApplied ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(style.title)
                        .font(.body.weight(.semibold))
                    Text(isApplied ? "Currently applied" : "Apply to screen saver")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isApplied ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isApplied ? Color.accentColor : Color.secondary)
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isApplied ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.2),
                        lineWidth: 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
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

private struct PrimaryCommandButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    private var preferredSize: CGSize {
        Self.preferredSize(title: title, systemImage: systemImage)
    }

    var body: some View {
        PrimaryCommandNativeButton(title: title, systemImage: systemImage, action: action)
            .frame(width: preferredSize.width, height: preferredSize.height)
    }

    private static func preferredSize(title: String, systemImage: String) -> CGSize {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.keyEquivalent = "\r"
        button.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        return button.intrinsicContentSize
    }
}

private struct PrimaryCommandNativeButton: NSViewRepresentable {
    let title: String
    let systemImage: String
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            title: title,
            target: context.coordinator,
            action: #selector(Coordinator.performAction)
        )
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.keyEquivalent = "\r"
        button.imagePosition = .imageLeading
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        update(button)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.target = context.coordinator
        button.action = #selector(Coordinator.performAction)
        update(button)
    }

    private func update(_ button: NSButton) {
        button.title = title
        button.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func performAction() {
            action()
        }
    }
}

private struct SaveSelectionButton: View {
    let action: () -> Void

    private static let preferredSize: CGSize = {
        let button = NSButton(title: "Save Selection", target: nil, action: nil)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        return button.intrinsicContentSize
    }()

    var body: some View {
        SaveSelectionNativeButton(action: action)
            .frame(width: Self.preferredSize.width, height: Self.preferredSize.height)
    }
}

private struct SaveSelectionNativeButton: NSViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            title: "Save Selection",
            target: context.coordinator,
            action: #selector(Coordinator.performAction)
        )
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.keyEquivalent = "\r"
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.target = context.coordinator
        button.action = #selector(Coordinator.performAction)
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func performAction() {
            action()
        }
    }
}

private struct AppearanceModeButton: View {
    let mode: ScreenSaverAppearanceMode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Dim: \(mode.title)", systemImage: mode.systemImage)
        }
        .help("Cycle screen saver appearance")
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

private struct PreviewPalette {
    private let resolvedColorScheme: ColorScheme

    init(appearanceMode: ScreenSaverAppearanceMode, systemColorScheme: ColorScheme) {
        switch appearanceMode {
        case .light:
            self.resolvedColorScheme = .light
        case .dark:
            self.resolvedColorScheme = .dark
        case .automatic:
            self.resolvedColorScheme = systemColorScheme
        }
    }

    private var isLight: Bool {
        resolvedColorScheme == .light
    }

    var background: Color {
        isLight ? .white : .black
    }

    var primaryText: Color {
        (isLight ? Color.black : Color.white).opacity(1)
    }

    var metricText: Color {
        (isLight ? Color.black : Color.white).opacity(0.9)
    }

    var secondaryText: Color {
        (isLight ? Color.black : Color.white).opacity(0.54)
    }

    var tertiaryText: Color {
        (isLight ? Color.black : Color.white).opacity(0.58)
    }

    var badgeText: Color {
        (isLight ? Color.black : Color.white).opacity(0.7)
    }

    var badgeBackground: Color {
        (isLight ? Color.black : Color.white).opacity(0.12)
    }

    var grid: Color {
        (isLight ? Color.black : Color.white).opacity(0.12)
    }
}

private struct PreviewCard: View {
    let quote: StockQuote
    let series: StockChartSeries
    var appearanceMode: ScreenSaverAppearanceMode = .dark
    var chartStyle: ScreenSaverChartStyle = .line

    @Environment(\.colorScheme) private var systemColorScheme

    private var palette: PreviewPalette {
        PreviewPalette(appearanceMode: appearanceMode, systemColorScheme: systemColorScheme)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(palette.background)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    PreviewMetricBlock(
                        title: "Open",
                        value: StockQuote.currencyText(for: series.points.first?.close ?? quote.price),
                        palette: palette
                    )
                    PreviewMetricBlock(
                        title: "High",
                        value: StockQuote.currencyText(for: series.highClose ?? quote.price),
                        palette: palette
                    )
                    PreviewMetricBlock(
                        title: "Low",
                        value: StockQuote.currencyText(for: series.lowClose ?? quote.price),
                        palette: palette
                    )
                    Spacer()
                    Text("Market snapshot")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                }

                switch chartStyle {
                case .line:
                    MiniLineChart(
                        series: series,
                        lineColor: quote.changePercent >= 0 ? .red : .blue,
                        gridColor: palette.grid
                    )
                case .candlestick:
                    MiniCandlestickChart(series: series, gridColor: palette.grid)
                }

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("KRX")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(palette.badgeText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(palette.badgeBackground, in: Capsule())
                        Text("Updated 15:30 KST")
                            .font(.caption)
                            .foregroundStyle(palette.tertiaryText)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        Text(quote.symbol)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(palette.primaryText)
                        Text(quote.priceText)
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(palette.primaryText)
                            .monospacedDigit()
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                        Text(quote.changePercentText)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(quote.changePercent >= 0 ? .red : .blue)
                    }
                }
            }
            .padding(22)
        }
        .frame(minHeight: 220)
    }
}

private struct PreviewMetricBlock: View {
    let title: String
    let value: String
    let palette: PreviewPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.secondaryText)
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(palette.metricText)
        }
    }
}

private struct MiniLineChart: View {
    let series: StockChartSeries
    let lineColor: Color
    let gridColor: Color

    var body: some View {
        GeometryReader { proxy in
            let points = normalizedPoints(in: proxy.size)
            ZStack {
                Path { path in
                    for index in 0..<3 {
                        let y = CGFloat(index) / 2 * proxy.size.height
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    }
                }
                .stroke(gridColor, style: StrokeStyle(lineWidth: 1, dash: [5, 8]))

                Path { path in
                    guard let firstPoint = points.first else { return }
                    path.move(to: firstPoint)
                    for segment in StockChartGeometry.smoothCurveSegments(through: points) {
                        path.addCurve(to: segment.end, control1: segment.control1, control2: segment.control2)
                    }
                }
                .stroke(lineColor, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(minHeight: 52)
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        StockChartGeometry.normalizedPoints(for: series, in: size)
    }
}

private struct MiniCandlestickChart: View {
    let series: StockChartSeries
    let gridColor: Color

    var body: some View {
        GeometryReader { proxy in
            let points = normalizedPoints(in: proxy.size)

            ZStack {
                Path { path in
                    for index in 0..<3 {
                        let y = CGFloat(index) / 2 * proxy.size.height
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    }
                }
                .stroke(gridColor, style: StrokeStyle(lineWidth: 1, dash: [5, 8]))

                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    let previous = index == 0 ? point : points[index - 1]
                    let candleColor: Color = point.y <= previous.y ? .red : .blue
                    let bodyHeight = max(abs(point.y - previous.y), 4)

                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(candleColor.opacity(0.8))
                            .frame(width: 2, height: max(bodyHeight + 8, 14))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(candleColor)
                            .frame(width: max(proxy.size.width / CGFloat(max(points.count, 1)) * 0.42, 4), height: bodyHeight)
                    }
                    .position(x: point.x, y: (point.y + previous.y) / 2)
                }
            }
        }
        .frame(minHeight: 52)
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        StockChartGeometry.normalizedPoints(for: series, in: size)
    }
}
