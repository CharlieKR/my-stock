import Foundation

enum ReportScope: String, CaseIterable, Identifiable {
  case all = "전체"
  case soxl = "SOXL"
  case hyxl = "HYXL"
  var id: String { rawValue }
  var currency: String { self == .soxl ? "USD" : "KRW" }
  var investments: [Investment] {
    self == .all ? Investment.allCases : [self == .soxl ? .soxl : .hyxl]
  }
}

struct AssetPoint: Identifiable {
  let date: String
  let assets: Double
  let constituents: [DailyReport]
  let fx: Double
  var id: String { date }
  var day: Date { ReportDate.parse(date) }
  var hasCarriedValuation: Bool { constituents.contains { $0.date != date } }
  /// Settlement P&L and principal use the same FX rate as this asset snapshot.
  /// Period returns belong to the report screen, not this cumulative balance.
  var cumulativeProfit: Double? {
    guard !constituents.isEmpty else { return nil }
    var total = 0.0
    for report in constituents {
      guard let profit = report.cumulativePnl, profit.isFinite else { return nil }
      let rate = report.currency == "USD" ? fx : 1
      guard rate.isFinite, rate > 0 else { return nil }
      total += profit * rate
    }
    return total.isFinite ? total : nil
  }
  var cumulativeReturn: Double? {
    guard let profit = cumulativeProfit, assets.isFinite, assets - profit > 0 else { return nil }
    return profit / (assets - profit) * 100
  }
}

extension Array where Element == AssetPoint {
  /// The change from the immediately preceding recorded point in this series.
  func assetChange(at point: AssetPoint?) -> Double? {
    guard let point, let index = firstIndex(where: { $0.id == point.id }), index > startIndex
    else { return nil }
    return point.assets - self[index - 1].assets
  }
}

/// Prepared once per series, not for every movement of the chart cursor.
struct AssetChartData {
  let points: [AssetPoint]
  let dates: [Date]
  let domain: ClosedRange<Double>
  init(points: [AssetPoint]) {
    self.points = points
    dates = points.map(\.day)
    let low = points.map(\.assets).min() ?? 0
    let high = points.map(\.assets).max() ?? 1
    let gap = max((high - low) * 0.24, max(1, high * 0.015))
    domain = max(0, low - gap)...(high + gap)
  }
  func nearestIndex(to date: Date) -> Int? {
    guard !dates.isEmpty else { return nil }
    var low = 0, high = dates.count
    while low < high {
      let middle = (low + high) / 2
      if dates[middle] < date { low = middle + 1 } else { high = middle }
    }
    if low == 0 { return 0 }
    if low == dates.count { return dates.count - 1 }
    return date.timeIntervalSince(dates[low - 1]) <= dates[low].timeIntervalSince(date) ? low - 1 : low
  }
}

struct MonthlyPerformance: Identifiable {
  let month: String
  let startDate: String
  let endDate: String
  let startAssets: Double
  let endAssets: Double
  let profit: Double?
  let returnPercent: Double?
  let cashflow: Double?
  let partial: Bool
  let estimated: Bool
  var reason: String? = nil
  var coverageLabel: String? = nil
  var periodLabel: String? {
    coverageLabel ?? (partial ? (profit == nil ? "근거 부족" : "\(ReportDate.label(startDate, format: "M.d"))부터") : nil)
  }
  var id: String { month }
  var assetChange: Double { endAssets - startAssets }
  var label: String { ReportDate.label(month + "-01", format: "M월") }
}

enum Performance {
  static func fx(on date: String, rates: [FXRate]) -> FXRate? {
    rates.filter { $0.date <= date && $0.usdKrw > 0 && ReportDate.days($0.date, date) <= 7 }
      .max { $0.date < $1.date }
  }

  static func points(_ envelope: ReportEnvelope, scope: ReportScope) -> [AssetPoint] {
    let valued = envelope.reports.filter {
      scope.investments.contains($0.investment) && $0.isValued
    }
    let dates = Set(valued.map(\.date)).sorted()
    return dates.compactMap { date in
      let parts = scope.investments.compactMap { investment in
        valued.filter {
          $0.investment == investment && $0.date <= date && ReportDate.days($0.date, date) <= 7
        }.max { $0.date < $1.date }
      }
      guard parts.count == scope.investments.count else { return nil }
      let rate: Double
      if scope == .all {
        guard let value = fx(on: date, rates: envelope.fxRates) else { return nil }
        rate = value.usdKrw
      } else {
        rate = 1
      }
      let assets = parts.reduce(0) {
        $0 + ($1.totalAssets ?? 0) * (scope == .all && $1.currency == "USD" ? rate : 1)
      }
      return AssetPoint(date: date, assets: assets, constituents: parts, fx: rate)
    }
  }

  static func monthly(_ envelope: ReportEnvelope, scope: ReportScope) -> [MonthlyPerformance] {
    let series = points(envelope, scope: scope)
    let months = Set(series.map { String($0.date.prefix(7)) }).sorted()
    return months.compactMap { month in
      let inside = series.filter { $0.date.hasPrefix(month) }
      guard let first = inside.first, let end = inside.last else { return nil }
      let boundary = month + "-01"
      let previous = series.last { $0.date < boundary && ReportDate.days($0.date, boundary) <= 7 }
      let start = previous ?? first
      let relevant = series.filter { $0.date >= start.date && $0.date <= end.date }
      // Principal = assets − cumulative investment P&L. Its change estimates
      // external cash flow. Settlement reports don't provide exact flow timing.
      var flows = 0.0
      var weighted = 0.0
      var valid = previous != nil
      var estimated = false
      let duration = max(1, ReportDate.days(start.date, end.date))
      for (a, b) in zip(relevant, relevant.dropFirst()) {
        if ReportDate.days(a.date, b.date) > 7 { valid = false }
        for investment in scope.investments {
          guard let before = a.constituents.first(where: { $0.investment == investment }),
            let after = b.constituents.first(where: { $0.investment == investment }),
            let oldPnl = before.cumulativePnl, let newPnl = after.cumulativePnl,
            let oldAssets = before.totalAssets, let newAssets = after.totalAssets
          else {
            valid = false
            continue
          }
          let flow = (newAssets - newPnl) - (oldAssets - oldPnl)
          let tolerance = investment == .soxl ? 0.05 : 5.0
          if abs(flow) <= tolerance { continue }
          estimated = true
          let converted: Double
          if scope == .all && investment == .soxl {
            guard let rate = fx(on: after.date, rates: envelope.fxRates) else {
              valid = false
              continue
            }
            converted = flow * rate.usdKrw
          } else {
            converted = flow
          }
          flows += converted
          weighted += converted * max(0, ReportDate.days(after.date, end.date)) / duration
        }
      }
      let pnl = end.assets - start.assets - flows
      let denominator = start.assets + weighted
      return MonthlyPerformance(
        month: month, startDate: start.date, endDate: end.date,
        startAssets: start.assets, endAssets: end.assets,
        profit: valid ? pnl : nil,
        returnPercent: valid && denominator > 0 ? pnl / denominator * 100 : nil,
        cashflow: valid ? flows : nil, partial: !valid, estimated: estimated)
    }.reversed()
  }
}
