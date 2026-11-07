import AppKit
import SwiftUI

@main
struct ChocoEditApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = EditorModel()
    @StateObject private var updates = UpdateState.shared

    var body: some Scene {
        WindowGroup("ChocoEdit") {
            ContentView()
                .environmentObject(model)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button(updates.title) { delegate.checkForUpdates() }
                    .disabled(updates.installing)
                Button("Update Source…") { delegate.editUpdateSource() }
                Button("ChocoEdit on GitHub") {
                    if let url = URL(string: "https://github.com/\(AppVersion.repo)") { NSWorkspace.shared.open(url) }
                }
                Button("Error Code List") {
                    if let url = URL(string: ErrorReporter.helpURL) { NSWorkspace.shared.open(url) }
                }
                Text("Version \(AppVersion.version) (built \(AppVersion.built))")
            }
            CommandGroup(replacing: .newItem) {
                Button("Open Settings File…") { model.openFile() }.keyboardShortcut("o")
                Button("Save Settings File…") { model.saveFile() }.keyboardShortcut("s").disabled(model.settings == nil)
            }
            CommandMenu("Pedal") {
                Button("Read from Pedal") { model.readFromPedal() }.keyboardShortcut("r")
                Button("Write to Pedal") { model.writeToPedal() }.keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.settings == nil || !model.isDirty)
                Button("Revert to Pedal") { model.revert() }.disabled(model.baseline == nil || !model.isDirty)
                Divider()
                Button("Refresh Ports") { model.refreshPorts() }
                Button("Show Backups") { NSWorkspace.shared.open(EditorModel.backupFolder) }
            }
        }
    }
}

/// Update menu state shown in the app menu.
final class UpdateState: ObservableObject {
    static let shared = UpdateState()
    @Published var title = "Check for Updates…"
    @Published var installing = false

    func refresh(checking: Bool = false) {
        if installing { title = "Installing Update…" }
        else if checking { title = "Checking for Updates…" }
        else if let m = Updater.shared.available { title = "⬆︎ Install Update to v\(m.version)…" }
        else { title = "Check for Updates…" }
        if let tile = NSApp?.dockTile { tile.badgeLabel = Updater.shared.available != nil ? "↑" : nil }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Updater.shared.onChange = { UpdateState.shared.refresh() }
        Updater.shared.startAutomaticChecks()
        reportFailedUpdateIfAny()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func checkForUpdates() {
        if let m = Updater.shared.available { offerInstall(m); return }
        UpdateState.shared.refresh(checking: true)
        Updater.shared.check { [weak self] result in
            UpdateState.shared.refresh()
            switch result {
            case .success(let m?):
                self?.offerInstall(m)
            case .success(nil):
                let alert = NSAlert()
                alert.messageText = "ChocoEdit is up to date"
                alert.informativeText = "You're running v\(AppVersion.version), the newest version available."
                alert.runModal()
            case .failure(let error):
                self?.showUpdateError(error)
            }
        }
    }

    private func offerInstall(_ m: UpdateManifest) {
        let alert = NSAlert()
        alert.messageText = "Update to ChocoEdit v\(m.version)?"
        var info = "You have v\(AppVersion.version)."
        if let notes = m.notes, !notes.isEmpty { info += "\n\nWhat's new:\n\(notes)" }
        info += "\n\nChocoEdit will quit, update itself and reopen. Your backups and settings files are kept."
            + " Write any unsaved edits to the pedal or save them to a file first."
            + "\n\nNo permissions need granting again: ChocoEdit uses none."
        alert.informativeText = info
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        UpdateState.shared.installing = true
        UpdateState.shared.refresh()
        Updater.shared.install(m) { [weak self] error in
            UpdateState.shared.installing = false
            UpdateState.shared.refresh()
            self?.showUpdateError(error)
        }
    }

    private func showUpdateError(_ error: Error) {
        let e = AppError(wrapping: error)
        ErrorReporter.shared.log(e)
        let sourceProblem = e.code == .noUpdateSource || e.code == .badUpdateSource
        let picked = ErrorReporter.shared.present(e, title: "Couldn't update ChocoEdit",
                                                  actions: sourceProblem ? ["Set Update Source…"] : [])
        if picked == 0 { editUpdateSource() }
    }

    private func reportFailedUpdateIfAny() {
        let marker = Updater.swapFailureMarker
        guard let text = try? String(contentsOf: marker, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(at: marker)
        let parts = text.split(separator: "|", maxSplits: 1).map(String.init)
        let code = parts.first.flatMap { ErrorCode(rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            ?? .updateSwapFailed
        ErrorReporter.shared.report(AppError(code, parts.count > 1 ? parts[1] : nil),
                                    surface: .alert, title: "Couldn't install the update")
    }

    func editUpdateSource() {
        let alert = NSAlert()
        alert.messageText = "Update Source"
        alert.informativeText = "Where ChocoEdit looks for new versions: a web link or a file path to a latest.json feed. "
            + "Leave it empty to use the built-in source"
            + (AppVersion.updateFeed.isEmpty ? " (none in this build)." : ":\n\(AppVersion.updateFeed)")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        field.stringValue = UserDefaults.standard.string(forKey: "updateFeed") ?? ""
        field.placeholderString = AppVersion.updateFeed.isEmpty ? "https://…/latest.json" : AppVersion.updateFeed
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty && Updater.url(from: value) == nil {
            showUpdateError(AppError(.badUpdateSource, value))
            return
        }
        Updater.shared.feed = value
        Updater.shared.check { _ in }
    }
}
