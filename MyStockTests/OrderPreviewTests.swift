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
  #expect(!message.orderPreviews[0].isUnfilled)
}

@Test func marksOnlyFailedFillStatesAsUnfilled() {
  let result = ThreadMessage(
    id: "result",
    text:
      "체결 결과\n- 매수 SOXL 10주 @ $100 / $1,000 LOC · 체결 완료\n- 매도 SOXL 5주 @ $110 / $550 LOC · 미체결",
    date: "")
  #expect(!result.orderPreviews[0].isUnfilled)
  #expect(result.orderPreviews[1].isUnfilled)
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

@Test func submissionSummaryKeepsSubmittedAndRejectedCounts() {
  let message = ThreadMessage(
    id: "execution", text: "주문 제출\n제출 2건 · 거부 2건", date: "2026-09-18T06:00:00Z")
  #expect(message.activityStatus == "제출 2건 · 거부 2건")
}

@Test func orderCardAdvancesFromPlanToSubmissionWithoutDuplicatingRows() {
  let plan = ThreadMessage(
    id: "plan", text: "주문표 생성\n- 매수 KODEX 10주 @ ₩10,000 / ₩100,000 LOC · 예정",
    date: "2026-09-18T00:00:00Z")
  let submission = ThreadMessage(
    id: "execution", text: "주문 제출\n- 매수 KODEX 8주 @ ₩10,000 / ₩80,000 LOC · 제출 완료",
    date: "2026-09-18T00:10:00Z")
  let planned = OrderActivity.timeline([plan])
  let submitted = OrderActivity.timeline([submission, plan])
  #expect(planned.count == 1)
  #expect(planned[0].message.activityTitle == "주문표")
  #expect(planned[0].orders[0].type == "LOC · 예정")
  #expect(submitted.count == 1)
  #expect(submitted[0].id == planned[0].id)
  #expect(submitted[0].message.activityTitle == "주문 제출")
  #expect(submitted[0].message.date == submission.date)
  #expect(submitted[0].orders.count == 1)
  #expect(submitted[0].orders[0].quantity == "8")
  #expect(submitted[0].orders[0].type == "LOC · 제출 완료")
}

@Test func historicalSubmissionRetainsPlanAndRejectionCountsWithoutInventingRowStatus() {
  let plan = ThreadMessage(
    id: "plan", text: "주문표 생성\n- 매수 SOXL 10주 @ $100 / $1,000 LOC · 예정",
    date: "2026-09-18T00:00:00Z")
  let submission = ThreadMessage(
    id: "execution", text: "주문 제출\n제출 0건 · 거부 1건", date: "2026-09-18T00:10:00Z")
  let result = ThreadMessage(
    id: "result", text: "체결 결과\n- 매수 SOXL 10주 @ $100 / $1,000 LOC · 미체결",
    date: "2026-09-18T06:00:00Z")
  let activities = OrderActivity.timeline([result, submission, plan])
  #expect(activities.count == 2)
  #expect(activities[0].showsSubmissionSummary)
  #expect(activities[0].message.activityStatus == "제출 0건 · 거부 1건")
  #expect(activities[0].orders[0].amount == "$1,000")
  #expect(activities[0].orders[0].type == "LOC")
  #expect(activities[1].message.activityTitle == "체결 결과")
  #expect(activities[1].orders[0].isUnfilled)
}

@Test func submissionCanBeShownWithoutAnEarlierPlan() {
  let submission = ThreadMessage(
    id: "execution", text: "주문 제출\n제출 2건", date: "2026-09-18T00:10:00Z")
  let activities = OrderActivity.timeline([submission])
  #expect(activities.count == 1)
  #expect(activities[0].showsSubmissionSummary)
  #expect(activities[0].orders.isEmpty)
  #expect(activities[0].message.activityTitle == "주문 제출")
}

@Test(arguments: [
  ("제출 완료", "완료"),
  ("제출 0건 · 거부 1건", "제출 0건 · 거부 1건"),
  ("- 매수 SOXL 10주 @ $100 / $1,000 LOC · 제출 완료", "완료"),
  ("- 매수 SOXL 10주 @ $100 / $1,000 LOC · 거부", "확인 필요"),
  ("- 매수 SOXL 10주 @ $100 / $1,000 LOC · 예정", "확인 대기"),
])
func submissionHeaderDoesNotTreatRejectedOrPendingOrdersAsComplete(body: String, expected: String) {
  let message = ThreadMessage(id: "execution", text: "주문 제출\n" + body, date: "")
  let activity = OrderActivity(id: "orders", message: message, plan: nil)
  #expect(activity.submissionStatus == expected)
}
