import SwiftUI

struct HTMLTableView: View {
    let table: HTMLTable
    let fontSize: CGFloat

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HTMLTableLayout(table: table) {
                ForEach(table.cells.indices, id: \.self) { index in
                    let cell = table.cells[index]
                    Text(cell.content)
                        .font(.system(size: fontSize * 0.94))
                        .foregroundStyle(Shad.reading)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(cell.isHeader ? Shad.muted.opacity(0.6) : .clear)
                        .overlay(Rectangle().strokeBorder(Shad.border, lineWidth: 0.5))
                }
            }
            .overlay(Rectangle().strokeBorder(Shad.border, lineWidth: 0.5))
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .textSelection(.enabled)
    }
}

/// Grid layout supporting row and column spans:
/// column widths come from single-column cells (capped), then row heights are
/// measured at those widths; spanning cells grow the last row/column they cover.
struct HTMLTableLayout: Layout {
    let table: HTMLTable
    var minColumnWidth: CGFloat = 64
    var maxColumnWidth: CGFloat = 260

    private struct Solution {
        var columns: [CGFloat]
        var rows: [CGFloat]
    }

    private func solve(_ subviews: Subviews) -> Solution {
        let cells = Array(table.cells.prefix(subviews.count))
        var columns = Array(repeating: minColumnWidth, count: table.columnCount)
        let ideal = cells.indices.map { subviews[$0].sizeThatFits(.unspecified).width }

        for (i, cell) in cells.enumerated() where cell.columnSpan == 1 {
            columns[cell.column] = max(columns[cell.column], min(ideal[i], maxColumnWidth))
        }
        for (i, cell) in cells.enumerated() where cell.columnSpan > 1 {
            let span = cell.column..<min(cell.column + cell.columnSpan, columns.count)
            let have = span.reduce(0) { $0 + columns[$1] }
            let need = min(ideal[i], maxColumnWidth)
            if need > have {
                let extra = (need - have) / CGFloat(span.count)
                for c in span { columns[c] += extra }
            }
        }

        var rows = Array(repeating: CGFloat(0), count: table.rowCount)
        for i in cells.indices.sorted(by: { cells[$0].rowSpan < cells[$1].rowSpan }) {
            let cell = cells[i]
            let width = (cell.column..<min(cell.column + cell.columnSpan, columns.count)).reduce(0) { $0 + columns[$1] }
            let height = subviews[i].sizeThatFits(ProposedViewSize(width: width, height: nil)).height
            let span = cell.row..<min(cell.row + cell.rowSpan, rows.count)
            let have = span.reduce(0) { $0 + rows[$1] }
            if height > have { rows[span.upperBound - 1] += height - have }
        }
        return Solution(columns: columns, rows: rows)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let solution = solve(subviews)
        return CGSize(width: solution.columns.reduce(0, +), height: solution.rows.reduce(0, +))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let solution = solve(subviews)
        let xs = solution.columns.reduce(into: [CGFloat(0)]) { $0.append($0.last! + $1) }
        let ys = solution.rows.reduce(into: [CGFloat(0)]) { $0.append($0.last! + $1) }
        for (i, cell) in table.cells.prefix(subviews.count).enumerated() {
            let lastColumn = min(cell.column + cell.columnSpan, solution.columns.count)
            let lastRow = min(cell.row + cell.rowSpan, solution.rows.count)
            subviews[i].place(
                at: CGPoint(x: bounds.minX + xs[cell.column], y: bounds.minY + ys[cell.row]),
                proposal: ProposedViewSize(width: xs[lastColumn] - xs[cell.column], height: ys[lastRow] - ys[cell.row])
            )
        }
    }
}
