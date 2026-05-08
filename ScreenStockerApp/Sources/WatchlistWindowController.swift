import AppKit
import SwiftUI

final class WatchlistWindowController: NSWindowController {
    init(preferences: StockerPreferences) {
        let viewModel = WatchlistViewModel(preferences: preferences)
        let hostingController = NSHostingController(rootView: WatchlistRootView(viewModel: viewModel))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "ScreenStocker"
        window.isReleasedWhenClosed = false
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 700, height: 480))
        window.minSize = NSSize(width: 640, height: 420)

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
final class WatchlistViewModel: ObservableObject {
    enum Section: String, CaseIterable, Identifiable {
        case watchlist = "Watchlist"
        case apiKeys = "API Keys"

        var id: String { rawValue }

        var symbolName: String {
            switch self {
            case .watchlist:
                return "star"
            case .apiKeys:
                return "key"
            }
        }
    }

    @Published var selectedSection: Section = .watchlist
    @Published var symbols: [String]
    @Published var inputSymbol = ""
    @Published var searchResults: [StockSymbolSearchResult] = []
    @Published var appKey: String
    @Published var appSecret: String
    @Published var isShowingSavedCredentials = false
    @Published var statusMessage = ""

    private let preferences: StockerPreferences
    private let installer = ScreenSaverInstaller()

    init(preferences: StockerPreferences) {
        self.preferences = preferences
        self.symbols = preferences.registeredSymbols
        self.appKey = preferences.koreaInvestmentAppKey
        self.appSecret = preferences.koreaInvestmentAppSecret
        updateStatus()
    }

    var savedAppKeyPreview: String {
        displayCredential(preferences.koreaInvestmentAppKey)
    }

    var savedAppSecretPreview: String {
        displayCredential(preferences.koreaInvestmentAppSecret)
    }

    var credentialsStatus: String {
        preferences.koreaInvestmentCredentials.isConfigured ? "KIS credentials are saved." : "Demo data is active."
    }

    func addSymbol() {
        let symbol = normalizedSymbol(inputSymbol)
        guard !symbol.isEmpty, !symbols.contains(symbol) else { return }

        symbols.append(symbol)
        inputSymbol = ""
        saveWatchlist()
        statusMessage = "Added \(symbol). Screen saver dropdown updated."
    }

    func addSearchResult(_ result: StockSymbolSearchResult) {
        inputSymbol = result.symbol
        addSymbol()
    }

    func removeSymbols(at offsets: IndexSet) {
        let removed = offsets.compactMap { symbols.indices.contains($0) ? symbols[$0] : nil }
        symbols.remove(atOffsets: offsets)
        saveWatchlist()
        statusMessage = removed.isEmpty ? "\(symbols.count) symbol(s) ready." : "Removed \(removed.joined(separator: ", "))."
    }

    func addDemoSet() {
        for symbol in StockerPreferences.demoSymbols where !symbols.contains(symbol) {
            symbols.append(symbol)
        }
        saveWatchlist()
        statusMessage = "Added demo symbols. Screen saver dropdown updated."
    }

    func searchSymbols() {
        let query = inputSymbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        let credentials = currentCredentials()
        guard credentials.isConfigured else {
            statusMessage = "Add KIS credentials before searching."
            return
        }

        statusMessage = "Looking up KIS symbol..."
        KoreaInvestmentSymbolSearchProvider(credentials: credentials).searchSymbols(matching: query) { [weak self] results in
            DispatchQueue.main.async {
                self?.searchResults = results
                self?.statusMessage = results.isEmpty ? "No matching symbols found." : "\(results.count) result(s) found."
            }
        }
    }

    func applyChanges() {
        do {
            try preferences.saveKoreaInvestmentCredentials(appKey: appKey, appSecret: appSecret)
        } catch {
            statusMessage = "Could not save KIS credentials: \(error.localizedDescription)"
            return
        }

        appKey = preferences.koreaInvestmentAppKey
        appSecret = preferences.koreaInvestmentAppSecret
        saveWatchlist()

        do {
            try installer.reinstall()
            statusMessage = "Applied and reinstalled screen saver."
        } catch {
            statusMessage = "Applied, but install failed: \(error.localizedDescription)"
        }
    }

    func clearCredentials() {
        appKey = ""
        appSecret = ""
        statusMessage = "KIS credentials cleared. Apply to switch to demo data."
    }

    func refreshSavedCredentials() {
        appKey = preferences.koreaInvestmentAppKey
        appSecret = preferences.koreaInvestmentAppSecret
        statusMessage = credentialsStatus
    }

    func updateStatus() {
        switch selectedSection {
        case .watchlist:
            statusMessage = "\(symbols.count) symbol(s) ready."
        case .apiKeys:
            statusMessage = credentialsStatus
        }
    }

    private func saveWatchlist() {
        preferences.registeredSymbols = symbols
        if let selectedSymbol = preferences.selectedSymbol, !preferences.registeredSymbols.contains(selectedSymbol) {
            preferences.selectedSymbol = nil
        }
        symbols = preferences.registeredSymbols
    }

    private func currentCredentials() -> KoreaInvestmentCredentials {
        let enteredKey = appKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let enteredSecret = appSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        return KoreaInvestmentCredentials(
            appKey: enteredKey.isEmpty ? preferences.koreaInvestmentAppKey : enteredKey,
            appSecret: enteredSecret.isEmpty ? preferences.koreaInvestmentAppSecret : enteredSecret
        )
    }

    private func normalizedSymbol(_ symbol: String) -> String {
        symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private func displayCredential(_ credential: String) -> String {
        guard !credential.isEmpty else { return "not saved" }
        guard !isShowingSavedCredentials else { return credential }
        guard credential.count > 10 else { return String(repeating: "*", count: credential.count) }

        return "\(credential.prefix(4))...\(credential.suffix(4))"
    }
}

private struct WatchlistRootView: View {
    @ObservedObject var viewModel: WatchlistViewModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 160)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                footer
            }
        }
        .onChange(of: viewModel.selectedSection) { _ in
            viewModel.updateStatus()
        }
    }

    private var sidebar: some View {
        List(selection: $viewModel.selectedSection) {
            ForEach(WatchlistViewModel.Section.allCases) { section in
                Label(section.rawValue, systemImage: section.symbolName)
                    .tag(section)
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.selectedSection {
        case .watchlist:
            WatchlistEditorView(viewModel: viewModel)
        case .apiKeys:
            APIKeysView(viewModel: viewModel)
        }
    }

    private var footer: some View {
        HStack {
            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer()

            Button("Apply") {
                viewModel.applyChanges()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }
}

private struct WatchlistEditorView: View {
    @ObservedObject var viewModel: WatchlistViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Watchlist")
                    .font(.headline)
                Text("Search and manage symbols shown in the screen saver dropdown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                TextField("005930", text: $viewModel.inputSymbol)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        viewModel.addSymbol()
                    }

                Button("Add") {
                    viewModel.addSymbol()
                }

                Button("Search") {
                    viewModel.searchSymbols()
                }
            }

            if !viewModel.searchResults.isEmpty {
                Menu("Search Results") {
                    ForEach(viewModel.searchResults, id: \.symbol) { result in
                        Button(result.displayTitle) {
                            viewModel.addSearchResult(result)
                        }
                    }
                }
            }

            List {
                ForEach(viewModel.symbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.body.monospacedDigit())
                }
                .onDelete(perform: viewModel.removeSymbols)
            }

            HStack {
                Button("Add Demo Set") {
                    viewModel.addDemoSet()
                }

                Spacer()

                Text("\(viewModel.symbols.count) symbol(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
    }
}

private struct APIKeysView: View {
    @ObservedObject var viewModel: WatchlistViewModel

    var body: some View {
        Form {
            Section {
                SecureField("Paste App Key", text: $viewModel.appKey)
                SecureField("Paste App Secret", text: $viewModel.appSecret)

                HStack {
                    Button("Clear Key") {
                        viewModel.clearCredentials()
                    }

                    Button("Refresh Saved") {
                        viewModel.refreshSavedCredentials()
                    }

                    Button(viewModel.isShowingSavedCredentials ? "Hide Saved" : "Reveal Saved") {
                        viewModel.isShowingSavedCredentials.toggle()
                    }
                }
            } header: {
                Text("Korea Investment Open API")
            } footer: {
                Text("Credentials are stored in Keychain. Leave either field empty and apply to use demo data.")
            }

            Section("Saved in Keychain") {
                CredentialPreviewRow(title: "App Key", value: viewModel.savedAppKeyPreview)
                CredentialPreviewRow(title: "App Secret", value: viewModel.savedAppSecretPreview)
            }
        }
        .formStyle(.grouped)
        .padding(24)
    }
}

private struct CredentialPreviewRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.body.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
