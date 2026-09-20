import Foundation

enum Investment: String, Codable, CaseIterable, Identifiable, Sendable {
  case soxl = "SOXL"
  case hyxl = "HYXL"
  var id: String { rawValue }
  var currency: String { self == .soxl ? "USD" : "KRW" }
  var subtitle: String { self == .soxl ? "Tide · 동파 · Tail" : "하이닉스 · ACE · KODEX" }
  var symbol: String { self == .soxl ? "chart.line.uptrend.xyaxis" : "chart.bar.xaxis" }
  var timezone: String { self == .soxl ? "미국 거래일 기준" : "한국 거래일 기준" }
}

struct DailyReport: Codable, Identifiable, Sendable {
  enum CodingKeys: String, CodingKey {
    case id, investment, date, currency, status, totalAssets, stockValue, cash, cumulativePnl
    case cumulativeReturn, dailyPnl, dailyPnlLabel, details, rawText, slackURL, threadTS, updatedAt
    case messages, quality, hasOrderPlan, plannedOrderCount
  }
  var messages: [ThreadMessage]? = nil
  let id: String
  let investment: Investment
  let date: String
  let currency: String
  let status: String
  let totalAssets: Double?
  let stockValue: Double?
  let cash: Double?
  let cumulativePnl: Double?
  let cumulativeReturn: Double?
  let dailyPnl: Double?
  let dailyPnlLabel: String
  let details: [ReportDetail]
  let rawText: String
  let slackURL: String
  let threadTS: String
  let updatedAt: String
  let quality: String?
  let hasOrderPlan: Bool?
  let plannedOrderCount: Int?
  var day: Date { ReportDate.parse(date) }
  var isValued: Bool { status == "settled" && totalAssets != nil }
  var isOrderPlan: Bool {
    hasOrderPlan == true
      || messages?.contains(where: { $0.title.contains("주문") }) == true
      || details.contains(where: { $0.title.contains("주문") || $0.text.contains("주문금액") })
  }
  var statusTitle: String {
    status == "closed" ? "휴장" : status == "settled" ? "정산 완료" : isOrderPlan ? "주문 예정" : "정산 대기"
  }
  var hasLegacySettlementSource: Bool {
    quality == "legacy_archive" || (quality == nil && !slackURL.isEmpty)
  }
}

struct ReportDetail: Codable, Identifiable, Sendable {
  let id: String
  let title: String
  let text: String
}

struct FXRate: Codable, Sendable {
  enum CodingKeys: String, CodingKey { case date, usdKrw }
  let date: String
  let usdKrw: Double
}

struct ReportSource: Codable, Identifiable, Sendable {
  let investment: Investment
  let status: String
  let message: String
  let lastSyncedAt: String?
  var id: String { investment.rawValue }
}

struct ReportEnvelope: Codable, Sendable {
  var datasetId: String? = nil
  var revision: String? = nil
  var calculationVersion: String? = nil
  var performance: [String: ServerPerformance]? = nil
  let schemaVersion: Int
  let generatedAt: String?
  let reports: [DailyReport]
  let fxRates: [FXRate]
  let fxSource: String?
  let fxMessage: String?
  let sources: [ReportSource]
  static let empty = ReportEnvelope(
    schemaVersion: 1, generatedAt: nil, reports: [], fxRates: [], fxSource: nil, fxMessage: nil,
    sources: [])
}

struct ThreadMessage: Codable, Identifiable, Sendable {
  let id: String
  let text: String
  let date: String
  var title: String {
    let first = text.components(separatedBy: .newlines).first ?? "상세 리포트"
    return Self.clean(first)
  }
  var body: String {
    Self.clean(text.components(separatedBy: .newlines).dropFirst().joined(separator: "\n"))
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
  var symbol: String {
    if title.contains("주문") { return "list.bullet.rectangle" }
    if title.contains("실행") { return "paperplane" }
    if title.contains("결과") { return "checklist" }
    if title.contains("비교") { return "chart.xyaxis.line" }
    return "doc.text"
  }
  static func clean(_ text: String) -> String {
    text.replacingOccurrences(of: ":[a-z_0-9+-]+:", with: "", options: .regularExpression)
      .replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "```", with: "")
      .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&lt;", with: "<")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
struct ThreadEnvelope: Codable, Sendable {
  let messages: [ThreadMessage]
  let partial: Bool
}

enum ReportDate {
  static var calendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(secondsFromGMT: 0)!
    return c
  }
  static func parse(_ value: String) -> Date {
    let parts = value.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return .distantPast }
    return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
      ?? .distantPast
  }
  static func key(_ date: Date) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
  }
  static func label(_ value: String, format: String = "M월 d일 EEEE") -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ko_KR")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = format
    return formatter.string(from: parse(value))
  }
  static func days(_ a: String, _ b: String) -> Double {
    parse(b).timeIntervalSince(parse(a)) / 86400
  }
}
