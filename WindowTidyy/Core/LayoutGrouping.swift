import Foundation

/// overlay 瓦片：单个布局，或聚合显示的互补布局组（原版 AutoGroupLayouts）
enum OverlayTile: Identifiable, Equatable {
    case single(LayoutItem)
    case group([LayoutItem])

    var layouts: [LayoutItem] {
        switch self {
        case .single(let layout): return [layout]
        case .group(let layouts): return layouts
        }
    }

    /// 组内首个布局的网格（同组网格必然一致）
    var grid: (x: Int, y: Int) {
        let first = layouts[0]
        return (first.gridX, first.gridY)
    }

    var id: String {
        layouts.map(\.id.uuidString).joined(separator: "+")
    }

    /// 瓦片标题：单个用原名；聚合组用 "+" 连接
    var title: String {
        switch self {
        case .single(let layout): return layout.name
        case .group(let layouts): return layouts.map(\.name).joined(separator: "+")
        }
    }
}

/// 互补布局自动聚合：网格相同的布局中，恰好无缝平铺整个网格（不重不漏）的一组
/// 合并为一个瓦片（原版 Window Tidy 的 AutoGroupLayouts 行为）。
enum LayoutGrouping {
    struct Cell: Hashable {
        let x: Int
        let y: Int
    }

    static func cells(of layout: LayoutItem) -> Set<Cell> {
        guard layout.isValid else { return [] }
        var result = Set<Cell>()
        for x in layout.startX..<layout.endX {
            for y in layout.startY..<layout.endY {
                result.insert(Cell(x: x, y: y))
            }
        }
        return result
    }

    /// 生成 overlay 瓦片序列：聚合组在首个成员的原始位置输出，其余布局保持单瓦片。
    /// 顺序与输入布局顺序一致（右半屏即使排在后面，也聚合到左半屏的位置）。
    static func overlayTiles(from layouts: [LayoutItem]) -> [OverlayTile] {
        guard !layouts.isEmpty else { return [] }

        // 1) 按网格尺寸分桶（不同网格不可能互补）
        var buckets: [String: [Int]] = [:]
        for (index, layout) in layouts.enumerated() {
            buckets["\(layout.gridX),\(layout.gridY)", default: []].append(index)
        }

        // 2) 桶内做精确覆盖找互补组
        var groupedIndices = Set<Int>()
        var groupsByFirstMember: [Int: [Int]] = [:]

        for (_, indices) in buckets {
            guard let firstLayout = indices.map({ layouts[$0] }).first else { continue }
            let fullGrid = Set((0..<firstLayout.gridX).flatMap { x in
                (0..<firstLayout.gridY).map { y in Cell(x: x, y: y) }
            })
            // 全屏布局只能独占一个瓦片，不参与聚合
            var pool = indices.filter { !layouts[$0].isFullCoverage }

            while !pool.isEmpty {
                guard let cover = findBestCover(fullGrid, pool.map { layouts[$0] }) else { break }
                let coverIDs = Set(cover.map(\.id))
                let members = pool.filter { coverIDs.contains(layouts[$0].id) }
                // 非全屏的单个布局不可能覆盖整格，找到的组必然 ≥ 2 个成员
                if members.count >= 2 {
                    groupedIndices.formUnion(members)
                    groupsByFirstMember[members.min() ?? members[0]] = members
                }
                pool.removeAll { coverIDs.contains(layouts[$0].id) }
            }
        }

        // 3) 按原始顺序输出：组在首个成员位置聚合出现
        var tiles: [OverlayTile] = []
        for (index, layout) in layouts.enumerated() {
            if groupedIndices.contains(index) {
                if let members = groupsByFirstMember[index] {
                    tiles.append(.group(members.map { layouts[$0] }))
                }
                // 组内其余成员：已在组瓦片里，跳过
            } else {
                tiles.append(.single(layout))
            }
        }
        return tiles
    }

    /// 精确覆盖（回溯全搜索，返回成员数最多的一组；同一覆盖规模下取先出现的组合）。
    /// 优先大组：同时存在「左右半屏」与「四分屏」时，4 个四分屏先聚成一组，
    /// 避免出现 {左半屏+右上+右下} 这类数学合法但语义杂糅的混合组。
    private static func findBestCover(_ remaining: Set<Cell>, _ candidates: [LayoutItem]) -> [LayoutItem]? {
        if remaining.isEmpty { return [] }
        guard let pivot = remaining.min(by: { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }) else { return nil }
        var best: [LayoutItem]?
        for candidate in candidates {
            let cells = self.cells(of: candidate)
            guard cells.contains(pivot), cells.isSubset(of: remaining) else { continue }
            let rest = remaining.subtracting(cells)
            let others = candidates.filter { $0.id != candidate.id }
            if let tail = findBestCover(rest, others) {
                let cover = [candidate] + tail
                if best == nil || cover.count > best!.count {
                    best = cover
                }
            }
        }
        return best
    }
}
