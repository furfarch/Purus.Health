import Foundation

enum PDFRenderer {
    enum RenderError: Error {
        case webViewFailed
        case timedOut
    }

    static func render(html: String) async throws -> Data {
        try await iOSPDFRenderer.render(html: html)
    }
}
