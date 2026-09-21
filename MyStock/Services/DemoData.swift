import Foundation

enum DemoData {
  // Synthetic, explicitly opt-in data. Personal Slack reports are never bundled.
  static var envelope: ReportEnvelope {
    var reports: [DailyReport] = []
    var rates: [FXRate] = []
    for offset in 0..<180 {
      let day = ReportDate.calendar.date(
        byAdding: .day, value: offset, to: ReportDate.parse("2026-03-23"))!
      let key = ReportDate.key(day)
      rates.append(FXRate(date: key, usdKrw: 1340 + sin(Double(offset) / 24) * 35))
      guard ![1, 7].contains(ReportDate.calendar.component(.weekday, from: day)) else { continue }
      for investment in Investment.allCases {
        let principal = investment == .soxl ? 85000.0 : 98_000_000
        let pnl = principal * (Double(offset) * 0.0014 + sin(Double(offset) / 14) * 0.023)
        let assets = principal + pnl
        let stock = assets * (investment == .soxl ? 0.28 : 0.43)
        let id = "\(investment.rawValue)-\(key)"
        reports.append(
          DailyReport(
            quotes: investment == .soxl
              ? [ClosingQuote(symbol: "SOXL", name: "SOXL", date: key, currency: "USD", close: 82.40, change: 1.40, changePercent: 1.73)]
              : [ClosingQuote(symbol: "0193T0", name: "KODEX 하이닉스", date: key, currency: "KRW", close: 11200, change: 200, changePercent: 1.82)],
            id: id, investment: investment, date: key, currency: investment.currency,
            status: "settled",
            totalAssets: assets, stockValue: stock, cash: assets - stock, cumulativePnl: pnl,
            cumulativeReturn: pnl / principal * 100,
            dailyPnl: principal * 0.0021, dailyPnlLabel: "오늘 손익",
            details: [
              ReportDetail(id: id + "fill", title: "체결", text: "매수 24주 · 매도 18주"),
              ReportDetail(
                id: id + "income", title: investment == .soxl ? "RP" : "CMA", text: "이자 정산 완료"),
              ReportDetail(
                id: id + "tail", title: investment == .soxl ? "Tail" : "운용 상태",
                text: investment == .soxl ? "오늘 미진입 · 조건 대기" : "ACE · KODEX 정상 운용"),
            ],
            rawText: "샘플 리포트입니다. 실제 투자 정보가 아닙니다.", slackURL: "", threadTS: "",
            updatedAt: "2026-09-18T08:00:00Z", quality: "demo", hasOrderPlan: nil,
            plannedOrderCount: nil))
      }
    }
    return ReportEnvelope(
      schemaVersion: 1, generatedAt: "2026-09-18T08:00:00Z", reports: reports, fxRates: rates,
      fxSource: "샘플 환율", fxMessage: nil,
      sources: Investment.allCases.map {
        ReportSource(investment: $0, status: "ready", message: "샘플 데이터", lastSyncedAt: nil)
      })
  }
  static func thread(_ report: DailyReport) -> ThreadEnvelope {
    ThreadEnvelope(
      messages: [
        ThreadMessage(
          id: "orders",
          text:
            "주문표\n\nTide\n- 매수 24주 @ $82.40 / $1,977.60 LOC\n- 매도 18주 @ $88.20 / $1,587.60 LOC\n\n요약: 매수 24주 / 매도 18주",
          date: "2026-09-18T01:00:00Z"),
        ThreadMessage(
          id: "result", text: "주문결과\n\n체결\n- 매수 24주\n- 매도 18주\n\n미체결\n- 없음",
          date: "2026-09-18T08:00:00Z"),
      ], partial: false)
  }
}
