import Foundation

// Ignore document/layout changes and bounce; require deliberate movement before
// changing the bar, so small finger movements do not flicker its labels.
struct TabBarScrollTracker {
  private var travel: CGFloat = 0

  mutating func update(from old: CGFloat, to new: CGFloat, maximum: CGFloat, userScrolling: Bool)
    -> Bool?
  {
    guard userScrolling, maximum > 24, old.isFinite, new.isFinite else {
      travel = 0
      return nil
    }
    if new <= 0 {
      travel = 0
      return false
    }
    guard new <= maximum, old >= 0, old <= maximum else {
      travel = 0
      return nil
    }
    let delta = new - old
    if delta * travel < 0 { travel = 0 }
    travel += delta
    if travel >= 18 {
      travel = 0
      return true
    }
    if travel <= -10 {
      travel = 0
      return false
    }
    return nil
  }
}
