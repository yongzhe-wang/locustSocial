import SwiftUI
import CoreGraphics

struct MasonryLayout: Layout {
    var columns: Int = 2
    var spacing: CGFloat = 1
    /// extra room for card shadows so they don't visually touch
    var extraBottom: CGFloat = 1

    private func columnWidth(_ total: CGFloat) -> CGFloat {
        let raw = (total - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        let scale = UIScreen.main.scale
        return floor(raw * scale) / scale
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let totalW = proposal.width, totalW > 0 else { return .zero }
        let colW = columnWidth(totalW)
        var heights = Array(repeating: CGFloat(0), count: columns)

        for v in subviews {
            let s = v.sizeThatFits(.init(width: colW, height: nil))
            let i = heights.enumerated().min(by: { $0.element < $1.element })!.offset
            heights[i] += s.height + spacing + extraBottom
        }
        let h = (heights.max() ?? 0) - spacing
        return .init(width: totalW, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let colW = columnWidth(bounds.width)
        var y = Array(repeating: bounds.minY, count: columns)
        let scale = UIScreen.main.scale

        for v in subviews {
            let i = y.enumerated().min(by: { $0.element < $1.element })!.offset
            let s = v.sizeThatFits(.init(width: colW, height: nil))
            let x = bounds.minX + CGFloat(i) * (colW + spacing)
            let xAligned = floor(x * scale) / scale  // pixel-align

            v.place(
                at: CGPoint(x: xAligned, y: y[i]),
                anchor: .topLeading,                       // <- important
                proposal: .init(width: colW, height: s.height)
            )
            y[i] += s.height + spacing + extraBottom
        }
    }
}
