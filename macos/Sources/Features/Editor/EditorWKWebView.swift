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

            // Cmd+B: Close editor and return to terminal.
            if flags == .command, event.charactersIgnoringModifiers == "b" {
                surfaceView?.closeEditor(nil)
                return true
            }
        }

        // Let WKWebView handle standard editing shortcuts (Cmd+C/V/X/A/Z etc.) first.
        if super.performKeyEquivalent(with: event) {
            return true
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
