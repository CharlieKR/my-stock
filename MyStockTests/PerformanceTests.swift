import Foundation
import Testing

@testable import MyStockCore

private func report(_ investment: Investment, _ date: String, assets: Double, pnl: Double?)
  -> DailyReport
{
  DailyReport(
    id: "\(investment)-\(date)", investment: investment, date: date, currency: investment.currency,
    status: "settled", totalAssets: assets, stockValue: assets * 0.5, cash: assets * 0.5,
    cumulativePnl: pnl, cumulativeReturn: nil, dailyPnl: nil, dailyPnlLabel: "오늘 손익", details: [],
    rawText: "", slackURL: "", threadTS: "", updatedAt: "")
}
private func envelope(_ reports: [DailyReport], rates: [FXRate] = []) -> ReportEnvelope {
  ReportEnvelope(
    schemaVersion: 1, generatedAt: nil, reports: reports, fxRates: rates, fxSource: nil,
    fxMessage: nil, sources: [])
}
private func monthSeries(assets: (Int) -> Double, pnl: (Int) -> Double?) -> [DailyReport] {
  (0...30).map { day in
    report(
      .soxl, day == 0 ? "2026-08-31" : String(format: "2026-09-%02d", day), assets: assets(day),
      pnl: pnl(day))
  }
}

@Test func profitWithoutDeposits() {
  let data = envelope(monthSeries(assets: { 1000 + Double($0) * 10 }, pnl: { Double($0) * 10 }))
  let month = Performance.monthly(data, scope: .soxl).first!
  #expect(month.profit == 300)
  #expect(month.returnPercent == 30)
  #expect(!month.estimated)
}

@Test func fullHistoryKeepsEveryMonthAcrossYears() {
  let dates = ["2024-01-31", "2024-12-31", "2025-01-31", "2025-06-30", "2026-03-31", "2026-09-18"]
  let data = envelope(dates.map { report(.soxl, $0, assets: 1000, pnl: 0) })
  let months = Performance.monthly(data, scope: .soxl)
  #expect(months.map(\.month) == dates.map { String($0.prefix(7)) }.reversed())
  #expect(Performance.points(data, scope: .soxl).first?.date == "2024-01-31")
}
@Test func depositIsExcludedAndDietzWeighted() {
  let data = envelope(
    monthSeries(assets: { 1000 + ($0 >= 15 ? 500 : 0) + Double($0) * 5 }, pnl: { Double($0) * 5 }))
  let month = Performance.monthly(data, scope: .soxl).first!
  #expect(month.profit == 150)
  #expect(month.cashflow == 500)
  #expect(month.returnPercent == 12)
  #expect(month.estimated)
}
@Test func withdrawalIsNotLoss() {
  let data = envelope(monthSeries(assets: { 1000 - ($0 >= 15 ? 400 : 0) }, pnl: { _ in 0 }))
  let month = Performance.monthly(data, scope: .soxl).first!
  #expect(month.profit == 0)
  #expect(month.cashflow == -400)
  #expect(month.returnPercent == 0)
}
@Test func firstMonthDoesNotInventOpeningBalance() {
  let data = envelope([
    report(.soxl, "2026-09-02", assets: 1100, pnl: 100),
    report(.soxl, "2026-09-03", assets: 1150, pnl: 150),
  ])
  let month = Performance.monthly(data, scope: .soxl).first!
  #expect(month.profit == nil && month.returnPercent == nil && month.partial)
  #expect(month.assetChange == 50)
}
@Test func missingPnlAndLongGapsArePartial() {
  let missing = envelope(monthSeries(assets: { _ in 1000 }, pnl: { $0 == 10 ? nil : 0 }))
  #expect(Performance.monthly(missing, scope: .soxl).first!.partial)
  let gap = envelope([
    report(.soxl, "2026-08-31", assets: 1000, pnl: 0),
    report(.soxl, "2026-09-30", assets: 1100, pnl: 100),
  ])
  #expect(Performance.monthly(gap, scope: .soxl).first!.profit == nil)
}
@Test func combinedRequiresBothInvestmentsAndDatedFX() {
  let data = envelope(
    [
      report(.soxl, "2026-09-01", assets: 100, pnl: 0),
      report(.hyxl, "2026-09-02", assets: 5000, pnl: 0),
    ], rates: [FXRate(date: "2026-09-02", usdKrw: 1400)])
  let points = Performance.points(data, scope: .all)
  #expect(points.count == 1)
  #expect(points[0].assets == 145000)
  #expect(points[0].hasCarriedValuation)
  #expect(Performance.points(envelope(data.reports), scope: .all).isEmpty)
}
@Test func combinedIncludesFXMovement() {
  var reports: [DailyReport] = []
  var rates: [FXRate] = []
  for day in 0...30 {
    let date = day == 0 ? "2026-08-31" : String(format: "2026-09-%02d", day)
    reports += [
      report(.soxl, date, assets: 100, pnl: 0), report(.hyxl, date, assets: 10000, pnl: 0),
    ]
    rates.append(FXRate(date: date, usdKrw: 1300 + Double(day) * 5))
  }
  let month = Performance.monthly(envelope(reports, rates: rates), scope: .all).first!
  #expect(month.profit == 15000)
  #expect(month.cashflow == 0)
}
@Test func staleOrFutureRatesAreNeverUsed() {
  #expect(
    Performance.fx(on: "2026-09-10", rates: [FXRate(date: "2026-09-01", usdKrw: 1400)]) == nil)
  #expect(
    Performance.fx(on: "2026-09-10", rates: [FXRate(date: "2026-09-11", usdKrw: 1400)]) == nil)
}
@Test func datedKeysDoNotShiftWithDeviceTimezone() {
  #expect(ReportDate.key(ReportDate.parse("2026-09-18")) == "2026-09-18")
  #expect(ReportDate.days("2026-08-31", "2026-09-01") == 1)
}
