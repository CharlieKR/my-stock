import Foundation
import Testing
@testable import MyStockCore

@Test func decimalPerformanceSurvivesDiskEncoding() throws {
  let json = #"{"calculationVersion":"v2","points":[{"date":"2026-09-18","assets":"123456789.01","fx":"1350.12345678","constituentIDs":[]}],"months":[{"month":"2026-09","startDate":"2026-08-31","endDate":"2026-09-18","startAssets":"100.01","endAssets":"123456789.01","profit":null,"returnPercent":null,"cashflow":null,"partial":true,"estimated":false}]}"#
  let value=try JSONDecoder().decode(ServerPerformance.self,from:Data(json.utf8))
  let cache=try JSONEncoder().encode(value)
  let loaded=try JSONDecoder().decode(ServerPerformance.self,from:cache)
  #expect(loaded.points[0].assets.decimal == Decimal(string:"123456789.01"))
  #expect(loaded.months[0].profit == nil)
  #expect(loaded.months[0].display.profit == nil)
}

@Test func historicalProfitCoverageSurvivesDiskEncoding() throws {
  let json = #"{"month":"2026-07","startDate":"2026-07-03","endDate":"2026-07-31","startAssets":"100","endAssets":"130","profit":"20","returnPercent":"19.5","cashflow":"10","partial":true,"estimated":true,"reason":"2026-07-03부터 계산한 추정 수익"}"#
  let value=try JSONDecoder().decode(ServerMonth.self,from:Data(json.utf8))
  let loaded=try JSONDecoder().decode(ServerMonth.self,from:JSONEncoder().encode(value))
  #expect(loaded.display.startDate == "2026-07-03")
  #expect(loaded.display.profit == 20)
  #expect(loaded.display.estimated)
  #expect(loaded.display.reason == "2026-07-03부터 계산한 추정 수익")
}
