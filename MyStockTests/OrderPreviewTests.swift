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

@Test func parsesDatabaseOrderPlans() {
  let message = ThreadMessage(
    id: "plan",
    text: "주문 계획 · ls_main\n- 매수 KODEX 2,141주 @ ₩12,660 / ₩27,105,060 LOC\n제출 전 계획입니다.",
    date: "2026-09-18T07:30:20Z")
  #expect(message.orderPreviews.count == 1)
  #expect(message.orderPreviews[0].side == "매수")
  #expect(message.orderPreviews[0].name == "KODEX")
  #expect(message.orderPreviews[0].amount == "₩27,105,060")
  #expect(message.orderPreviews[0].type == "LOC")
}

@Test func parsesOrderStatusAfterOrderType() {
  let message = ThreadMessage(
    id: "submitted",
    text: "주문 제출\n- 매도 ACE 1,026주 @ ₩10,960 / ₩11,244,960 LOC · 제출 완료",
    date: "2026-09-21T00:01:00Z")
  #expect(message.orderPreviews[0].type == "LOC · 제출 완료")
}
@Test func parsesStrategyHeadingsAndOrderTypes() {
  let message = ThreadMessage(
    id: "2",
    text: "주문표\n동파\n- 매도 15주 @ $166.26 / $2,493.90 LOC\nTide\n- 매수 80주 @ $108.41 / $8,672.80 LOC",
    date: "")
  #expect(message.orderPreviews[0].name == "SOXL")
  #expect(message.orderPreviews[1].name == "SOXL")
  #expect(message.orderPreviews[1].type == "LOC")
}

@Test func keepsOnlyOrderLifecycleMessagesForTheTimeline() {
  let settlement = ThreadMessage(
    id: "settled", text: "정산 완료\n자산 : 총 ₩173,660,462", date: "2026-09-18T07:00:00Z")
  let comparison = ThreadMessage(
    id: "comparison", text: "전략비교\n결론: 동일", date: "2026-09-18T06:00:00Z")
  let result = ThreadMessage(
    id: "result", text: "주문결과\n- 매도 SOXL 15주 @ $166.26 / $2,493.90 LOC · 미체결",
    date: "2026-09-18T06:50:00Z")
  #expect(!settlement.isOrderActivity)
  #expect(!comparison.isOrderActivity)
  #expect(result.isOrderActivity)
  #expect(result.activityTitle == "체결 결과")
}
