import Foundation

/// Maps file extensions to Monaco Editor language identifiers.
/// Used to configure syntax highlighting when opening files.
func monacoLanguageId(for ext: String) -> String {
    switch ext.lowercased() {
    case "swift": return "swift"
    case "rs": return "rust"
    case "py", "pyw": return "python"
    case "js", "mjs", "cjs": return "javascript"
    case "jsx": return "javascript"
    case "ts", "mts", "cts": return "typescript"
    case "tsx": return "typescript"
    case "json": return "json"
    case "yaml", "yml": return "yaml"
    case "toml": return "toml"
    case "html", "htm": return "html"
    case "css": return "css"
    case "scss": return "scss"
    case "less": return "less"
    case "md", "markdown": return "markdown"
    case "sh", "bash", "zsh", "fish": return "shell"
    case "c", "h": return "c"
    case "cpp", "hpp", "cc", "cxx", "hxx": return "cpp"
    case "java": return "java"
    case "go": return "go"
    case "zig": return "zig"
    case "rb", "ruby": return "ruby"
    case "lua": return "lua"
    case "sql": return "sql"
    case "xml", "xsl", "xslt", "plist": return "xml"
    case "dockerfile": return "dockerfile"
    case "r": return "r"
    case "php": return "php"
    case "kt", "kts": return "kotlin"
    case "cs": return "csharp"
    case "m", "mm": return "objective-c"
    case "pl", "pm": return "perl"
    case "ex", "exs": return "elixir"
    default: return "plaintext"
    }
}
