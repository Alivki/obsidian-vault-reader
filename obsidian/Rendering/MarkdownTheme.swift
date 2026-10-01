import MarkdownUI
import SwiftUI

extension MarkdownUI.Theme {
    static func vault(bodySize: CGFloat) -> MarkdownUI.Theme {
        let base = bodySize
        return MarkdownUI.Theme()
            .text {
                ForegroundColor(Shad.reading)
                FontSize(base)
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.86))
                BackgroundColor(Shad.muted)
            }
            .strong { FontWeight(.semibold) }
            .link { ForegroundColor(Shad.link) }
            .heading1 { configuration in
                configuration.label
                    .markdownMargin(top: 28, bottom: 12)
                    .markdownTextStyle {
                        FontWeight(.heavy)
                        FontSize(.em(2.1))
                        ForegroundColor(Shad.foreground)
                    }
            }
            .heading2 { configuration in
                configuration.label
                    .markdownMargin(top: 24, bottom: 8)
                    .markdownTextStyle {
                        FontWeight(.bold)
                        FontSize(.em(1.6))
                        ForegroundColor(Shad.foreground)
                    }
            }
            .heading3 { configuration in
                configuration.label
                    .markdownMargin(top: 22, bottom: 8)
                    .markdownTextStyle {
                        FontWeight(.bold)
                        FontSize(.em(1.3))
                        ForegroundColor(Shad.foreground)
                    }
            }
            .heading4 { configuration in
                configuration.label
                    .markdownMargin(top: 20, bottom: 6)
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(1.12))
                        ForegroundColor(Shad.foreground)
                    }
            }
            .heading5 { configuration in
                configuration.label
                    .markdownMargin(top: 18, bottom: 6)
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        ForegroundColor(Shad.foreground)
                    }
            }
            .heading6 { configuration in
                configuration.label
                    .markdownMargin(top: 18, bottom: 6)
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        ForegroundColor(Shad.mutedForeground)
                    }
            }
            .paragraph { configuration in
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.32))
                    .markdownMargin(top: 0, bottom: 14)
            }
            .listItem { configuration in
                configuration.label.markdownMargin(top: .em(0.2))
            }
            .taskListMarker { configuration in
                Image(systemName: configuration.isCompleted ? "checkmark.square.fill" : "square")
                    .foregroundStyle(configuration.isCompleted ? Shad.link : Shad.mutedForeground)
                    .imageScale(.small)
                    .relativeFrame(minWidth: .em(1.5), alignment: .trailing)
            }
            .blockquote { configuration in
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Shad.border)
                        .frame(width: 3)
                    configuration.label
                        .markdownTextStyle { ForegroundColor(Shad.reading) }
                        .padding(.leading, 16)
                        .padding(.vertical, 2)
                }
                .fixedSize(horizontal: false, vertical: true)
                .markdownMargin(top: 0, bottom: 14)
            }
            .codeBlock { configuration in
                CodeBlockView(configuration: configuration)
                    .markdownMargin(top: 0, bottom: 16)
            }
            .table { configuration in
                ScrollView(.horizontal, showsIndicators: false) {
                    configuration.label
                        .fixedSize(horizontal: false, vertical: true)
                        .markdownTableBorderStyle(.init(color: Shad.border))
                        .markdownTableBackgroundStyle(.alternatingRows(Shad.background, Shad.muted.opacity(0.45)))
                }
                .markdownMargin(top: 0, bottom: 16)
            }
            .tableCell { configuration in
                configuration.label
                    .markdownTextStyle {
                        if configuration.row == 0 { FontWeight(.semibold) }
                        FontSize(.em(0.94))
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 12)
                    .relativeLineSpacing(.em(0.2))
            }
            .thematicBreak {
                Rectangle()
                    .fill(Shad.border)
                    .frame(height: 1)
                    .markdownMargin(top: 20, bottom: 20)
            }
    }
}

struct CodeBlockView: View {
    let configuration: CodeBlockConfiguration
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(configuration.language ?? "")
                    .font(Shad.mono(12))
                    .foregroundStyle(Shad.mutedForeground)
                Spacer()
                Button {
                    Clipboard.copy(configuration.content)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundStyle(Shad.mutedForeground)
                }
                .buttonStyle(.shad(.ghost, size: .iconSm))
                .accessibilityLabel("Copy code")
            }
            .padding(.leading, 14)
            .padding(.trailing, 4)
            .padding(.top, 2)
            ScrollView(.horizontal, showsIndicators: false) {
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.3))
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(.em(0.84))
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
        .background(RoundedRectangle(cornerRadius: Shad.radius).fill(Shad.muted.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: Shad.radius).strokeBorder(Shad.border))
    }
}
