import AppKit
import SwiftUI

final class ConfigurationWindowController: NSWindowController {
    private let preferences: StockerPreferences
    private let viewModel: ScreenSaverConfigurationViewModel

    init(preferences: StockerPreferences) {
        self.preferences = preferences
        self.viewModel = ScreenSaverConfigurationViewModel(preferences: preferences)

        let hostingController = NSHostingController(
            rootView: ScreenSaverConfigurationView(viewModel: viewModel)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "ScreenStocker Settings"
        window.styleMask = [.titled]
        window.setContentSize(NSSize(width: 420, height: 180))

        super.init(window: window)

        viewModel.onDone = { [weak window] in
            guard let window else { return }
            window.sheetParent?.endSheet(window)
        }

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(preferencesDidChange),
            name: StockerPreferences.didChangeNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    func reloadSymbols() {
        viewModel.reload()
    }

    @objc private func preferencesDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.reloadSymbols()
        }
    }
}

@MainActor
final class ScreenSaverConfigurationViewModel: ObservableObject {
    @Published private(set) var symbols: [String] = []
    @Published var selectedSymbol: String = ScreenSaverConfigurationViewModel.firstSymbolID
    var onDone: (() -> Void)?

    private static let firstSymbolID = "__first__"
    private let preferences: StockerPreferences

    init(preferences: StockerPreferences) {
        self.preferences = preferences
        reload()
    }

    var isWatchlistEmpty: Bool {
        symbols.isEmpty
    }

    var firstSymbolID: String {
        Self.firstSymbolID
    }

    func reload() {
        symbols = preferences.registeredSymbols
        selectedSymbol = preferences.selectedSymbol ?? Self.firstSymbolID
    }

    func saveAndClose() {
        preferences.selectedSymbol = selectedSymbol == Self.firstSymbolID ? nil : selectedSymbol
        onDone?()
    }
}

private struct ScreenSaverConfigurationView: View {
    @ObservedObject var viewModel: ScreenSaverConfigurationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Display Symbol")
                .font(.headline)

            Picker("Display", selection: $viewModel.selectedSymbol) {
                Text("First watchlist symbol").tag(viewModel.firstSymbolID)
                ForEach(viewModel.symbols, id: \.self) { symbol in
                    Text(symbol).tag(symbol)
                }
            }
            .labelsHidden()
            .disabled(viewModel.isWatchlistEmpty)

            if viewModel.isWatchlistEmpty {
                Text("No registered symbols. Open ScreenStocker to add symbols.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") {
                    viewModel.saveAndClose()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420, height: 180)
    }
}
