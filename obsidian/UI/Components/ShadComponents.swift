import SwiftUI

// MARK: - Separator

struct ShadSeparator: View {
    var vertical = false
    var body: some View {
        Rectangle().fill(Shad.border)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

// MARK: - Badge

struct ShadBadge: View {
    enum Variant { case primary, secondary, outline, destructive }
    let text: String
    var variant: Variant = .secondary
    var mono = false

    init(_ text: String, variant: Variant = .secondary, mono: Bool = false) {
        self.text = text
        self.variant = variant
        self.mono = mono
    }

    var body: some View {
        Text(text)
            .font(mono ? Shad.mono(11.5, .medium) : Shad.font(12, .semibold))
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 2.5)
            .background(RoundedRectangle(cornerRadius: Shad.radiusSmall).fill(background))
            .overlay {
                if variant == .outline { RoundedRectangle(cornerRadius: Shad.radiusSmall).strokeBorder(Shad.border) }
            }
    }

    private var foreground: Color {
        switch variant {
        case .primary: Shad.primaryForeground
        case .secondary, .outline: Shad.foreground
        case .destructive: .white
        }
    }

    private var background: Color {
        switch variant {
        case .primary: Shad.primary
        case .secondary: Shad.secondary
        case .outline: .clear
        case .destructive: Shad.destructive
        }
    }
}

// MARK: - Search field

struct ShadSearchField: View {
    @Binding var text: String
    var placeholder = "Search"
    var focus: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: Shad.isMac ? 12 : 15, weight: .medium))
                .foregroundStyle(Shad.mutedForeground)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(Shad.isMac ? .system(size: 13) : .body)
                .focused(focus)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                #endif
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: Shad.isMac ? 12 : 15))
                        .foregroundStyle(Shad.mutedForeground)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: Shad.isMac ? 28 : 36)
        .background(RoundedRectangle(cornerRadius: Shad.isMac ? 7 : 10).fill(Shad.searchFill))
    }
}

// MARK: - Skeleton

struct Skeleton: View {
    var width: CGFloat?
    var height: CGFloat = 14
    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: Shad.radiusSmall)
            .fill(Shad.muted)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .opacity(pulse ? 0.5 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { pulse = true }
            }
    }
}

// MARK: - Flow layout (for tag chips)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}

// MARK: - Toasts (sonner-style)

@Observable
final class ToastCenter {
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let icon: String
    }

    private(set) var current: Toast?

    func show(_ message: String, icon: String = "info.circle") {
        let toast = Toast(message: message, icon: icon)
        withAnimation(.spring(duration: 0.3)) { current = toast }
        Task {
            try? await Task.sleep(for: .seconds(3))
            if current?.id == toast.id {
                withAnimation(.easeOut(duration: 0.2)) { current = nil }
            }
        }
    }
}

struct ToastOverlay: View {
    let center: ToastCenter

    var body: some View {
        VStack {
            Spacer()
            if let toast = center.current {
                HStack(spacing: 10) {
                    Image(systemName: toast.icon).font(Shad.font(14, .medium))
                    Text(toast.message).font(Shad.font(13.5, .medium)).fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Shad.foreground)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: 420, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Shad.radius).fill(Shad.card))
                .overlay(RoundedRectangle(cornerRadius: Shad.radius).strokeBorder(Shad.border))
                .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
                .padding(16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(toast.id)
            }
        }
        .allowsHitTesting(false)
    }
}
