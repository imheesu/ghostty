import WebKit
import GhosttyKit

/// A WKWebView subclass that correctly forwards Ghostty keybindings
/// to the associated surface view. Without this, when the web view is
/// first responder, Cmd+D and similar shortcuts either don't work or
/// get routed to the wrong pane.
class EditorWKWebView: WKWebView {
    weak var surfaceView: Ghostty.SurfaceView?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Intercept editor-specific shortcuts before WKWebView consumes them.
        // WKWebView handles Cmd+P internally (e.g. Print), preventing it from
        // reaching the menu system where Quick Open is wired.
        if event.type == .keyDown {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // Cmd+P: Quick Open — only intercept if this web view has focus.
            // performKeyEquivalent is called on ALL subviews in the key window,
            // not just the first responder. Without this guard, a BlockNote editor
            // in Pane A would swallow Cmd+P even when Pane B has focus.
            // Use keyCode (hardware scan code) instead of charactersIgnoringModifiers
            // because the latter returns IME-composed characters (e.g. "ㅔ" for Korean IME).
            if flags == .command, event.keyCode == 0x23 /* P */ {
                guard let firstResponder = window?.firstResponder as? NSView,
                      (firstResponder === self || firstResponder.isDescendant(of: self)) else {
                    return false
                }
                surfaceView?.quickOpenVisible.toggle()
                return true
            }

            // Ctrl+C: Close editor and return to terminal.
            if flags == .control, event.keyCode == 0x08 /* C */ {
                surfaceView?.closeEditor(nil)
                return true
            }

            // Cmd+R: Toggle file explorer — WKWebView would consume this as
            // "reload page" so we intercept it and call the action directly.
            if flags == .command, event.keyCode == 0x0F /* R */ {
                surfaceView?.toggleFilePicker(nil)
                return true
            }

            // Cmd+Number (1-9): Let the event propagate up the responder chain
            // for macOS native tab switching. Uses keyCode for IME compatibility.
            // keyCodes: 1=0x12, 2=0x13, 3=0x14, 4=0x15, 5=0x17, 6=0x16, 7=0x1A, 8=0x1C, 9=0x19
            let digitKeyCodes: Set<UInt16> = [0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19]
            if flags == .command, digitKeyCodes.contains(event.keyCode) {
                return false
            }

        }

        // Let WKWebView handle the event first — this forwards it to the web
        // content process, triggering DOM events (copy, paste, selectAll, etc.)
        // that BlockNote's contenteditable relies on.
        if super.performKeyEquivalent(with: event) {
            return true
        }

        // Standard editing shortcuts (Cmd+C/V/X/A/Z, Cmd+Shift+Z):
        // super.performKeyEquivalent didn't handle them, and the Edit menu
        // lacks keyEquivalents (terminal app), so dispatch directly via
        // NSApp.sendAction to the current first responder (WKWebView content).
        // Uses keyCode (hardware scan code) instead of charactersIgnoringModifiers
        // for Korean IME compatibility — the latter returns composed Hangul characters.
        if event.type == .keyDown {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command {
                switch event.keyCode {
                case 0x08: // C
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)
                    return true
                case 0x09: // V
                    NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
                    return true
                case 0x07: // X
                    NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self)
                    return true
                case 0x00: // A
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self)
                    return true
                case 0x06: // Z
                    NSApp.sendAction(Selector(("undo:")), to: nil, from: self)
                    return true
                default: break
                }
            }
            if flags == [.command, .shift] && event.keyCode == 0x06 /* Z */ {
                NSApp.sendAction(Selector(("redo:")), to: nil, from: self)
                return true
            }
        }

        // Only process key-down events.
        guard event.type == .keyDown else { return false }

        // Check if this event matches a Ghostty keybinding on the associated surface.
        guard let surface = surfaceView?.surface else {
            return false
        }

        var ghosttyEvent = event.ghosttyKeyEvent(GHOSTTY_ACTION_PRESS)
        let isBinding: Bool = (event.characters ?? "").withCString { ptr in
            ghosttyEvent.text = ptr
            var flags = ghostty_binding_flags_e(0)
            return ghostty_surface_key_is_binding(surface, ghosttyEvent, &flags)
        }

        guard isBinding else { return false }

        // Forward the key event to the correct surface.
        var keyEvent = event.ghosttyKeyEvent(GHOSTTY_ACTION_PRESS)
        (event.characters ?? "").withCString { ptr in
            keyEvent.text = ptr
            ghostty_surface_key(surface, keyEvent)
        }
        return true
    }
}
