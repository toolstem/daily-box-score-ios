import SwiftUI
import PDFKit

/// Full-screen PDF reader that opens on a specific page.
struct PDFReaderScreen: View {
    let url: URL
    let page: Int

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PDFReaderView(url: url, page: page)
                .ignoresSafeArea(edges: .bottom)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

struct PDFReaderView: UIViewRepresentable {
    let url: URL
    /// 1-based page number to open on.
    let page: Int

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = PDFDocument(url: url)
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        guard let document = view.document, page >= 1,
              let pdfPage = document.page(at: page - 1) else { return }
        // Only jump if we're not already there, so user scrolling isn't reset.
        if view.currentPage != pdfPage {
            view.go(to: pdfPage)
        }
    }
}
