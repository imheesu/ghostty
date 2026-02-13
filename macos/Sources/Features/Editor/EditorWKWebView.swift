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

            // Cmd+P: Quick Open — toggle directly because SurfaceView may not
            // be in the responder chain when the editor is active.
            if flags == .command, event.charactersIgnoringModifiers == "p" {
                surfaceView?.quickOpenVisible.toggle()
                return true
            }

            // Ctrl+C: Close editor and return to terminal.
            if flags == .control, event.charactersIgnoringModifiers == "c" {
                surfaceView?.closeEditor(nil)
                return true
            }

            // Cmd+R: Toggle file explorer — WKWebView would consume this as
            // "reload page" so we intercept it and call the action directly.
            if flags == .command, event.charactersIgnoringModifiers == "r" {
                surfaceView?.toggleFilePicker(nil)
                return true
            }

            // Cmd+Number (1-9): Let the event propagate up the responder chain
            // for macOS native tab switching.
            if flags == .command,
               let chars = event.charactersIgnoringModifiers,
               chars.count == 1,
               let scalar = chars.unicodeScalars.first,
               scalar >= "1" && scalar <= "9" {
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
        // If super didn't handle them, return false so the system Edit menu
        // can dispatch them via the responder chain. Do NOT fall through to
        // Ghostty keybinding check — otherwise cmd+c would copy from the
        // terminal surface instead of the editor.
        if event.type == .keyDown {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command || flags == [.command, .shift] {
                if let chars = event.charactersIgnoringModifiers,
                   ["c", "v", "x", "a", "z"].contains(chars) {
                    return false
                }
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
