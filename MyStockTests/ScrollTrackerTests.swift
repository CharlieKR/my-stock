import Testing

@testable import MyStockCore

@Test func deliberateScrollAndDirectionReversal() {
  var tracker = TabBarScrollTracker()
  #expect(tracker.update(from: 0, to: 12, maximum: 500, userScrolling: true) == nil)
  #expect(tracker.update(from: 12, to: 18, maximum: 500, userScrolling: true) == true)
  #expect(tracker.update(from: 18, to: 13, maximum: 500, userScrolling: true) == nil)
  #expect(tracker.update(from: 13, to: 8, maximum: 500, userScrolling: true) == false)
}
@Test func ignoresInertiaBounceAndShortPages() {
  var tracker = TabBarScrollTracker()
  #expect(tracker.update(from: 10, to: 70, maximum: 500, userScrolling: false) == nil)
  #expect(tracker.update(from: 490, to: 520, maximum: 500, userScrolling: true) == nil)
  #expect(tracker.update(from: 0, to: 18, maximum: 20, userScrolling: true) == nil)
  #expect(tracker.update(from: 8, to: -2, maximum: 500, userScrolling: true) == false)
}
