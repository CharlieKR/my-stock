import XCTest

@MainActor final class MyStockUITests: XCTestCase {
  private func launch(extra: [String] = []) -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--demo", "--ui-testing"] + extra
    app.launch()
    XCTAssertTrue(app.buttons["tab.SOXL"].waitForExistence(timeout: 10))
    return app
  }
  private func capture(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
  private func expectBar(_ app: XCUIApplication, _ value: String) {
    let bar = app.tabBars["stock.tabbar"]
    let predicate = NSPredicate(format: "value == %@", value)
    expectation(for: predicate, evaluatedWith: bar)
    waitForExpectations(timeout: 5)
  }
  func testCompactScrollAndDirectTabSelection() {
    let app = launch()
    capture(app, "01-SOXL-expanded")
    app.swipeUp()
    expectBar(app, "compact")
    capture(app, "02-SOXL-compact")
    let otherTab = app.coordinate(withNormalizedOffset: .zero).withOffset(
      CGVector(dx: app.frame.width / 2, dy: app.frame.height - 49))
    otherTab.tap()
    expectBar(app, "expanded")
    XCTAssertTrue(app.staticTexts["하이닉스 · ACE · KODEX"].waitForExistence(timeout: 5))
    capture(app, "03-HYXL")
    app.swipeUp()
    expectBar(app, "compact")
    app.swipeDown()
    expectBar(app, "expanded")
  }
  func testCalendarReportNavigationAndSettings() {
    let app = launch()
    app.buttons["리포트 날짜 선택"].tap()
    XCTAssertTrue(app.navigationBars["리포트 날짜"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.datePickers.firstMatch.exists)
    capture(app,"Native-calendar")
    app.buttons["daily.confirmDate"].tap()
    app.buttons["tab.My"].tap()
    XCTAssertTrue(app.descendants(matching:.any)["my.totalProfit"].waitForExistence(timeout:5))
    XCTAssertTrue(app.descendants(matching:.any)["my.totalReturn"].exists)
    XCTAssertTrue(app.descendants(matching:.any)["my.SOXL.performance"].exists)
    XCTAssertTrue(app.descendants(matching:.any)["my.HYXL.performance"].exists)
    capture(app, "04-My")
    app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "종합리포트")).firstMatch.tap()
    XCTAssertTrue(app.navigationBars["종합리포트"].waitForExistence(timeout: 5))
    capture(app, "05-Report")
    app.segmentedControls.buttons["SOXL"].tap()
    XCTAssertTrue(app.staticTexts["SOXL의 투자 흐름"].exists)
    let periods=app.segmentedControls["report.period"]
    XCTAssertTrue(periods.exists)
    periods.buttons["1주"].tap()
    XCTAssertTrue(app.staticTexts["report.dateRange"].label.contains("2026.09.14"))
    XCTAssertTrue(app.staticTexts["report.dateRange"].label.contains("5일 기록"))
    periods.buttons["1개월"].tap()
    XCTAssertTrue(app.staticTexts["report.dateRange"].label.contains("2026.08.19"))
    periods.buttons["전체"].tap()
    app.buttons["성과 계산 기준"].tap()
    XCTAssertTrue(app.navigationBars["계산 기준"].waitForExistence(timeout: 5))
    app.buttons["완료"].tap()
    XCTAssertTrue(app.navigationBars["계산 기준"].waitForNonExistence(timeout: 5))
    app.buttons["report.back"].tap()
    XCTAssertTrue(app.staticTexts["나의 투자 기록"].waitForExistence(timeout:5))
    app.swipeUp()
    XCTAssertTrue(app.buttons["앱 설정"].waitForExistence(timeout: 5))
    app.buttons["앱 설정"].tap()
    XCTAssertTrue(app.switches["금액 숨기기"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["데이터 연결"].exists)
    app.switches["금액 숨기기"].coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    XCTAssertEqual(app.switches["금액 숨기기"].value as? String, "1")
    let leftEdge=app.coordinate(withNormalizedOffset:CGVector(dx:0.01,dy:0.5))
    leftEdge.press(forDuration:0.05,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.9,dy:0.5)))
    XCTAssertTrue(app.navigationBars["앱 설정"].waitForNonExistence(timeout:5))
    app.swipeDown()
    capture(app, "09-Hidden-amounts")
    XCTAssertTrue(app.staticTexts["••••••"].firstMatch.waitForExistence(timeout: 5))
  }
  func testLargeTextKeepsTabsExpanded() {
    let app = launch(extra: [
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
    ])
    app.swipeUp()
    expectBar(app, "expanded")
    capture(app, "06-Accessibility")
  }
  func testChartInspectionRestoresLatestAssetsWithoutMovingChart() {
    let app=launch()
    app.buttons["tab.My"].tap()
    app.buttons.matching(NSPredicate(format:"label CONTAINS %@","종합리포트")).firstMatch.tap()
    XCTAssertTrue(app.navigationBars["종합리포트"].waitForExistence(timeout:5))
    app.segmentedControls.buttons["SOXL"].tap()
    let chart=app.descendants(matching:.any).matching(identifier:"asset.chart").firstMatch
    XCTAssertTrue(chart.waitForExistence(timeout:5))
    let originalFrame=chart.frame
    let originalAmount=app.staticTexts["report.assetAmount"].label
    let originalDate=app.staticTexts["report.assetDate"].label
    capture(app,"Chart-before-inspection")
    // The demo series is falling around the first quarter, which also exercises
    // the negative inspection state before verifying that release restores it.
    chart.coordinate(withNormalizedOffset:CGVector(dx:0.25,dy:0.5)).press(forDuration:12)
    XCTAssertEqual(app.staticTexts["report.assetTitle"].label,"총 자산")
    XCTAssertEqual(app.staticTexts["report.assetAmount"].label,originalAmount)
    XCTAssertEqual(app.staticTexts["report.assetDate"].label,originalDate)
    XCTAssertEqual(chart.frame.minY,originalFrame.minY,accuracy:1)
    XCTAssertEqual(chart.frame.height,originalFrame.height,accuracy:1)
    let start=chart.coordinate(withNormalizedOffset:CGVector(dx:0.25,dy:0.5))
    start.press(forDuration:0.4,thenDragTo:chart.coordinate(withNormalizedOffset:CGVector(dx:0.7,dy:0.5)),withVelocity:.slow,thenHoldForDuration:8)
    XCTAssertEqual(app.staticTexts["report.assetTitle"].label,"총 자산")
    XCTAssertEqual(app.staticTexts["report.assetAmount"].label,originalAmount)
    XCTAssertEqual(chart.frame.minY,originalFrame.minY,accuracy:1)
    capture(app,"Chart-after-inspection")
  }
  func testDarkAppearance() {
    let app = launch(extra: ["--dark"])
    capture(app, "07-Dark")
    app.buttons["tab.HYXL"].tap()
    app.swipeUp()
    expectBar(app, "compact")
    capture(app, "08-Dark-compact")
  }
}
