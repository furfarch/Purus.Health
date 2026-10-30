import Foundation
import UIKit
import WebKit

@MainActor
enum iOSPDFRenderer {
    private static let a4 = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)

    static func render(html: String) async throws -> Data {
        let webView = WKWebView(frame: a4)
        let navigationDelegate = NavigationDelegate()
        webView.navigationDelegate = navigationDelegate

        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            navigationDelegate.continuation = c
            webView.loadHTMLString(html, baseURL: nil)
            // A hung web process must not block callers (home-server sync, emergency copy) forever.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                navigationDelegate.finish(.failure(PDFRenderer.RenderError.timedOut))
            }
        }

        // Paginate to A4 instead of webView.pdf(), which yields one tall page.
        let renderer = A4PageRenderer()
        renderer.addPrintFormatter(webView.viewPrintFormatter(), startingAtPageAt: 0)
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, a4, nil)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        for page in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: page, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }

    private final class A4PageRenderer: UIPrintPageRenderer {
        override var paperRect: CGRect { iOSPDFRenderer.a4 }
        override var printableRect: CGRect { iOSPDFRenderer.a4.insetBy(dx: 36, dy: 36) }
    }

    private final class NavigationDelegate: NSObject, WKNavigationDelegate {
        var continuation: CheckedContinuation<Void, Error>?

        /// Resumes at most once (finish, fail, crash and timeout can all race).
        func finish(_ result: Result<Void, Error>) {
            continuation?.resume(with: result)
            continuation = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            finish(.success(()))
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finish(.failure(error))
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            finish(.failure(error))
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            finish(.failure(PDFRenderer.RenderError.webViewFailed))
        }
    }
}
