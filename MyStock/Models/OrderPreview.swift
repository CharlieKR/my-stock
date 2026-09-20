import Foundation

struct OrderPreview: Identifiable {
  let id: Int
  let side: String
  let name: String
  let quantity: String
  let price: String
  let amount: String
  let type: String
  var isUnfilled: Bool {
    ["미체결", "거부", "취소", "실패"].contains { type.contains($0) }
  }
}

/// Plan and execution messages are snapshots of the same day's orders.
/// Keep fills separate, while advancing the order card to its submitted state.
struct OrderActivity: Identifiable {
  let id: String
  let message: ThreadMessage
  let plan: ThreadMessage?

  var isSubmission: Bool { message.activityTitle == "주문 제출" }
  var showsSubmissionSummary: Bool { isSubmission && message.orderPreviews.isEmpty }
  var orders: [OrderPreview] {
    let rows = message.orderPreviews
    guard showsSubmissionSummary, let plan else { return rows }
    // Historical execution summaries have counts, but no per-order outcome.
    // Preserve the plan's amounts without claiming each order was submitted.
    return plan.orderPreviews.map {
      OrderPreview(
        id: $0.id, side: $0.side, name: $0.name, quantity: $0.quantity,
        price: $0.price, amount: $0.amount,
        type: $0.type.components(separatedBy: " · ").filter { $0 != "예정" }.joined(separator: " · "))
    }
  }

  static func timeline(_ messages: [ThreadMessage]) -> [OrderActivity] {
    let messages = messages.filter(\.isOrderActivity).sorted { $0.date < $1.date }
    let plan = messages.last { $0.activityTitle == "주문표" }
    let submission = messages.last { $0.activityTitle == "주문 제출" }
    var activities = messages.filter { $0.activityTitle == "체결 결과" }.map {
      OrderActivity(id: $0.id, message: $0, plan: nil)
    }
    if let current = submission ?? plan {
      activities.append(OrderActivity(id: "daily-orders", message: current, plan: plan))
    }
    return activities.sorted { $0.message.date < $1.message.date }
  }
}

extension ThreadMessage {
  var orderPreviews: [OrderPreview] {
    guard title.contains("주문") || title.contains("체결"),
      let expression = try? NSRegularExpression(
        pattern:
          #"^-\s*(매수|매도)\s+(?:(\S+)\s+)?([\d,]+)주\s*@\s*([$₩][\d,.]+)\s*/\s*([$₩][\d,.]+)(?:\s+(.+))?"#
      )
    else { return [] }
    var rows: [OrderPreview] = []
    for line in body.components(separatedBy: .newlines).map({
      $0.trimmingCharacters(in: .whitespaces)
    }) {
      let source = line as NSString
      guard
        let match = expression.firstMatch(
          in: line, range: NSRange(location: 0, length: source.length))
      else { continue }
      func text(_ index: Int) -> String {
        let range = match.range(at: index)
        return range.location == NSNotFound ? "" : source.substring(with: range)
      }
      rows.append(
        OrderPreview(
          id: rows.count, side: text(1), name: text(2).isEmpty ? "SOXL" : text(2),
          quantity: text(3), price: text(4), amount: text(5), type: text(6)))
    }
    return rows
  }
}
