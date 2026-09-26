import XCTest
@testable import WindowTidyy

final class LayoutItemTests: XCTestCase {
    private let bounds = CGRect(x: 100, y: 50, width: 600, height: 400)

    func testFullGridCoversBounds() {
        let item = LayoutItem(name: "全屏", gridX: 6, gridY: 6, startX: 0, startY: 0, endX: 6, endY: 6)
        XCTAssertEqual(item.rect(in: bounds), bounds)
    }

    func testLeftHalf() {
        let item = LayoutItem(name: "左半屏", gridX: 6, gridY: 6, startX: 0, startY: 0, endX: 3, endY: 6)
        let r = item.rect(in: bounds)
        XCTAssertEqual(r.minX, 100)
        XCTAssertEqual(r.width, 300, accuracy: 0.001)
        XCTAssertEqual(r.height, 400, accuracy: 0.001)
        XCTAssertEqual(r.minY, 50)
    }

    func testTopHalfIsFlipped() {
        // startY=0 是顶行：AppKit 坐标里应该贴着 bounds 顶部
        let top = LayoutItem(name: "上半", gridX: 6, gridY: 6, startX: 0, startY: 0, endX: 6, endY: 3)
        let rt = top.rect(in: bounds)
        XCTAssertEqual(rt.maxY, bounds.maxY, accuracy: 0.001)
        XCTAssertEqual(rt.height, 200, accuracy: 0.001)

        let bottom = LayoutItem(name: "下半", gridX: 6, gridY: 6, startX: 0, startY: 3, endX: 6, endY: 6)
        let rb = bottom.rect(in: bounds)
        XCTAssertEqual(rb.minY, bounds.minY, accuracy: 0.001)
        XCTAssertEqual(rb.height, 200, accuracy: 0.001)
    }

    func testCentre() {
        let item = LayoutItem(name: "居中", gridX: 6, gridY: 6, startX: 1, startY: 1, endX: 5, endY: 5)
        let r = item.rect(in: bounds)
        XCTAssertEqual(r.minX, 200, accuracy: 0.001)
        XCTAssertEqual(r.maxX, 600, accuracy: 0.001)
        XCTAssertEqual(r.width, 400, accuracy: 0.001)
        XCTAssertEqual(r.height, 400 * 4.0 / 6.0, accuracy: 0.001)
    }

    func testInvalidSelections() {
        XCTAssertFalse(LayoutItem(name: "", gridX: 0, gridY: 6, startX: 0, startY: 0, endX: 1, endY: 1).isValid)
        XCTAssertFalse(LayoutItem(name: "", gridX: 6, gridY: 6, startX: 0, startY: 0, endX: 7, endY: 6).isValid)
        XCTAssertFalse(LayoutItem(name: "", gridX: 6, gridY: 6, startX: 3, startY: 0, endX: 3, endY: 2).isValid)
    }

    func testClampShrinksSelection() {
        var item = LayoutItem(name: "宽", gridX: 6, gridY: 6, startX: 2, startY: 2, endX: 6, endY: 6)
        item.gridX = 3
        item.gridY = 4
        item.clampToBounds()
        XCTAssertTrue(item.isValid)
        XCTAssertEqual(item.endX, 3)
        XCTAssertEqual(item.endY, 4)
    }

    func testDefaults() {
        XCTAssertEqual(LayoutItem.defaults.count, 4)
        XCTAssertTrue(LayoutItem.defaults.allSatisfy(\.isValid))
    }

    func testSettingsCodableRoundTrip() throws {
        var settings = AppSettings()
        settings.triggerMode = .anyDrag
        settings.showTileTitles = false
        let item = LayoutItem(name: "自定义", gridX: 8, gridY: 4, startX: 1, startY: 1, endX: 7, endY: 3)
        settings.layouts.append(item)
        settings.quickSlotIDs = [item.id, nil, nil, nil]

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded, settings)
        XCTAssertEqual(decoded.quickSlotIDs.count, 4)
    }

    func testRepairSlotsDropsDeletedLayouts() {
        var settings = AppSettings()
        let removed = settings.layouts[1].id
        settings.layouts.remove(at: 1)
        settings.repairQuickSlots()
        XCTAssertFalse(settings.quickSlotIDs.contains(removed))
    }

    func testFullCoverageDetection() {
        XCTAssertTrue(LayoutItem(name: "全屏", gridX: 6, gridY: 6, startX: 0, startY: 0, endX: 6, endY: 6).isFullCoverage)
        XCTAssertFalse(LayoutItem(name: "左", gridX: 6, gridY: 6, startX: 0, startY: 0, endX: 3, endY: 6).isFullCoverage)
        // 8×8 的 100% 覆盖也算全屏
        XCTAssertTrue(LayoutItem(name: "全屏2", gridX: 8, gridY: 4, startX: 0, startY: 0, endX: 8, endY: 4).isFullCoverage)
    }

    func testTargetRectIgnoresDockInset() {
        // 模拟一块带 Dock 的屏：frame (0,0,1000,800)，visibleFrame (0,60,1000,700)（菜单栏 40 + Dock 60）
        let fakeScreen = FakeScreen(frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                                    visibleFrame: CGRect(x: 0, y: 60, width: 1000, height: 700))
        // 全屏：贴 frame 底（盖住 Dock），只让出菜单栏
        let full = LayoutItem(name: "全屏", gridX: 6, gridY: 6, startX: 0, startY: 0, endX: 6, endY: 6)
        let rf = full.targetRect(on: fakeScreen)
        XCTAssertEqual(rf.minY, 0)
        XCTAssertEqual(rf.height, 760, accuracy: 0.001)
        XCTAssertEqual(rf.width, 1000)

        // 左半屏：同样基于整屏去菜单栏（不被自动隐藏 Dock 的动态 visibleFrame 坑）
        let half = LayoutItem(name: "左半", gridX: 6, gridY: 6, startX: 0, startY: 0, endX: 3, endY: 6)
        let rh = half.targetRect(on: fakeScreen)
        XCTAssertEqual(rh.minY, 0)
        XCTAssertEqual(rh.height, 760, accuracy: 0.001)
        XCTAssertEqual(rh.width, 500)
    }

    func testTilingBoundsOnSecondaryScreenWithoutMenuBar() {
        // 副屏无菜单栏：topInset=0，tilingBounds = 整个 frame
        let fake = FakeScreen(frame: CGRect(x: -1000, y: 0, width: 1000, height: 800),
                              visibleFrame: CGRect(x: -1000, y: 0, width: 1000, height: 800))
        XCTAssertEqual(fake.tilingBounds, fake.frame)
    }
}

/// 测试用假屏（NSScreen 的 frame/visibleFrame 无法直接构造）
final class FakeScreen: NSScreen {
    private let f: NSRect
    private let vf: NSRect
    init(frame: NSRect, visibleFrame: NSRect) {
        self.f = frame
        self.vf = visibleFrame
        super.init()
    }
    override var frame: NSRect { f }
    override var visibleFrame: NSRect { vf }
}

// MARK: - 互补布局聚合

final class LayoutGroupingTests: XCTestCase {
    private func item(_ name: String, _ sx: Int, _ sy: Int, _ ex: Int, _ ey: Int,
                      gx: Int = 6, gy: Int = 6) -> LayoutItem {
        LayoutItem(name: name, gridX: gx, gridY: gy, startX: sx, startY: sy, endX: ex, endY: ey)
    }

    func testHalvesGroupTogether() {
        let left = item("左半屏", 0, 0, 3, 6)
        let right = item("右半屏", 3, 0, 6, 6)
        let centre = item("居中", 1, 1, 5, 5)
        let full = item("全屏", 0, 0, 6, 6)
        let tiles = LayoutGrouping.overlayTiles(from: [left, right, centre, full])
        XCTAssertEqual(tiles.count, 3)
        guard case let .group(members) = tiles[0] else {
            return XCTFail("首个瓦片应为聚合组，实际 \(tiles[0])")
        }
        XCTAssertEqual(members.map(\.name), ["左半屏", "右半屏"])
        XCTAssertEqual(tiles[1], .single(centre))
        XCTAssertEqual(tiles[2], .single(full)) // 全屏独占，不参与聚合
    }

    func testQuartersGroupIntoOne() {
        let tiles = LayoutGrouping.overlayTiles(from: [
            item("左上", 0, 0, 3, 3),
            item("右上", 3, 0, 6, 3),
            item("左下", 0, 3, 3, 6),
            item("右下", 3, 3, 6, 6),
        ])
        XCTAssertEqual(tiles.count, 1)
        guard case .group(let members) = tiles[0] else { return XCTFail("应为聚合组") }
        XCTAssertEqual(members.count, 4)
        XCTAssertEqual(tiles[0].title, "左上+右上+左下+右下")
    }

    func testIncompletePartitionDoesNotGroup() {
        // 只有左半屏 + 四个四分屏：四分屏成组，左半屏找不到互补 → 单瓦片
        let tiles = LayoutGrouping.overlayTiles(from: [
            item("左半屏", 0, 0, 3, 6),
            item("左上", 0, 0, 3, 3),
            item("右上", 3, 0, 6, 3),
            item("左下", 0, 3, 3, 6),
            item("右下", 3, 3, 6, 6),
        ])
        XCTAssertEqual(tiles.count, 2)
        XCTAssertEqual(tiles[0].title, "左半屏") // 左半屏找不到互补 → 单瓦片
        guard case .group(let m) = tiles[1] else { return XCTFail("四分屏应聚合") }
        XCTAssertEqual(m.map(\.name), ["左上", "右上", "左下", "右下"])
    }

    func testDifferentGridsDoNotMix() {
        // 6×6 的左半屏 + 4×4 的"右半屏"（各占自己网格一半）：网格不同不能聚合
        let tiles = LayoutGrouping.overlayTiles(from: [
            item("左半", 0, 0, 3, 6, gx: 6, gy: 6),
            item("右半", 2, 0, 4, 4, gx: 4, gy: 4),
        ])
        XCTAssertEqual(tiles.map(\.title), ["左半", "右半"])
    }

    func testThirdsGroupOfThree() {
        let tiles = LayoutGrouping.overlayTiles(from: [
            item("左1/3", 0, 0, 2, 6),
            item("中1/3", 2, 0, 4, 6),
            item("右1/3", 4, 0, 6, 6),
        ])
        XCTAssertEqual(tiles.count, 1)
        guard case .group(let m) = tiles[0] else { return XCTFail("三等分应聚合") }
        XCTAssertEqual(m.count, 3)
    }

    func testOverlappingLayoutsDoNotGroup() {
        // 两个区域重叠 → 无法精确覆盖
        let tiles = LayoutGrouping.overlayTiles(from: [
            item("左半", 0, 0, 3, 6),
            item("右半偏左", 2, 0, 6, 6), // 与左半重叠 1 列
        ])
        XCTAssertEqual(tiles.count, 2)
    }

    func testGroupEmitsAtFirstMemberPosition() {
        // 顺序：居中、右半屏、左半屏 → 组出现在"右半屏"的位置（组内首个成员=左半屏，位置跟随输入顺序中先出现者）
        let tiles = LayoutGrouping.overlayTiles(from: [
            item("居中", 1, 1, 5, 5),
            item("右半屏", 3, 0, 6, 6),
            item("左半屏", 0, 0, 3, 6),
        ])
        XCTAssertEqual(tiles.count, 2)
        XCTAssertEqual(tiles[0].title, "居中")
        guard case .group(let m) = tiles[1] else { return XCTFail("应为聚合组") }
        XCTAssertEqual(Set(m.map(\.name)), ["左半屏", "右半屏"])
    }

    func testTileTitleAndGrid() {
        XCTAssertEqual(OverlayTile.single(item("全屏", 0, 0, 6, 6)).title, "全屏")
        let group = OverlayTile.group([item("左上", 0, 0, 3, 3), item("右下", 3, 3, 6, 6)])
        // 左上+右下 不构成覆盖（缺右上/左下）— 但 OverlayTile 本身允许构造；title 仅拼接
        XCTAssertEqual(group.title, "左上+右下")
        XCTAssertEqual(group.grid.x, 6)
        XCTAssertEqual(group.grid.y, 6)
    }
}
