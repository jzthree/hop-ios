import SwiftUI
import WebKit

// Tap a formula in the terminal, see it typeset — hop web shows the same
// thing on hover (utils/mathTooltip.ts). KaTeX ships inside the app
// (Resources/KaTeX, MIT), so it renders offline and needs nothing from the
// host. The source stays below, selectable, with a copy button.

struct MathShown: Identifiable {
    let id = UUID()
    let span: MathSpan
}

struct MathSheet: View {
    let span: MathSpan
    let light: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                KaTeXView(tex: span.tex, display: span.display, light: light)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .accessibilityIdentifier("math-render")
                Text(span.tex)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(UIColor.secondarySystemBackground)))
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Formula")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(copied ? "Copied" : "Copy LaTeX") {
                        UIPasteboard.general.string = span.tex
                        copied = true
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(light ? .light : .dark)
    }
}

/// KaTeX in a transparent web view. The page is built here and loaded with
/// the bundled KaTeX folder as its base, so the stylesheet finds its fonts.
struct KaTeXView: UIViewRepresentable {
    let tex: String
    let display: Bool
    let light: Bool

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        let key = "\(light)|\(display)|\(tex)"
        guard context.coordinator.loaded != key,
              let dir = Bundle.main.url(forResource: "KaTeX", withExtension: nil) else { return }
        context.coordinator.loaded = key
        web.loadHTMLString(Self.page(tex: tex, display: display, light: light), baseURL: dir.appendingPathComponent("index.html"))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var loaded = "" }

    static func page(tex: String, display: Bool, light: Bool) -> String {
        // Always display style: the sheet has the room, and inline \frac is
        // squeezed. The TeX goes in as a JSON string literal, never as markup.
        let data = (try? JSONSerialization.data(withJSONObject: [tex], options: [])) ?? Data("[\"\"]".utf8)
        let arg = String(data: data, encoding: .utf8) ?? "[\"\"]"
        let fg = light ? "#1d1d1f" : "#f2f2f7"
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <link rel="stylesheet" href="katex.min.css"><script src="katex.min.js"></script>
        <style>
          html,body{margin:0;background:transparent;color:\(fg);}
          body{display:flex;align-items:center;justify-content:center;min-height:100vh;padding:8px;box-sizing:border-box;
               font-size:22px;overflow-x:auto;-webkit-user-select:text;}
          #m{max-width:100%;overflow-x:auto;}
          .err{font:14px ui-monospace,monospace;color:#ff6b6b;white-space:pre-wrap;}
        </style></head><body><div id="m"></div><script>
          const tex = \(arg)[0], el = document.getElementById("m");
          try { katex.render(tex, el, { throwOnError: false, displayMode: true, strict: "ignore" }); }
          catch (e) { el.className = "err"; el.textContent = tex; }
        </script></body></html>
        """
    }
}
