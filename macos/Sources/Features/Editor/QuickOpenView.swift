import SwiftUI

/// Quick Open overlay for fuzzy file search (Cmd+P).
/// Follows the CommandPaletteView pattern: TextField + results list + keyboard navigation.
struct QuickOpenView: View {
    @Binding var isPresented: Bool
    let rootDirectory: URL
    let recentFiles: [String]
    let onFileSelected: (URL) -> Void

    @State private var query = ""
    @State private var selectedIndex: UInt?
    @State private var allPaths: [String] = []
    @State private var isScanning = true
    @FocusState private var isTextFieldFocused: Bool

    private var displayedResults: [FuzzyMatcher.Result] {
        if query.isEmpty {
            return recentFiles.prefix(9).map {
                FuzzyMatcher.Result(path: $0, score: 0, matchedIndices: [])
            }
        }
        return FuzzyMatcher.match(query: query, paths: allPaths)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search field with hidden keyboard shortcut buttons
            QuickOpenSearchField(query: $query, isTextFieldFocused: _isTextFieldFocused) { event in
                switch event {
                case .exit:
                    isPresented = false

                case .submit:
                    submitSelection()

                case .move(.up):
                    moveSelection(up: true)

                case .move(.down):
                    moveSelection(up: false)

                case .move(_):
                    break

                case .selectIndex(let index):
                    selectItemAtIndex(index)
                }
            }
            .onChange(of: query) { newValue in
                if !newValue.isEmpty {
                    if selectedIndex == nil {
                        selectedIndex = 0
                    }
                } else {
                    // When clearing query, auto-select first recent file if available
                    selectedIndex = recentFiles.isEmpty ? nil : 0
                }
            }

            Divider()

            // Results list
            if isScanning && allPaths.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Scanning files…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding()
            } else if query.isEmpty && recentFiles.isEmpty {
                Text("Type to search files")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .padding()
            } else if query.isEmpty {
                // Recent files section
                VStack(alignment: .leading, spacing: 0) {
                    Text("Recent Files")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    QuickOpenResultsList(
                        results: displayedResults,
                        rootDirectory: rootDirectory,
                        selectedIndex: $selectedIndex,
                        showShortcutBadges: true,
                        onSelect: { result in
                            let url = rootDirectory.appendingPathComponent(result.path)
                            isPresented = false
                            onFileSelected(url)
                        }
                    )
                }
            } else {
                QuickOpenResultsList(
                    results: displayedResults,
                    rootDirectory: rootDirectory,
                    selectedIndex: $selectedIndex,
                    showShortcutBadges: true,
                    onSelect: { result in
                        let url = rootDirectory.appendingPathComponent(result.path)
                        isPresented = false
                        onFileSelected(url)
                    }
                )
            }
        }
        .frame(maxWidth: 500)
        .background(
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                Rectangle()
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .blendMode(.color)
            }
            .compositingGroup()
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .tertiaryLabelColor).opacity(0.75))
        )
        .shadow(radius: 32, x: 0, y: 12)
        .padding()
        .onChange(of: isPresented) { newValue in
            isTextFieldFocused = newValue
            if !isPresented {
                query = ""
                selectedIndex = nil
            } else {
                // Auto-select first item when opening with recent files
                if !recentFiles.isEmpty {
                    selectedIndex = 0
                }
            }
        }
        .task {
            isTextFieldFocused = isPresented
            // Auto-select first recent file on open
            if !recentFiles.isEmpty {
                selectedIndex = 0
            }
            allPaths = await FileScanner.scan(root: rootDirectory)
            isScanning = false
        }
    }

    private func submitSelection() {
        let results = displayedResults
        guard !results.isEmpty else { return }
        let index = Int(selectedIndex ?? 0)
        let safeIndex = min(index, results.count - 1)
        let result = results[safeIndex]
        let url = rootDirectory.appendingPathComponent(result.path)
        isPresented = false
        onFileSelected(url)
    }

    private func moveSelection(up: Bool) {
        let results = displayedResults
        guard !results.isEmpty else { return }
        let count = UInt(results.count)
        if up {
            let current = selectedIndex ?? count
            selectedIndex = (current == 0) ? count - 1 : current - 1
        } else {
            let current = selectedIndex ?? UInt.max
            selectedIndex = (current >= count - 1) ? 0 : current + 1
        }
    }

    private func selectItemAtIndex(_ index: Int) {
        let results = displayedResults
        guard index < results.count else { return }
        let result = results[index]
        let url = rootDirectory.appendingPathComponent(result.path)
        isPresented = false
        onFileSelected(url)
    }
}

// MARK: - Search Field

fileprivate struct QuickOpenSearchField: View {
    @Binding var query: String
    var onEvent: ((KeyboardEvent) -> Void)?
    @FocusState private var isTextFieldFocused: Bool

    init(query: Binding<String>, isTextFieldFocused: FocusState<Bool>, onEvent: ((KeyboardEvent) -> Void)?) {
        _query = query
        self.onEvent = onEvent
        _isTextFieldFocused = isTextFieldFocused
    }

    enum KeyboardEvent {
        case exit
        case submit
        case move(MoveCommandDirection)
        case selectIndex(Int)
    }

    var body: some View {
        ZStack {
            Group {
                Button { onEvent?(.move(.up)) } label: { Color.clear }
                    .buttonStyle(PlainButtonStyle())
                    .keyboardShortcut(.upArrow, modifiers: [])
                Button { onEvent?(.move(.down)) } label: { Color.clear }
                    .buttonStyle(PlainButtonStyle())
                    .keyboardShortcut(.downArrow, modifiers: [])
                Button { onEvent?(.move(.up)) } label: { Color.clear }
                    .buttonStyle(PlainButtonStyle())
                    .keyboardShortcut(.init("p"), modifiers: [.control])
                Button { onEvent?(.move(.down)) } label: { Color.clear }
                    .buttonStyle(PlainButtonStyle())
                    .keyboardShortcut(.init("n"), modifiers: [.control])

                // Cmd+1 through Cmd+9 for quick selection
                ForEach(1...9, id: \.self) { n in
                    Button { onEvent?(.selectIndex(n - 1)) } label: { Color.clear }
                        .buttonStyle(PlainButtonStyle())
                        .keyboardShortcut(.init(Character("\(n)")), modifiers: [.command])
                }
            }
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))

                TextField("Search files by name…", text: $query)
                    .font(.system(size: 18, weight: .light))
                    .textFieldStyle(.plain)
                    .focused($isTextFieldFocused)
                    .onChange(of: isTextFieldFocused) { focused in
                        if !focused {
                            onEvent?(.exit)
                        }
                    }
                    .onExitCommand { onEvent?(.exit) }
                    .onSubmit { onEvent?(.submit) }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - Results List

fileprivate struct QuickOpenResultsList: View {
    let results: [FuzzyMatcher.Result]
    let rootDirectory: URL
    @Binding var selectedIndex: UInt?
    var showShortcutBadges: Bool = false
    let onSelect: (FuzzyMatcher.Result) -> Void

    var body: some View {
        if results.isEmpty {
            Text("No matches")
                .foregroundStyle(.secondary)
                .padding()
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.offset) { index, result in
                            QuickOpenRow(
                                result: result,
                                isSelected: isSelected(index),
                                shortcutIndex: showShortcutBadges && index < 9 ? index + 1 : nil
                            ) {
                                onSelect(result)
                            }
                            .id(index)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 300)
                .onChange(of: selectedIndex) { _ in
                    guard let selectedIndex,
                          selectedIndex < results.count else { return }
                    proxy.scrollTo(Int(selectedIndex))
                }
            }
        }
    }

    private func isSelected(_ index: Int) -> Bool {
        guard let selected = selectedIndex else { return false }
        if selected == index { return true }
        if selected >= results.count && index == results.count - 1 { return true }
        return false
    }
}

// MARK: - Result Row

fileprivate struct QuickOpenRow: View {
    let result: FuzzyMatcher.Result
    let isSelected: Bool
    var shortcutIndex: Int? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: fileIcon(for: result.path))
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    // Filename with matched character highlighting
                    highlightedFilename
                        .font(.system(size: 13))

                    // Relative directory path
                    let dir = directoryPart(of: result.path)
                    if !dir.isEmpty {
                        Text(dir)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if let n = shortcutIndex {
                    Text("\u{2318}\(n)")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.1)))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.2)
                    : Color.clear
            )
            .cornerRadius(5)
        }
        .buttonStyle(.plain)
    }

    private var highlightedFilename: Text {
        let filename = (result.path as NSString).lastPathComponent
        let filenameOffset = result.path.count - filename.count
        let matchedInFilename = Set(
            result.matchedIndices
                .filter { $0 >= filenameOffset }
                .map { $0 - filenameOffset }
        )

        var text = Text("")
        for (i, char) in filename.enumerated() {
            let part = Text(String(char))
            if matchedInFilename.contains(i) {
                text = text + part.foregroundColor(.accentColor).bold()
            } else {
                text = text + part.foregroundColor(.primary)
            }
        }
        return text
    }

    private func directoryPart(of path: String) -> String {
        let ns = path as NSString
        let dir = ns.deletingLastPathComponent
        return dir == "." ? "" : dir
    }

    private func fileIcon(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "zig": return "chevron.left.forwardslash.chevron.right"
        case "js", "ts", "jsx", "tsx": return "curlybraces"
        case "json", "yaml", "yml", "toml": return "gearshape"
        case "md", "markdown": return "doc.text"
        case "html", "css": return "globe"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "sh", "bash", "zsh": return "terminal"
        case "png", "jpg", "jpeg", "gif", "svg": return "photo"
        default: return "doc"
        }
    }
}
