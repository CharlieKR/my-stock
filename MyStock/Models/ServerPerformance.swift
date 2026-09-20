import Foundation

/// Decimal wire values stay exact in the disk cache. Double conversion is for existing presentation/chart models.
struct WireAmount: Codable, Sendable {
  let decimal: Decimal
  var value: Double { NSDecimalNumber(decimal: decimal).doubleValue }
  init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if let s = try? c.decode(String.self), let d = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) { decimal = d }
    else { decimal = try c.decode(Decimal.self) }
  }
  func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    try c.encode(NSDecimalNumber(decimal: decimal).stringValue)
  }
}

struct ServerPerformance: Codable, Sendable {
  var periods: [String: ServerPerformance]? = nil
  var summary: ServerMonth? = nil
  let calculationVersion: String
  let points: [ServerAssetPoint]
  let months: [ServerMonth]
  func assetPoints(in envelope: ReportEnvelope) -> [AssetPoint] {
    let reports = Dictionary(envelope.reports.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    return points.map { p in AssetPoint(date:p.date, assets:p.assets.value,
      constituents:p.constituentIDs.compactMap { reports[$0] }, fx:p.fx.value) }
  }
}
struct ServerAssetPoint: Codable, Sendable {
  let date: String
  let assets: WireAmount
  let fx: WireAmount
  let constituentIDs: [String]
}
struct ServerMonth: Codable, Sendable {
  let month: String
  let startDate: String
  let endDate: String
  let startAssets: WireAmount
  let endAssets: WireAmount
  let profit: WireAmount?
  let returnPercent: WireAmount?
  let cashflow: WireAmount?
  let partial: Bool
  let estimated: Bool
  var reason: String? = nil
  var coverageLabel: String? = nil
  var display: MonthlyPerformance {
    MonthlyPerformance(month:month,startDate:startDate,endDate:endDate,startAssets:startAssets.value,
      endAssets:endAssets.value,profit:profit?.value,returnPercent:returnPercent?.value,
      cashflow:cashflow?.value,partial:partial,estimated:estimated,reason:reason,coverageLabel:coverageLabel)
  }
}

extension DailyReport {
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy:CodingKeys.self)
    func amount(_ key: CodingKeys) throws -> Double? { try c.decodeIfPresent(WireAmount.self,forKey:key)?.value }
    id=try c.decode(String.self,forKey:.id); investment=try c.decode(Investment.self,forKey:.investment)
    date=try c.decode(String.self,forKey:.date); currency=try c.decode(String.self,forKey:.currency)
    status=try c.decode(String.self,forKey:.status)
    totalAssets=try amount(.totalAssets);stockValue=try amount(.stockValue);cash=try amount(.cash)
    cumulativePnl=try amount(.cumulativePnl);cumulativeReturn=try amount(.cumulativeReturn);dailyPnl=try amount(.dailyPnl)
    dailyPnlLabel=try c.decode(String.self,forKey:.dailyPnlLabel);details=try c.decode([ReportDetail].self,forKey:.details)
    rawText=try c.decode(String.self,forKey:.rawText);slackURL=try c.decode(String.self,forKey:.slackURL)
    threadTS=try c.decode(String.self,forKey:.threadTS);updatedAt=try c.decode(String.self,forKey:.updatedAt)
    messages=try c.decodeIfPresent([ThreadMessage].self,forKey:.messages)
    quality=try c.decodeIfPresent(String.self,forKey:.quality)
    hasOrderPlan=try c.decodeIfPresent(Bool.self,forKey:.hasOrderPlan)
    plannedOrderCount=try c.decodeIfPresent(Int.self,forKey:.plannedOrderCount)
  }
}
extension FXRate {
  init(from decoder: Decoder) throws {
    let c=try decoder.container(keyedBy:CodingKeys.self)
    date=try c.decode(String.self,forKey:.date);usdKrw=try c.decode(WireAmount.self,forKey:.usdKrw).value
  }
}
