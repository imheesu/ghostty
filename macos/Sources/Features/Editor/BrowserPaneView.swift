import SwiftUI
import WebKit

/// Observable object that bridges the header bar controls to the underlying WKWebView.
/// The Coordinator sets `webView` once in `makeNSView`; the header reads published state.
class BrowserActions: ObservableObject {
    weak var webView: WKWebView? {
        didSet { startObserving() }
    }

    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var currentURL: String = ""

    private var observations: [NSKeyValueObservation] = []

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }
    func stopLoading() { webView?.stopLoading() }

    private func startObserving() {
        observations.removeAll()
        guard let wv = webView else { return }

        observations.append(wv.observe(\.canGoBack, options: [.initial, .new]) { [weak self] wv, _ in
            DispatchQueue.main.async { self?.canGoBack = wv.canGoBack }
        })
        observations.append(wv.observe(\.canGoForward, options: [.initial, .new]) { [weak self] wv, _ in
            DispatchQueue.main.async { self?.canGoForward = wv.canGoForward }
        })
        observations.append(wv.observe(\.isLoading, options: [.initial, .new]) { [weak self] wv, _ in
            DispatchQueue.main.async { self?.isLoading = wv.isLoading }
        })
        observations.append(wv.observe(\.url, options: [.initial, .new]) { [weak self] wv, _ in
            DispatchQueue.main.async { self?.currentURL = wv.url?.absoluteString ?? "" }
        })
    }
}

/// In-pane web browser view with navigation header and embedded WKWebView.
struct BrowserPaneView: View {
    @ObservedObject var editorState: EditorState
    let surfaceView: Ghostty.SurfaceView
    let url: URL
    let onClose: () -> Void

    @StateObject private var actions = BrowserActions()
    @State private var addressText: String = ""
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 0) {
            // Navigation header
            HStack(spacing: 6) {
                // Back / Forward
                Button(action: { actions.goBack() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(!actions.canGoBack)
                .help("Back")

                Button(action: { actions.goForward() }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(!actions.canGoForward)
                .help("Forward")

                // Reload / Stop
                Button(action: { actions.isLoading ? actions.stopLoading() : actions.reload() }) {
                    Image(systemName: actions.isLoading ? "xmark" : "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .help(actions.isLoading ? "Stop" : "Reload")

                // Address bar
                TextField("Enter URL…", text: $addressText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .onSubmit {
                        navigateToAddress()
                    }

                // Close button
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .opacity(isHovering ? 1.0 : 0.6)
                }
                .buttonStyle(.plain)
                .onHover { hovering in isHovering = hovering }
                .help("Close browser")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)

            // Web content
            BrowserWebView(
                url: url,
                surfaceView: surfaceView,
                actions: actions
            )
        }
        .onAppear {
            addressText = url.absoluteString
        }
        .onChange(of: actions.currentURL) { newURL in
            if !newURL.isEmpty {
                addressText = newURL
            }
        }
    }

    private func navigateToAddress() {
        var text = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Auto-add https:// if no scheme present
        if !text.hasPrefix("http://") && !text.hasPrefix("https://") && !text.hasPrefix("file://") {
            text = "https://" + text
        }

        guard let newURL = URL(string: text) else { return }
        // Navigate directly on the existing WKWebView to preserve
        // back/forward history instead of recreating the view.
        actions.webView?.load(URLRequest(url: newURL))
    }
}

// MARK: - BrowserWebView (NSViewRepresentable)

struct BrowserWebView: NSViewRepresentable {
    let url: URL
    let surfaceView: Ghostty.SurfaceView
    let actions: BrowserActions

    func makeNSView(context: Context) -> EditorWKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = EditorWKWebView(frame: .zero, configuration: config)
        webView.surfaceView = surfaceView
        webView.isBrowserMode = true
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        // Wire up actions
        actions.webView = webView

        // Load initial URL and track it
        context.coordinator.lastLoadedURL = url
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: EditorWKWebView, context: Context) {
        // Only reload when the input URL actually changed (from QuickOpen),
        // not from KVO-driven SwiftUI state updates.
        guard url != context.coordinator.lastLoadedURL else { return }
        context.coordinator.lastLoadedURL = url
        webView.load(URLRequest(url: url))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(actions: actions)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let actions: BrowserActions
        /// Tracks the last URL we programmatically loaded, so updateNSView
        /// can distinguish genuine URL changes from KVO-triggered re-renders.
        var lastLoadedURL: URL?

        init(actions: BrowserActions) {
            self.actions = actions
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            updateState(webView)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            updateState(webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            updateState(webView)

            // Show inline error page (HTML-escape user-controlled strings)
            let desc = htmlEscape(error.localizedDescription)
            let urlStr = htmlEscape(webView.url?.absoluteString ?? "")
            let html = """
            <html>
            <head><style>
                body { font-family: -apple-system; padding: 40px; color: #888;
                       background: transparent; text-align: center; }
                h2 { color: #ccc; }
                code { font-size: 12px; color: #666; }
            </style></head>
            <body>
                <h2>Failed to load page</h2>
                <p>\(desc)</p>
                <code>\(urlStr)</code>
            </body>
            </html>
            """
            webView.loadHTMLString(html, baseURL: nil)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }

        private func htmlEscape(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
             .replacingOccurrences(of: "<", with: "&lt;")
             .replacingOccurrences(of: ">", with: "&gt;")
             .replacingOccurrences(of: "\"", with: "&quot;")
        }

        private func updateState(_ webView: WKWebView) {
            DispatchQueue.main.async { [weak self] in
                self?.actions.canGoBack = webView.canGoBack
                self?.actions.canGoForward = webView.canGoForward
                self?.actions.isLoading = webView.isLoading
                self?.actions.currentURL = webView.url?.absoluteString ?? ""
            }
        }
    }
}
