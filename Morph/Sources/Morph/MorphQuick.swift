import SwiftUI
import AppKit
import Carbon
import CoreGraphics
import UniformTypeIdentifiers

// Reliable v0.3 entry point: Option + Command + M reads Finder's selected files.
// Global drag observation is experimental; actual file payloads are received
// only through standard macOS drop targets on the wheel.
@MainActor
final class MorphDelegate: NSObject, NSApplicationDelegate {
    let quick = MorphQuickController()
    var reopenMainWindow: (() -> Void)?
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            reopenMainWindow?()
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationDidFinishLaunching(_ notification: Notification) {
        quick.installHotkey()
        quick.installShiftDragMonitor()
    }
}

private func morphHotkeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let controller = Unmanaged<MorphQuickController>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async { controller.showForFinderSelection() }
    return noErr
}

@MainActor final class QuickState: ObservableObject {
    @Published var files: [URL] = []
    @Published var busy = false
    @Published var message = "Selecteer een bestand in Finder"
    weak var controller: MorphQuickController?
    var formats: [String] {
        guard let first = files.first else { return [] }
        let kinds = Set(files.map { Engine.kind($0) })
        guard kinds.count == 1 else { return [] }
        return Engine.targets(for: Engine.kind(first))
    }
    func convert(to format: String, droppedFiles: [URL]? = nil) {
        let selectedFiles = droppedFiles ?? files
        guard !busy, !selectedFiles.isEmpty else { return }
        busy = true
        message = "Converteren naar \(format.uppercased())..."
        let items = selectedFiles
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> ([URL], [String]) in
                var successes: [URL] = []
                var errors: [String] = []
                for url in items {
                    let job = Job(url: url, kind: Engine.kind(url), target: format)
                    do { successes.append(try Engine.convert(job, quality: 0.9)) }
                    catch { errors.append("\(url.lastPathComponent): \(error.localizedDescription)") }
                }
                return (successes, errors)
            }.value
            busy = false
            if !result.0.isEmpty {
                controller?.store?.history.insert(contentsOf: result.0, at: 0)
                NSWorkspace.shared.activateFileViewerSelecting(result.0)
            }
            message = result.1.isEmpty ? "Klaar: \(result.0.count) bestand(en)" : result.1.joined(separator: "\n")
            // Sluit Morph Quick automatisch na een volledig geslaagde conversie.
            // Bij fouten blijft het venster open zodat de foutmelding zichtbaar is.
            if result.1.isEmpty && !result.0.isEmpty {
                controller?.hide()
            }
        }
    }
}

@MainActor final class MorphQuickController: NSObject {
    let state = QuickState()
    weak var store: MorphStore?
    private var panel: NSPanel?
    private var hotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var dragMonitor: Any?
    private var modifierMonitor: Any?
    private var lastDragTime = Date.distantPast
    private var lastTrigger = Date.distantPast

    // Listen to modifier changes *while the mouse is held down*, rather than
    // waiting for another drag event (which Finder may not deliver to us).
    // We do not intercept or alter Finder's events.
    func installShiftDragMonitor() {
        guard dragMonitor == nil, modifierMonitor == nil else { return }
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.lastDragTime = Date()
                self.maybeShowQuick(modifiers: event.modifierFlags)
            }
        }
        modifierMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.maybeShowQuick(modifiers: event.modifierFlags)
            }
        }
    }

    private func maybeShowQuick(modifiers: NSEvent.ModifierFlags) {
        guard modifiers.contains([.control, .shift]),
              CGEventSource.buttonState(.combinedSessionState, button: .left),
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder",
              Date().timeIntervalSince(lastDragTime) < 1.5,
              Date().timeIntervalSince(lastTrigger) > 2 else { return }
        lastTrigger = Date()
        showForFinderSelection()
        state.message = "Control + Shift herkend. Sleep naar een formaat of klik erop."
    }

    func attach(store: MorphStore) { self.store = store; state.controller = self }
    func installHotkey() {
        let spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), morphHotkeyHandler, 1, [spec], pointer, &handler)
        let identifier = EventHotKeyID(signature: 0x4D525048, id: 1) // MRPH
        RegisterEventHotKey(UInt32(kVK_ANSI_M), UInt32(optionKey | cmdKey), identifier, GetApplicationEventTarget(), 0, &hotkey)
    }
    func showForFinderSelection() {
        // The Finder automation permission prompt is managed by macOS.
        let script = NSAppleScript(source: """
        tell application "Finder"
            set selectedItems to selection
            set outputPaths to {}
            repeat with selectedItem in selectedItems
                set end of outputPaths to POSIX path of (selectedItem as alias)
            end repeat
            return outputPaths
        end tell
        """)
        var error: NSDictionary?
        let value = script?.executeAndReturnError(&error)
        let count = value?.numberOfItems ?? 0
        var urls: [URL] = []
        if count > 0 {
            for index in 1...count {
                if let path = value?.atIndex(index)?.stringValue {
                    urls.append(URL(fileURLWithPath: path))
                }
            }
        }
        state.files = urls.filter { !$0.hasDirectoryPath && !Engine.targets(for: Engine.kind($0)).isEmpty }
        if let error {
            state.message = "Finder-toegang nodig. Sta Morph toe onder Privacy en beveiliging > Automatisering. (\(error["NSAppleScriptErrorNumber"] ?? "?") )"
        } else if state.files.isEmpty {
            state.message = "Selecteer eerst één of meer ondersteunde bestanden in Finder."
        } else if state.formats.isEmpty {
            state.message = "Selecteer bestanden van hetzelfde type."
        } else {
            state.message = "\(state.files.count) bestand(en) geselecteerd"
        }
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 660),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .floating
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.contentView = NSHostingView(rootView: MorphQuickWheel(state: state))
            panel = p
        }
        if let panel {
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
            let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
            let x = min(max(mouse.x - 310, visible.minX), visible.maxX - 620)
            let y = min(max(mouse.y - 330, visible.minY), visible.maxY - 660)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
            panel.orderFrontRegardless()
        }
    }
    func hide() { panel?.orderOut(nil) }
}

private struct MorphQuickWheel: View {
    @ObservedObject var state: QuickState
    @State private var hoveredFormat: String?
    private let purple = Color(red: 0.67, green: 0.22, blue: 1)
    private let dark = Color(red: 0.035, green: 0.014, blue: 0.095)
    // Same clockwise layout as the reference image.
    private let preferredOrder = ["jpg", "webp", "tiff", "bmp", "gif", "heic", "pdf", "png"]

    private var orderedFormats: [String] {
        let available = state.formats
        let preferred = preferredOrder.filter { available.contains($0) }
        return preferred + available.filter { !preferred.contains($0) }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("MORPH QUICK")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .tracking(3)
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Button { state.controller?.hide() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.08), in: Circle())
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 28)
            .padding(.top, 17)

            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0.14, green: 0.05, blue: 0.32), dark], center: .center, startRadius: 20, endRadius: 280))
                    .overlay(Circle().stroke(purple.opacity(0.85), lineWidth: 1.4))
                    .shadow(color: purple.opacity(0.55), radius: 24)
                    .frame(width: 554, height: 554)
                Circle()
                    .stroke(Color(red: 0.55, green: 0.25, blue: 0.9).opacity(0.12), lineWidth: 1)
                    .frame(width: 268, height: 268)

                if let path = Bundle.main.path(forResource: "MorphIcon", ofType: "png"),
                   let icon = NSImage(contentsOfFile: path) {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 225, height: 225)
                        .clipShape(Circle())
                        .shadow(color: purple.opacity(0.7), radius: 20)
                } else {
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.system(size: 100))
                        .foregroundColor(purple)
                }

                ForEach(Array(orderedFormats.prefix(8).enumerated()), id: \.offset) { item in
                    formatTarget(item.element, index: item.offset, count: min(8, orderedFormats.count))
                }
            }
            .frame(width: 570, height: 570)

            HStack(spacing: 8) {
                if state.busy { ProgressView().controlSize(.small).tint(purple) }
                Text(state.message)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity, minHeight: 34)
            .padding(.horizontal, 30)
        }
        .frame(width: 620, height: 660)
        .background(Color.clear)
    }

    private func formatTarget(_ format: String, index: Int, count: Int) -> some View {
        let angle = Double(index) / Double(max(count, 1)) * .pi * 2 - .pi / 2
        let selected = hoveredFormat == format
        let top = index == 0
        let diameter: CGFloat = top ? 118 : 100
        let base = Color(red: 0.075, green: 0.045, blue: 0.16)
        return Button { state.convert(to: format) } label: {
            VStack(spacing: 7) {
                Image(systemName: icon(for: format))
                    .font(.system(size: top ? 32 : 27, weight: .light))
                Text(format.uppercased())
                    .font(.system(size: top ? 18 : 16, weight: .semibold, design: .rounded))
            }
            .foregroundColor(.white)
            .frame(width: diameter, height: diameter)
            .background {
                Circle()
                    .fill(selected || top ? purple.opacity(0.26) : base)
                    .overlay(Circle().stroke(purple.opacity(selected || top ? 1 : 0.45), lineWidth: selected || top ? 2.5 : 1))
                    .shadow(color: purple.opacity(selected || top ? 0.85 : 0.12), radius: selected || top ? 19 : 4)
            }
            .scaleEffect(selected ? 1.07 : 1)
        }
        .buttonStyle(.plain)
        .disabled(state.busy)
        .onHover { hoveredFormat = $0 ? format : nil }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
            guard !state.busy else { return false }
            let group = DispatchGroup()
            let lock = NSLock()
            var dropped: [URL] = []
            for provider in providers where provider.canLoadObject(ofClass: URL.self) {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { object, _ in
                    if let url = object, url.isFileURL {
                        lock.lock(); dropped.append(url); lock.unlock()
                    }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                let supported = dropped.filter {
                    !$0.hasDirectoryPath && Engine.targets(for: Engine.kind($0)).contains(format)
                }
                if supported.isEmpty {
                    state.message = "Geen ondersteunde bestanden voor \(format.uppercased()) ontvangen."
                } else if supported.count != dropped.count {
                    state.message = "Niet alle bestanden ondersteunen dit formaat."
                } else {
                    state.convert(to: format, droppedFiles: supported)
                }
            }
            return !providers.isEmpty
        }
        .offset(x: cos(angle) * 218, y: sin(angle) * 218)
    }

    private func icon(for format: String) -> String {
        switch format.lowercased() {
        case "pdf", "jpg": return "doc.text"
        case "png", "webp", "heic", "tiff", "gif", "bmp": return "photo"
        case "mp4", "mov", "mkv", "avi", "webm": return "film"
        case "mp3", "wav", "m4a", "flac", "aac": return "waveform"
        case "zip", "7z", "tar": return "archivebox"
        default: return "doc"
        }
    }
}
