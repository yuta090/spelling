import XCTest

/// フリーミアムのコンテンツゲート／ペイウォールの E2E（XCUITest）。
///
/// 起動引数 `-uitests`（揮発ストア・親ゲートのバイパス・初期タブ=単語登録・ログイン報酬OFF）と
/// `-uitest-open-parent`（起動時に親メニュー自動オープン）で決定的に回す。
/// 手書き/OCR の練習フローは E2E 対象外（ユニットテスト＋手動）。
final class PaywallE2ETests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uitests", "-uitest-open-parent"]
        app.launch()
        return app
    }

    /// 親メニュー（自動オープン）→「レベルで作成」シートを開く。
    private func openLevelSheet(_ app: XCUIApplication) {
        let byLevel = app.buttons["parent.byLevel"]
        XCTAssertTrue(byLevel.waitForExistence(timeout: 15), "「レベルで作成」が見つからない")
        byLevel.tap()
    }

    /// セグメント（学年ピッカー）のオプションを探す（buttons / segmentedControls 両対応）。
    private func gradeSegment(_ app: XCUIApplication, label: String) -> XCUIElement {
        let direct = app.buttons[label]
        if direct.waitForExistence(timeout: 10) { return direct }
        return app.segmentedControls.buttons[label]
    }

    /// 無料レベル（既定 pre-K）はロックされず、作成ボタンが出る。
    func testFreeLevelIsNotLocked() {
        let app = launchApp()
        openLevelSheet(app)

        XCTAssertTrue(app.buttons["level.create"].waitForExistence(timeout: 15),
                      "無料レベルでは作成ボタンが出るはず")
        XCTAssertFalse(app.buttons["level.unlock"].exists,
                       "無料レベルで解放ボタンが出てはいけない")
    }

    /// 有料レベル（US 1年生）はロックされ、ペイウォール経由で解放すると作成ボタンに変わる。
    /// 主ボタンは下部固定、ペイウォールの解放はツールバーにあり、どちらもスクロール不要で届く。
    func testLockedLevelShowsPaywallThenUnlocks() {
        let app = launchApp()
        openLevelSheet(app)

        // ロックされた「US 1年生」を選ぶ。
        let grade1 = gradeSegment(app, label: "US 1年生")
        XCTAssertTrue(grade1.waitForExistence(timeout: 15), "学年セグメント US 1年生 が見つからない")
        grade1.tap()

        // ロック中は解放ボタン（下部固定）。作成ボタンは出ない。
        let unlock = app.buttons["level.unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 15), "有料レベルはロックされ解放ボタンが出るはず")
        XCTAssertFalse(app.buttons["level.create"].exists, "有料レベルで作成ボタンが出てはいけない")
        unlock.tap()

        // ペイウォール → ツールバーの「解放」（デバッグ）で閉じる。
        let debugUnlock = app.buttons["paywall.debugUnlock"]
        XCTAssertTrue(debugUnlock.waitForExistence(timeout: 15), "ペイウォールの解放（デバッグ）が見つからない")
        debugUnlock.tap()

        // 解放後はロックが外れ、作成ボタンに変わる。
        XCTAssertTrue(app.buttons["level.create"].waitForExistence(timeout: 15),
                      "解放後は作成ボタンに変わるはず")
        XCTAssertFalse(app.buttons["level.unlock"].exists,
                       "解放後に解放ボタンが残ってはいけない")
    }
}
