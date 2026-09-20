import Foundation

struct OrderPreview: Identifiable {
  let id: Int
  let side: String
  let name: String
  let quantity: String
  let price: String
  let amount: String
  let type: String
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
