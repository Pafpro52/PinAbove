import AppKit
import Carbon

private let supportedYabaiVersion = "yabai-v7.1.16"
private let yabaiLocations = ["/opt/homebrew/bin/yabai", "/usr/local/bin/yabai"]

private enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

private func windowLayer(from json: String) throws -> String {
    guard let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
          let layer = object["sub-layer"] as? String,
          ["above", "auto", "normal"].contains(layer) else {
        throw AppError.message("The focused window could not be read.")
    }
    return layer
}

if CommandLine.arguments.contains("--self-test") {
    let validLayer = try windowLayer(from: #"{"sub-layer":"above"}"#)
    assert(validLayer == "above")
    assert((try? windowLayer(from: #"{"sub-layer":42}"#)) == nil)
    print("Self-test passed")
    exit(EXIT_SUCCESS)
}

final class AppController: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let popover = NSPopover()
    private let statusLight = NSImageView()
    private let statusButton = NSButton()
    private let shortcutButton = NSButton()
    private let worker = DispatchQueue(label: "app.pinabove.yabai", qos: .userInitiated)
    private var statusItem: NSStatusItem!
    private var yabaiIsRunning = false
    private var hotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var recordingMonitor: Any?
    private var registeredKeyCode = UInt32(kVK_ANSI_T)
    private var registeredModifiers = UInt32(controlKey | cmdKey)

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildPopover()
        buildStatusItem()
        installHotKeyHandler()
        registerSavedHotKey()
        checkYabai()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
        stopRecordingShortcut()
    }

    func popoverDidClose(_ notification: Notification) {
        stopRecordingShortcut()
        shortcutButton.title = savedShortcutName()
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "PinAbove")
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "PinAbove"
    }

    private func buildPopover() {
        let controller = NSViewController()
        controller.preferredContentSize = NSSize(width: 320, height: 170)
        let view = NSView(frame: NSRect(origin: .zero, size: controller.preferredContentSize))

        let title = NSTextField(labelWithString: "PinAbove")
        title.font = .boldSystemFont(ofSize: 17)
        title.alignment = .center
        title.frame = NSRect(x: 20, y: 132, width: 280, height: 24)

        let shortcutLabel = NSTextField(labelWithString: "Global Shortcut")
        shortcutLabel.frame = NSRect(x: 20, y: 94, width: 115, height: 22)
        shortcutButton.title = savedShortcutName()
        shortcutButton.target = self
        shortcutButton.action = #selector(startRecordingShortcut)
        shortcutButton.frame = NSRect(x: 140, y: 89, width: 160, height: 30)

        let statusLabel = NSTextField(labelWithString: "yabai Status")
        statusLabel.frame = NSRect(x: 20, y: 47, width: 115, height: 22)
        statusLight.frame = NSRect(x: 142, y: 50, width: 16, height: 16)
        statusButton.target = self
        statusButton.action = #selector(statusButtonClicked)
        statusButton.frame = NSRect(x: 180, y: 42, width: 120, height: 30)

        [title, shortcutLabel, shortcutButton, statusLabel, statusLight, statusButton]
            .forEach(view.addSubview)
        controller.view = view
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.delegate = self
        updateYabaiStatus(false)
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent, let button = statusItem.button else { return }
        if event.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Quit PinAbove", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 3), in: button)
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            checkYabai()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func statusButtonClicked() {
        yabaiIsRunning ? checkYabai() : startYabai()
    }

    private func checkYabai() {
        worker.async {
            let running = (try? self.requireCompatibleYabai()) != nil
                && (try? self.runYabai(["-m", "query", "--displays"])) != nil
            DispatchQueue.main.async { self.updateYabaiStatus(running) }
        }
    }

    private func startYabai() {
        statusButton.isEnabled = false
        worker.async {
            do {
                try self.requireCompatibleYabai()
                _ = try self.runYabai(["--start-service"])
                for _ in 0..<20 {
                    if (try? self.runYabai(["-m", "query", "--displays"])) != nil {
                        DispatchQueue.main.async { self.updateYabaiStatus(true) }
                        return
                    }
                    Thread.sleep(forTimeInterval: 0.1)
                }
                throw AppError.message("yabai did not start in time. Check its Accessibility permission.")
            } catch { DispatchQueue.main.async { self.fail(error) } }
        }
    }

    private func updateYabaiStatus(_ running: Bool) {
        yabaiIsRunning = running
        let image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: running ? "yabai is running" : "yabai is stopped")
        image?.isTemplate = true
        statusLight.image = image
        statusLight.contentTintColor = running ? .systemGreen : .systemRed
        statusButton.title = running ? "Check" : "Start"
        statusButton.isEnabled = true
    }

    private func installHotKeyHandler() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, data in
            guard let data else { return noErr }
            Unmanaged<AppController>.fromOpaque(data).takeUnretainedValue().toggleFocusedWindow()
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
    }

    private func toggleFocusedWindow() {
        worker.async {
            do {
                try self.requireCompatibleYabai()
                let query = try self.runYabai(["-m", "query", "--windows", "--window"])
                let target = try windowLayer(from: query) == "above" ? "auto" : "above"
                _ = try self.runYabai(["-m", "window", "--sub-layer", target])
                DispatchQueue.main.async { self.updateYabaiStatus(true) }
            } catch { DispatchQueue.main.async { self.fail(error) } }
        }
    }

    @objc private func startRecordingShortcut() {
        stopRecordingShortcut()
        shortcutButton.title = "Press shortcut…"
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.recordShortcut(event)
            return nil
        }
    }

    private func recordShortcut(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        guard modifiers != 0 else { shortcutButton.title = "Add a modifier key"; return }

        let oldCode = registeredKeyCode
        let oldModifiers = registeredModifiers
        guard registerHotKey(UInt32(event.keyCode), modifiers) else {
            _ = registerHotKey(oldCode, oldModifiers, showError: false)
            return
        }

        let name = shortcutName(flags, event.charactersIgnoringModifiers?.uppercased() ?? "?")
        let defaults = UserDefaults.standard
        defaults.set(Int(event.keyCode), forKey: "keyCode")
        defaults.set(Int(modifiers), forKey: "modifiers")
        defaults.set(name, forKey: "shortcutName")
        shortcutButton.title = name
        stopRecordingShortcut()
    }

    private func stopRecordingShortcut() {
        if let recordingMonitor { NSEvent.removeMonitor(recordingMonitor); self.recordingMonitor = nil }
    }

    private func registerSavedHotKey() {
        let defaults = UserDefaults.standard
        let code = defaults.object(forKey: "keyCode") == nil ? UInt32(kVK_ANSI_T) : UInt32(defaults.integer(forKey: "keyCode"))
        let modifiers = defaults.object(forKey: "modifiers") == nil ? UInt32(controlKey | cmdKey) : UInt32(defaults.integer(forKey: "modifiers"))
        if registerHotKey(code, modifiers) {
            defaults.set(Int(code), forKey: "keyCode")
            defaults.set(Int(modifiers), forKey: "modifiers")
        }
    }

    @discardableResult
    private func registerHotKey(_ code: UInt32, _ modifiers: UInt32, showError shouldShowError: Bool = true) -> Bool {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        let id = EventHotKeyID(signature: 0x50414256, id: 1) // "PABV"
        let status = RegisterEventHotKey(code, modifiers, id, GetApplicationEventTarget(), 0, &hotKey)
        if status == noErr {
            registeredKeyCode = code
            registeredModifiers = modifiers
        } else if shouldShowError {
            showError("This shortcut is unavailable. It may be used by another app.")
        }
        return status == noErr
    }

    private func savedShortcutName() -> String {
        UserDefaults.standard.string(forKey: "shortcutName") ?? "⌃⌘T"
    }

    private func shortcutName(_ flags: NSEvent.ModifierFlags, _ key: String) -> String {
        (flags.contains(.control) ? "⌃" : "")
            + (flags.contains(.option) ? "⌥" : "")
            + (flags.contains(.shift) ? "⇧" : "")
            + (flags.contains(.command) ? "⌘" : "") + key
    }

    private func yabaiPath() throws -> String {
        guard let path = yabaiLocations.first(where: FileManager.default.isExecutableFile) else {
            throw AppError.message("yabai was not found at a supported location.")
        }
        return path
    }

    private func requireCompatibleYabai() throws {
        let version = try runYabai(["--version"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard version == supportedYabaiVersion else {
            throw AppError.message("PinAbove requires \(supportedYabaiVersion). Found: \(version)")
        }
    }

    private func runYabai(_ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        let finished = DispatchSemaphore(value: 0)
        process.executableURL = URL(fileURLWithPath: try yabaiPath())
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() }
        catch { throw AppError.message("yabai could not start: \(error.localizedDescription)") }
        guard finished.wait(timeout: .now() + 5) == .success else {
            process.terminate()
            throw AppError.message("The yabai command timed out.")
        }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let errorText = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw AppError.message(errorText.isEmpty ? "The yabai command failed." : errorText)
        }
        return text
    }

    private func fail(_ error: Error) {
        updateYabaiStatus(false)
        showError(error.localizedDescription)
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "PinAbove"
        alert.informativeText = message
        alert.runModal()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = AppController()
app.delegate = controller

let menu = NSMenu()
let item = NSMenuItem()
let submenu = NSMenu()
submenu.addItem(withTitle: "Quit PinAbove", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
item.submenu = submenu
menu.addItem(item)
app.mainMenu = menu
app.run()
