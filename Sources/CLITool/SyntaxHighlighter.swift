import AppKit

// MARK: - Theme

enum EditorTheme: String {
    case light, dark

    var toggled: EditorTheme { self == .light ? .dark : .light }
    var appearance: NSAppearance? { NSAppearance(named: self == .light ? .aqua : .darkAqua) }

    private func pick(_ light: UInt32, _ dark: UInt32) -> NSColor {
        let hex = self == .light ? light : dark
        return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                       green: CGFloat((hex >> 8) & 0xFF) / 255,
                       blue: CGFloat(hex & 0xFF) / 255,
                       alpha: 1)
    }

    var background: NSColor { pick(0xFFFFFF, 0x1E1F26) }
    var text: NSColor { pick(0x1F2328, 0xE4E6EB) }
    var comment: NSColor { pick(0x6E7781, 0x7F8694) }
    var string: NSColor { pick(0x1A7F37, 0x9ECE6A) }
    var keyword: NSColor { pick(0xCF222E, 0xFF6AC1) }
    var builtin: NSColor { pick(0x0550AE, 0x82AAFF) }
    var variable: NSColor { pick(0x953800, 0xE0AF68) }
    var number: NSColor { pick(0x8250DF, 0xBB9AF7) }
}

// MARK: - Highlighter

/// A small hand-written scanner for shell-style config files. It colors comments,
/// quoted strings, `$variables`, assignments, numbers and (for shell files) keywords
/// and common builtins. It is not a full parser — heredocs, for example, are treated
/// as ordinary code.
enum SyntaxHighlighter {
    enum Token { case comment, string, keyword, builtin, variable, number }

    private static let keywords: Set<String> = [
        "if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done",
        "case", "esac", "in", "select", "function", "return", "break", "continue", "time",
    ]
    private static let builtins: Set<String> = [
        "export", "alias", "unalias", "source", "local", "typeset", "declare", "readonly",
        "unset", "setopt", "unsetopt", "autoload", "eval", "exec", "exit", "cd", "echo",
        "print", "printf", "test", "bindkey", "zstyle", "compdef", "compinit", "zmodload",
        "fpath", "path", "prompt", "promptinit", "command", "builtin", "set", "shift",
        "trap", "umask", "read", "true", "false",
    ]

    static func font(size: CGFloat = 13) -> NSFont { .monospacedSystemFont(ofSize: size, weight: .regular) }

    /// Re-colors the whole text storage. Dotfiles are small, so this runs on every edit.
    static func apply(to storage: NSTextStorage, theme: EditorTheme, shell: Bool) {
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes([.font: font(), .foregroundColor: theme.text], range: full)
        for (range, token) in tokens(in: storage.string, shell: shell) {
            let color: NSColor
            switch token {
            case .comment: color = theme.comment
            case .string: color = theme.string
            case .keyword: color = theme.keyword
            case .builtin: color = theme.builtin
            case .variable: color = theme.variable
            case .number: color = theme.number
            }
            storage.addAttribute(.foregroundColor, value: color, range: range)
        }
        storage.endEditing()
    }

    // UTF-16 code units, so ranges line up with NSTextStorage.
    private static func u(_ scalar: Unicode.Scalar) -> UInt16 { UInt16(scalar.value) }
    private static let hash = u("#"), squote = u("'"), dquote = u("\"")
    private static let dollar = u("$"), backslash = u("\\"), newline = u("\n")
    private static let lbrace = u("{"), rbrace = u("}"), equals = u("=")
    private static let underscore = u("_"), dash = u("-"), plus = u("+")

    private static func isDigit(_ c: UInt16) -> Bool { c >= 48 && c <= 57 }
    private static func isAlpha(_ c: UInt16) -> Bool { (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == underscore }
    private static func isSpace(_ c: UInt16) -> Bool { c == 32 || c == 9 || c == newline || c == 13 }

    static func tokens(in text: String, shell: Bool) -> [(NSRange, Token)] {
        let c = Array(text.utf16)
        let n = c.count
        var out: [(NSRange, Token)] = []
        var i = 0

        func add(_ start: Int, _ end: Int, _ token: Token) {
            if end > start { out.append((NSRange(location: start, length: end - start), token)) }
        }

        /// Scans a `$…` expansion starting at `start` (which holds "$"); returns its end index.
        func variableEnd(_ start: Int) -> Int {
            var j = start + 1
            guard j < n else { return j }
            if c[j] == lbrace {
                while j < n, c[j] != rbrace, c[j] != newline { j += 1 }
                return min(j + 1, n)
            }
            if isAlpha(c[j]) {
                while j < n, isAlpha(c[j]) || isDigit(c[j]) { j += 1 }
                return j
            }
            // $1, $?, $#, $@, $*, $$, $!
            if isDigit(c[j]) || "?#@*$!-".utf16.contains(c[j]) { return j + 1 }
            return start + 1
        }

        while i < n {
            let ch = c[i]
            if ch == backslash {
                i += 2
            } else if ch == hash, i == 0 || isSpace(c[i - 1]) {
                let start = i
                while i < n, c[i] != newline { i += 1 }
                add(start, i, .comment)
            } else if ch == squote {
                let start = i
                i += 1
                while i < n, c[i] != squote { i += 1 }
                i = min(i + 1, n)
                add(start, i, .string)
            } else if ch == dquote {
                // Double-quoted string; $variables inside keep their own color.
                var segment = i
                i += 1
                while i < n, c[i] != dquote {
                    if c[i] == backslash {
                        i += 2
                    } else if c[i] == dollar {
                        let end = variableEnd(i)
                        if end > i + 1 {
                            add(segment, i, .string)
                            add(i, end, .variable)
                            segment = end
                        }
                        i = end
                    } else {
                        i += 1
                    }
                }
                i = min(i + 1, n)
                add(segment, i, .string)
            } else if ch == dollar {
                let end = variableEnd(i)
                if end > i + 1 { add(i, end, .variable) }
                i = end
            } else if isAlpha(ch) {
                let start = i
                while i < n, isAlpha(c[i]) || isDigit(c[i]) || c[i] == dash { i += 1 }
                let wordStartsToken = start == 0 || !(isAlpha(c[start - 1]) || isDigit(c[start - 1])
                    || "/.-~:".utf16.contains(c[start - 1]))
                let isAssignment = i < n && (c[i] == equals || (c[i] == plus && i + 1 < n && c[i + 1] == equals))
                if isAssignment {
                    add(start, i, .variable)
                } else if shell, wordStartsToken, !(i < n && "/.".utf16.contains(c[i])) {
                    let word = String(utf16CodeUnits: Array(c[start..<i]), count: i - start)
                    if keywords.contains(word) {
                        add(start, i, .keyword)
                    } else if builtins.contains(word) {
                        add(start, i, .builtin)
                    }
                }
            } else if isDigit(ch) {
                let start = i
                while i < n, isDigit(c[i]) { i += 1 }
                let boundedBefore = start == 0 || isSpace(c[start - 1]) || "=:;([,".utf16.contains(c[start - 1])
                let boundedAfter = i == n || isSpace(c[i]) || ";)],".utf16.contains(c[i])
                if boundedBefore, boundedAfter { add(start, i, .number) }
            } else {
                i += 1
            }
        }
        return out
    }
}
