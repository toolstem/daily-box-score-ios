import SwiftUI
import PDFKit

/// Full-screen PDF reader that opens on a specific page.
/// Also carries the Print / Share button: the iOS share sheet offers
/// Print (AirPrint), Messages, Mail and Save to Files for the PDF file
/// already on the device. Nothing is sent to us. This week's papers are
/// free to share; older archive papers need the Archive Pass.
struct PDFReaderScreen: View {
    let url: URL
    let page: Int

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: StoreManager
    @EnvironmentObject var feed: FeedService
    @State private var showingPass = false

    /// The paper's date, read from the cached filename
    /// (boxscores_YYYY-MM-DD.pdf).
    private var paperDate: String? {
        StoreManager.paperDate(fromFilename: url.lastPathComponent)
    }

    private var shareTitle: String {
        if let paperDate,
           let edition = feed.editions.first(where: { $0.date == paperDate }) {
            return "The Daily Box Score, \(edition.label)"
        }
        return "The Daily Box Score"
    }

    var body: some View {
        NavigationStack {
            PDFReaderView(url: url, page: page)
                .ignoresSafeArea(edges: .bottom)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        shareButton
                    }
                }
                .sheet(isPresented: $showingPass) {
                    ArchivePassSheet()
                }
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        switch store.shareAccess(
            paperDate: paperDate,
            newestPaperDate: feed.editions.first?.date
        ) {
        case .allowed:
            ShareLink(
                item: url,
                preview: SharePreview(shareTitle)
            ) {
                Label("Print or Share", systemImage: "square.and.arrow.up")
            }
        case .needsPass:
            Button {
                showingPass = true
            } label: {
                Label("Print or Share", systemImage: "square.and.arrow.up")
            }
        case .hidden:
            EmptyView()
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
