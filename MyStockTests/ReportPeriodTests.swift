import Testing
@testable import MyStockCore

@Test func rollingPeriodsRespectCalendarBoundaries() {
  #expect(ReportPeriod.week.start(ending:"2026-09-18")=="2026-09-12")
  #expect(ReportPeriod.month.start(ending:"2026-03-31")=="2026-03-01")
  #expect(ReportPeriod.year.start(ending:"2024-02-29")=="2023-03-01")
  #expect(ReportPeriod.quarter.start(ending:"2026-09-18")=="2026-06-19")
  #expect(ReportPeriod.all.start(ending:"2026-09-18")==nil)
}
