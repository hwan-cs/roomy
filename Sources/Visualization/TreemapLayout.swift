import CoreGraphics

struct TreemapSlot<Item> {
    let item: Item
    let rect: CGRect
}

enum TreemapLayout {
    static func layout<Item>(
        items: [Item],
        size: (Item) -> Int64,
        in rect: CGRect
    ) -> [TreemapSlot<Item>] {
        let positive = items.filter { size($0) > 0 }
        guard !positive.isEmpty, rect.width > 0, rect.height > 0 else {
            return []
        }

        let total = positive.reduce(Int64(0)) { $0 + size($1) }
        guard total > 0 else {
            return []
        }

        let rectArea = Double(rect.width) * Double(rect.height)
        let scale = rectArea / Double(total)
        var normalized = positive.map { Double(size($0)) * scale }
        applyMinimumAreaFloor(&normalized, totalArea: rectArea)

        var result: [TreemapSlot<Item>] = []
        squarify(
            items: positive,
            values: normalized,
            in: rect,
            result: &result
        )
        return result
    }

    private static func applyMinimumAreaFloor(_ values: inout [Double], totalArea: Double) {
        guard values.count > 1, totalArea > 0 else {
            return
        }
        let minArea = totalArea * 0.045
        let flooredIndices = values.indices.filter { values[$0] > 0 && values[$0] < minArea }
        guard !flooredIndices.isEmpty, flooredIndices.count < values.count else {
            return
        }

        let deficit = flooredIndices.reduce(0.0) { $0 + (minArea - values[$1]) }
        let donorIndices = values.indices.filter { !flooredIndices.contains($0) }
        let donorTotal = donorIndices.reduce(0.0) { $0 + values[$1] }
        guard donorTotal > deficit * 3 else {
            return
        }

        for i in flooredIndices {
            values[i] = minArea
        }
        for i in donorIndices {
            values[i] -= deficit * (values[i] / donorTotal)
        }
    }

    private static func squarify<Item>(
        items: [Item],
        values: [Double],
        in rect: CGRect,
        result: inout [TreemapSlot<Item>]
    ) {
        guard !values.isEmpty, rect.width > 0, rect.height > 0 else {
            return
        }

        let shortSide = min(rect.width, rect.height)
        var rowCount = 1
        var bestWorst = worstAspectRatio(values: Array(values.prefix(1)), shortSide: Double(shortSide))

        while rowCount < values.count {
            let candidate = worstAspectRatio(values: Array(values.prefix(rowCount + 1)), shortSide: Double(shortSide))
            if candidate <= bestWorst {
                bestWorst = candidate
                rowCount += 1
            } else {
                break
            }
        }

        let rowItems = Array(items.prefix(rowCount))
        let rowValues = Array(values.prefix(rowCount))
        let rowTotal = rowValues.reduce(0, +)

        let placeVertically = rect.width >= rect.height
        let rowLength = rowTotal / Double(shortSide)

        var offset: Double = 0
        for (item, value) in zip(rowItems, rowValues) {
            let extent = value / rowLength
            let slotRect: CGRect
            if placeVertically {
                slotRect = CGRect(x: rect.minX, y: rect.minY + offset, width: rowLength, height: extent)
            } else {
                slotRect = CGRect(x: rect.minX + offset, y: rect.minY, width: extent, height: rowLength)
            }
            result.append(TreemapSlot(item: item, rect: slotRect))
            offset += extent
        }

        let remainingRect: CGRect
        if placeVertically {
            remainingRect = CGRect(
                x: rect.minX + rowLength,
                y: rect.minY,
                width: rect.width - rowLength,
                height: rect.height
            )
        } else {
            remainingRect = CGRect(
                x: rect.minX,
                y: rect.minY + rowLength,
                width: rect.width,
                height: rect.height - rowLength
            )
        }

        squarify(
            items: Array(items.dropFirst(rowCount)),
            values: Array(values.dropFirst(rowCount)),
            in: remainingRect,
            result: &result
        )
    }

    private static func worstAspectRatio(values: [Double], shortSide: Double) -> Double {
        guard !values.isEmpty, shortSide > 0 else {
            return .infinity
        }
        let sum = values.reduce(0, +)
        guard sum > 0 else {
            return .infinity
        }
        let maxValue = values.max() ?? 0
        let minValue = values.min() ?? 0
        let sideSquared = shortSide * shortSide
        let sumSquared = sum * sum
        let ratioMax = (sideSquared * maxValue) / sumSquared
        let ratioMin = sumSquared / (sideSquared * minValue)
        return max(ratioMax, ratioMin)
    }
}
