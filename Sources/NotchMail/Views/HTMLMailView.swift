import SwiftUI
import WebKit

/// An HTML mail with its own layout, on a white card. Locked down: no
/// JavaScript, no cookies or storage, nothing loads from the network unless
/// images are allowed, and links open in the browser, never in here.
struct HTMLMailView: NSViewRepresentable {
    let html: String
    let showsQuoted: Bool
    let loadsImages: Bool
    let blocker: WKContentRuleList
    /// Larger text in the enlarged notch.
    var zoom: CGFloat = 1

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.allowsMagnification = false
        view.allowsBackForwardNavigationGestures = false
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        if view.pageZoom != zoom { view.pageZoom = zoom }
        let document = Self.document(html, showsQuoted: showsQuoted, loadsImages: loadsImages)
        guard context.coordinator.loaded != document else { return }
        let rules = view.configuration.userContentController
        rules.removeAllContentRuleLists()
        if !loadsImages { rules.add(blocker) }
        context.coordinator.loaded = document
        context.coordinator.allowNextLoad = true
        view.loadHTMLString(document, baseURL: nil)
    }

    /// Our styles first: readable defaults, nothing wider than the card, quotes and remote pictures hidden.
    static func document(_ html: String, showsQuoted: Bool, loadsImages: Bool) -> String {
        var css = """
        html { background: #fff; }
        body { margin: 16px 18px; font: 14px/1.5 -apple-system, sans-serif; color: #1d1d1f;
               overflow-wrap: anywhere; -webkit-text-size-adjust: none; }
        img, video { max-width: 100% !important; height: auto !important; }
        table { max-width: 100% !important; }
        pre { white-space: pre-wrap; }
        html { scrollbar-width: none; }
        ::-webkit-scrollbar { display: none; width: 0; height: 0; }
        a { color: #0a66d8; }
        """
        if !showsQuoted {
            css += ".gmail_quote, .gmail_extra, blockquote[type=cite], #divRplyFwdMsg, #divRplyFwdMsg ~ *, #appendonsend ~ * { display: none !important; }\n"
        }
        if !loadsImages {
            css += "img[src^='http'], img[src^='//'] { display: none !important; }\n"
        }
        return "<meta charset=\"utf-8\"><style>\(css)</style>" + html
    }

    static func hasQuote(_ html: String) -> Bool {
        ["gmail_quote", "type=\"cite\"", "type=cite", "divRplyFwdMsg"].contains { html.contains($0) }
    }

    static func hasRemoteImages(_ html: String) -> Bool {
        let lowered = html.lowercased()
        return lowered.contains("<img") && (lowered.contains("src=\"http") || lowered.contains("src='http") || lowered.contains("src=\"//"))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loaded: String?
        var allowNextLoad = false

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            // Our own loadHTMLString only; meta refreshes, forms and frames go nowhere.
            if allowNextLoad, action.navigationType == .other, action.targetFrame?.isMainFrame == true {
                allowNextLoad = false
                return .allow
            }
            if action.targetFrame?.isMainFrame == false, action.navigationType == .other {
                return .cancel
            }
            if action.navigationType == .linkActivated, let url = action.request.url,
               ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                await MainActor.run { Browser.open(url) }
            }
            return .cancel
        }
    }
}

/// Compiles, once, the rule that blocks every network load from mail HTML.
@MainActor
enum MailContentBlocker {
    private static var compiled: WKContentRuleList?
    private static var failed = false

    static var ruleList: WKContentRuleList? { compiled }

    /// Nil if it can't be built; then mail is shown as text, never unprotected.
    static func prepare() async -> WKContentRuleList? {
        if let compiled { return compiled }
        if failed { return nil }
        let rules = #"[{"trigger":{"url-filter":"^[a-z+.-]+://"},"action":{"type":"block"}}]"#
        do {
            let list = try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "notchmail.block-remote", encodedContentRuleList: rules)
            compiled = list
            return list
        } catch {
            failed = true
            return nil
        }
    }
}
