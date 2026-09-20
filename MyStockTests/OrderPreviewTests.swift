import Testing

@testable import MyStockCore

@Test func parsesWonOrdersAndKeepsQuantities() {
  let message = ThreadMessage(
    id: "1",
    text:
      ":clipboard: *주문표* 2026-09-18\n- 매수 KODEX 2,580주 @ ₩10,500 / ₩27,090,000\n- 매도 ACE 1,026주 @ ₩10,960 / ₩11,244,960",
    date: "")
  #expect(message.orderPreviews.count == 2)
  #expect(message.orderPreviews[0].quantity == "2,580")
  #expect(message.orderPreviews[1].amount == "₩11,244,960")
}
@Test func parsesStrategyHeadingsAndOrderTypes() {
  let message = ThreadMessage(
    id: "2",
    text: "주문표\n동파\n- 매도 15주 @ $166.26 / $2,493.90 LOC\nTide\n- 매수 80주 @ $108.41 / $8,672.80 LOC",
    date: "")
  #expect(message.orderPreviews[0].name == "동파")
  #expect(message.orderPreviews[1].name == "Tide")
  #expect(message.orderPreviews[1].type == "LOC")
}
