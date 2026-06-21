import AppKit
import SwiftUI

final class ConfigurationWindowController: NSWindowController {
    private let viewModel = ScreenSaverConfigurationViewModel()

    init(preferences: StockerPreferences) {
        let hostingController = NSHostingController(
            rootView: ScreenSaverConfigurationView(viewModel: viewModel)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "ScreenStocker Settings"
        window.styleMask = [.titled]
        window.setContentSize(NSSize(width: 420, height: 190))

        super.init(window: window)

        viewModel.onDone = { [weak window] in
            guard let window else { return }
            window.sheetParent?.endSheet(window)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reloadSymbols() {}
}

@MainActor
final class ScreenSaverConfigurationViewModel: ObservableObject {
    @Published var statusMessage = ""
    var onDone: (() -> Void)?

    func openManagementApp() {
        if let appURL = Self.managementAppURL() {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
                DispatchQueue.main.async {
                    if let error {
                        self?.statusMessage = "Could not open ScreenStocker: \(error.localizedDescription)"
                    } else {
                        self?.statusMessage = "ScreenStocker opened."
                    }
                }
            }
        } else {
            statusMessage = "ScreenStocker app is not installed in Applications."
        }
    }

    func close() {
        onDone?()
    }

    private static func managementAppURL() -> URL? {
        if let bundleURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.tasokiii.ScreenStockerApp") {
            return bundleURL
        }

        let applicationURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent("ScreenStocker.app", isDirectory: true)
        guard FileManager.default.fileExists(atPath: applicationURL.path) else {
            return nil
        }
        return applicationURL
    }
}

private struct ScreenSaverConfigurationView: View {
    @ObservedObject var viewModel: ScreenSaverConfigurationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ScreenStocker")
                .font(.headline)

            Text("Choose the displayed symbol and manage the watchlist in the ScreenStocker app.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                viewModel.openManagementApp()
            } label: {
                Label("Open ScreenStocker", systemImage: "arrow.up.forward.app")
            }

            Text(viewModel.statusMessage.isEmpty ? " " : viewModel.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(minHeight: 20, alignment: .topLeading)

            HStack {
                Spacer()
                Button("Done") {
                    viewModel.close()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, -4)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 22)
        .frame(width: 420)
        .frame(height: 190, alignment: .top)
    }
}
