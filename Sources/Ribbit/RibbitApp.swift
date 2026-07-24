import AppKit
import SwiftUI

@main
struct RibbitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: AppSettings
    @StateObject private var model: AppModel

    init() {
        let settings = AppSettings.shared
        _settings = StateObject(wrappedValue: settings)
        _model = StateObject(wrappedValue: AppModel(settings: settings))
    }

    var body: some Scene {
        WindowGroup("ribbit", id: "main") {
            RibbitSceneRoot(
                model: model,
                settings: settings,
                appDelegate: appDelegate
            )
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("new terminal") { model.newTerminal() }
                    .keyboardShortcut("t", modifiers: .command)
                Button("new note") { model.newNote() }
                    .keyboardShortcut("n", modifiers: .command)
                Divider()
                Button("ribbit in existing folder…") { model.chooseProjectFolder() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button("save note") { model.saveSelectedNote() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(model.selectedTab?.kind != .note)
                Button("save terminal transcript as note") { model.saveSelectedTerminalAsNote() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(model.selectedTab?.kind != .terminal || model.selectedProjectID == nil)
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("find in terminal…") { model.findInSelectedTerminal() }
                    .keyboardShortcut("f", modifiers: .command)
                    .disabled(model.selectedTab?.kind != .terminal)
            }
            CommandGroup(replacing: .windowList) {
                Button("close tab") { model.closeSelectedTab() }
                    .keyboardShortcut("w", modifiers: .command)
                Divider()
                Button("previous tab") { model.selectPreviousTab() }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                Button("next tab") { model.selectNextTab() }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                Divider()
                ForEach(1...9, id: \.self) { number in
                    Button("select tab \(number)") {
                        model.selectTab(at: number - 1)
                    }
                    .keyboardShortcut(
                        KeyEquivalent(Character(String(number))),
                        modifiers: .command
                    )
                    .disabled(model.visibleTabs.count < number)
                }
            }
            CommandMenu("terminal") {
                Button("clear screen") { model.clearSelectedTerminal() }
                    .keyboardShortcut("k", modifiers: .command)
                    .disabled(model.selectedTab?.kind != .terminal)
                Divider()
                Button("increase terminal text size") {
                    model.adjustTerminalFontSize(by: 1)
                }
                .keyboardShortcut("=", modifiers: .command)
                Button("decrease terminal text size") {
                    model.adjustTerminalFontSize(by: -1)
                }
                .keyboardShortcut("-", modifiers: .command)
                Button("reset terminal text size") {
                    model.resetTerminalFontSize()
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }

        Settings {
            SettingsView(settings: settings)
        }
    }
}

private struct RibbitSceneRoot: View {
    @Environment(\.openWindow) private var openWindow

    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    let appDelegate: AppDelegate

    var body: some View {
        RootView(model: model, settings: settings)
            .frame(minWidth: 720, minHeight: 520)
            .preferredColorScheme(.dark)
            .onAppear {
                appDelegate.configure(
                    model: model,
                    settings: settings,
                    reopenMainWindow: {
                        openWindow(id: "main")
                    }
                )
                DispatchQueue.main.async {
                    RibbitWindowConfigurator.configureMainSceneWindows()
                }
            }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var model: AppModel?
    private var notchController: RibbitAgentNotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            RibbitWindowConfigurator.configureMainSceneWindows()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func configure(
        model: AppModel,
        settings: AppSettings,
        reopenMainWindow: @escaping () -> Void
    ) {
        RibbitWindowConfigurator.reopenMainWindow = reopenMainWindow
        guard self.model !== model || notchController == nil else { return }
        notchController?.stop()
        self.model?.stopAgentMonitoring()
        self.model = model
        model.startAgentMonitoring()
        let controller = RibbitAgentNotchController(
            model: model,
            settings: settings
        )
        notchController = controller
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        notchController?.stop()
        model?.stopAgentMonitoring()
        RibbitWindowConfigurator.reopenMainWindow = nil
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            RibbitWindowConfigurator.showMainWindow()
        }
        return true
    }
}
