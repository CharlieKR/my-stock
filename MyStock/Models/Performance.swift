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
