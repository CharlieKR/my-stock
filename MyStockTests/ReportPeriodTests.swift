import Testing
import Foundation
@testable import MyStockCore

@Test func rollingPeriodsRespectCalendarBoundaries() {
  #expect(ReportPeriod.week.start(ending:"2026-09-18")=="2026-09-12")
  #expect(ReportPeriod.month.start(ending:"2026-03-31")=="2026-03-01")
  #expect(ReportPeriod.year.start(ending:"2024-02-29")=="2023-03-01")
  #expect(ReportPeriod.quarter.start(ending:"2026-09-18")=="2026-06-19")
  #expect(ReportPeriod.all.start(ending:"2026-09-18")==nil)
}

@Test func preparedChartLookupMatchesNearestDateIncludingEdges() {
  let points = ["2026-06-26", "2026-06-29", "2026-06-30"].enumerated().map { index, date in
    AssetPoint(date: date, assets: Double(100 + index * 10), constituents: [], fx: 1)
  }
  let data = AssetChartData(points: points)
  #expect(data.nearestIndex(to: ReportDate.parse("2026-06-01")) == 0)
  #expect(data.nearestIndex(to: ReportDate.parse("2026-06-28")) == 1)
  #expect(data.nearestIndex(to: ReportDate.parse("2026-06-30")) == 2)
  #expect(data.nearestIndex(to: ReportDate.parse("2026-07-01")) == 2)
  #expect(AssetChartData(points: []).nearestIndex(to: Date()) == nil)
  #expect(data.domain.lowerBound < 100 && data.domain.upperBound > 120)
  for hours in 0..<144 {
    let date = ReportDate.parse("2026-06-25").addingTimeInterval(Double(hours) * 3600)
    let expected = data.dates.indices.min { abs(data.dates[$0].timeIntervalSince(date)) < abs(data.dates[$1].timeIntervalSince(date)) }
    #expect(data.nearestIndex(to: date) == expected)
  }
}
