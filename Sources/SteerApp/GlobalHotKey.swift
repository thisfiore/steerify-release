import AppKit
import Carbon.HIToolbox

/// ⌃⌥N from any app: Steerify comes forward with the New request sheet open.
/// Carbon hot keys need no Accessibility permission and swallow the keystroke only for this combo.
enum GlobalHotKey {
    static let label = "⌃⌥N"
    private static var ref: EventHotKeyRef?
    private static var handler: EventHandlerRef?

    @MainActor static func install(_ model: AppModel) {
        guard ref == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { GlobalHotKey.fire() } }
            return noErr
        }, 1, &spec, nil, &handler)
        let id = EventHotKeyID(signature: OSType(0x53_54_52_46), id: 1)   // 'STRF'
        RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
        Self.model = model
    }

    @MainActor private static weak var model: AppModel?

    /// Bring the main window up, then open the sheet in the project you last had open.
    @MainActor static func fire() {
        guard let m = model else { return }
        NSApp.activate(ignoringOtherApps: true)
        if let open = AppModel.reopenWindow { open() }
        else { NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }?.makeKeyAndOrderFront(nil) }
        if m.project == nil, let first = m.projects.first { m.selectedProjectId = first.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { m.requestOpen = true; m.requestPickProject = true }
    }
}
