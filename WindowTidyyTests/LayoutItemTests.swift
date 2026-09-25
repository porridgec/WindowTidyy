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
