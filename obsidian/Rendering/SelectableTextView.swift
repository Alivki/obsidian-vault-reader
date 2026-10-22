import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Read-only native text view with free range selection across the whole note.
/// SwiftUI's `.textSelection` only copies whole blocks on iOS and can't span paragraphs on macOS.
struct SelectableTextView: View {
    let text: String
    let fontSize: CGFloat

    var body: some View {
        Representable(text: text, fontSize: fontSize)
    }
}

private func attributed(_ text: String, fontSize: CGFloat) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = fontSize * 0.32
    #if os(iOS)
    let font = UIFont.systemFont(ofSize: fontSize)
    let color = UIColor(Shad.reading)
    #else
    let font = NSFont.systemFont(ofSize: fontSize)
    let color = NSColor(Shad.reading)
    #endif
    return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
}

#if os(iOS)
private struct Representable: UIViewRepresentable {
    let text: String
    let fontSize: CGFloat

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 24, left: 22, bottom: 96, right: 22)
        view.textContainer.lineFragmentPadding = 0
        view.dataDetectorTypes = [.link]
        view.alwaysBounceVertical = true
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text || view.font?.pointSize != fontSize {
            view.attributedText = attributed(text, fontSize: fontSize)
        }
    }
}
#else
private struct Representable: NSViewRepresentable {
    let text: String
    let fontSize: CGFloat

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        let view = scroll.documentView as! NSTextView
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = NSSize(width: 40, height: 24)
        view.textContainer?.lineFragmentPadding = 0
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        if view.string != text || view.font?.pointSize != fontSize {
            view.textStorage?.setAttributedString(attributed(text, fontSize: fontSize))
        }
    }
}
#endif
