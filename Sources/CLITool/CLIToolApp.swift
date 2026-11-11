import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DotfileStore.shared.applyTheme()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let store = DotfileStore.shared
        guard store.hasUnsavedChanges else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "You have unsaved changes"
        alert.informativeText = "Save your edits before quitting CLITool?"
        alert.addButton(withTitle: "Save All")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            store.saveAll()
            return store.hasUnsavedChanges ? .terminateCancel : .terminateNow
        case .alertSecondButtonReturn:
            return .terminateCancel
        default:
            return .terminateNow
        }
    }
}

@main
struct CLIToolApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = DotfileStore.shared

    var body: some Scene {
        Window("CLITool", id: "main") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 860, minHeight: 480)
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(replacing: .saveItem) {
                Button("Save") { store.save() }
                    .keyboardShortcut("s")
                    .disabled(!store.isSelectionDirty)
                Button("Reload from Disk") { store.requestReload() }
                    .keyboardShortcut("r")
                Divider()
                Button("Take Snapshot") { store.takeSnapshot(note: "") }
                    .keyboardShortcut("b")
                Button("Snapshot All Files") { store.snapshotAll() }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                Divider()
                Button("Check Syntax") { store.checkSyntax() }
                    .keyboardShortcut("k")
                    .disabled(store.selectedFile?.syntaxShell == nil)
                Button("New Terminal Window") { store.openNewTerminal() }
                    .keyboardShortcut("t")
            }
            CommandGroup(after: .toolbar) {
                Button(store.theme == .dark ? "Use Light Theme" : "Use Dark Theme") {
                    store.theme = store.theme.toggled
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }
    }
}
