import Foundation

enum CommandPaletteLayout {
    static let rowHeight: CGFloat = 43
    static let sectionTextHeight: CGFloat = 13
    static let sectionTopPadding: CGFloat = 12
    static let sectionBottomPadding: CGFloat = 3
    static let contentPadding: CGFloat = 12
    static let maxHeight: CGFloat = 420

    static var sectionHeight: CGFloat {
        sectionTextHeight + sectionTopPadding + sectionBottomPadding
    }

    static func resultsHeight(groupSizes: [Int]) -> CGFloat {
        var height = contentPadding

        for size in groupSizes where size > 0 {
            let fullGroup = sectionHeight + CGFloat(size) * rowHeight
            if height + fullGroup <= maxHeight {
                height += fullGroup
                continue
            }

            let requiredRows = min(2, size)
            guard height + sectionHeight + CGFloat(requiredRows) * rowHeight <= maxHeight else {
                return height
            }

            height += sectionHeight
            var visibleRows = 0
            while visibleRows < size, height + rowHeight <= maxHeight {
                height += rowHeight
                visibleRows += 1
            }
            return height
        }

        return height
    }
}
