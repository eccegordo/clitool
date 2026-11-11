import AppKit
import SwiftUI

/// A plain-text monospaced editor with syntax coloring. Wraps NSTextView so that smart
/// quotes, dashes and autocorrect — which would corrupt shell config — are always off.
struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    var theme: EditorTheme
    /// True for shell startup files, which also get keyword/builtin coloring.
    var isShell: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.font = SyntaxHighlighter.font()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.textContainerInset = NSSize(width: 8, height: 10)
        textView.string = text
        context.coordinator.restyle(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let themeChanged = coordinator.parent.theme != theme || coordinator.parent.isShell != isShell
        coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            coordinator.restyle(textView)
        } else if themeChanged {
            coordinator.restyle(textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor

        init(_ parent: CodeEditor) { self.parent = parent }

        /// Applies theme colors and re-highlights the whole document.
        func restyle(_ textView: NSTextView) {
            let theme = parent.theme
            textView.backgroundColor = theme.background
            textView.insertionPointColor = theme.text
            textView.typingAttributes = [.font: SyntaxHighlighter.font(), .foregroundColor: theme.text]
            if let storage = textView.textStorage {
                SyntaxHighlighter.apply(to: storage, theme: theme, shell: parent.isShell)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            // Don't recolor in the middle of composing a character (e.g. accents, IME).
            if !textView.hasMarkedText() { restyle(textView) }
            parent.text = textView.string
        }
    }
}
