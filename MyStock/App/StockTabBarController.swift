import SwiftUI
import UIKit

// Adapted from appchart AppChartHost.swift: native glass, three-icon compaction,
// direct compact hit testing, press/slide gestures, and accessibility fallbacks.
final class StockTabBarController: UITabBarController, UITabBarControllerDelegate {
  private(set) var isCompact = false
  private var compactTouch: CompactTabTouch?
  private weak var compactSelectionDestination: UIViewController?
  private let selectionFeedback = UISelectionFeedbackGenerator()
  private lazy var compactTouchSurface: CompactTabTouchSurface = {
    let surface = CompactTabTouchSurface()
    surface.acceptsTouch = { [weak self] in self?.acceptsCompactTouch(at: $0) == true }
    surface.onBegin = { [weak self] in self?.beginCompactTouch(at: $0) }
    surface.onMove = { [weak self] in self?.moveCompactTouch(to: $0) }
    surface.onEnd = { [weak self] in self?.endCompactTouch(at: $0, cancelled: $1) }
    return surface
  }()

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemGroupedBackground
    tabBarMinimizeBehavior = .never
    tabBar.accessibilityIdentifier = "stock.tabbar"
    tabBar.accessibilityValue = "expanded"
    delegate = self
    // A sibling control receives touches at the rendered compact positions;
    // they must not fall through to the web view's scrolling recognizers.
    compactTouchSurface.frame = view.bounds
    compactTouchSurface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(compactTouchSurface)
    for item in tabBar.items ?? [] { item.accessibilityLabel = item.title }
    NotificationCenter.default.addObserver(
      self, selector: #selector(accessibilityChanged),
      name: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(accessibilityChanged),
      name: UIContentSizeCategory.didChangeNotification, object: nil)
    selectedIndex = 0
  }

  @objc private func accessibilityChanged() {
    endCompactTouch(at: .zero, cancelled: true)
    setCompact(false)
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    view.bringSubviewToFront(compactTouchSurface)
  }

  func contentDidAppear(_ content: UIViewController) {
    // Rapid tab changes can deliver appearance callbacks out of order.
    guard selectedViewController === content else { return }
    if compactSelectionDestination === content {
      updateItemLayout(animated: false)
    } else if compactTouch == nil {
      setCompact(false)
    }
  }

  // Use the system's laid-out controls, including RTL, rather than dividing
  // the screen into thirds: the floating tab platter is narrower than it.
  func tabTouchFrames(presentation: Bool = false) -> [CGRect] {
    let pivot = tabBar.convert(CGPoint(x: tabBar.bounds.midX, y: tabBar.bounds.midY), to: view)
    let modelScale = tabBar.layer.sublayerTransform.m11
    let visibleScale =
      presentation ? (tabBar.layer.presentation()?.sublayerTransform.m11 ?? modelScale) : modelScale
    let ratio = visibleScale / modelScale
    // Titles are absent in compact layout. Read native control geometry
    // without relying on a label or a private UIKit class name. Liquid Glass
    // can expose two render copies of each button, so deduplicate positions.
    let controls = tabBar.allDescendants.compactMap { $0 as? UIControl }
      .filter { $0.allDescendants.contains(where: { $0 is UIImageView }) }
    var frames: [CGRect] = []
    for target in controls {
      let frame = target.convert(target.bounds, to: view)
      guard !frame.isEmpty, !frames.contains(where: { abs($0.midX - frame.midX) < 1 }) else {
        continue
      }
      frames.append(frame)
    }
    guard frames.count == tabBar.items?.count else { return [] }
    frames.sort {
      tabBar.effectiveUserInterfaceLayoutDirection == .rightToLeft
        ? $0.midX > $1.midX : $0.midX < $1.midX
    }
    return frames.map { frame in
      let center = CGPoint(
        x: pivot.x + (frame.midX - pivot.x) * ratio, y: pivot.y + (frame.midY - pivot.y) * ratio)
      return CGRect(
        x: center.x - frame.width * ratio / 2, y: center.y - frame.height * ratio / 2,
        width: frame.width * ratio, height: frame.height * ratio)
    }
  }

  func acceptsCompactTouch(at point: CGPoint) -> Bool {
    guard isCompact, !tabBar.isHidden else { return false }
    return CompactTabTouch.target(at: point, frames: tabTouchFrames(presentation: true)) != nil
  }

  func beginCompactTouch(at point: CGPoint) {
    guard isCompact else { return }
    let frames = tabTouchFrames(presentation: true)
    guard let index = CompactTabTouch.target(at: point, frames: frames) else { return }
    compactTouch = CompactTabTouch(
      start: point, pressedIndex: index, originalSelection: selectedIndex, initialFrames: frames)
    selectionFeedback.prepare()
    animateBarScale(0.74, duration: 0.12, animated: true)
  }

  func moveCompactTouch(to point: CGPoint) {
    guard var touch = compactTouch else { return }
    let wasSliding = touch.isSliding
    touch.move(to: point)
    compactTouch = touch
    guard touch.isSliding else { return }
    if !wasSliding { setCompact(false) }
    if let index = CompactTabTouch.target(
      at: point, frames: tabTouchFrames(), current: selectedIndex, verticalMargin: 24),
      index != selectedIndex
    {
      selectTab(index, keepingCompact: false)
      selectionFeedback.selectionChanged()
      selectionFeedback.prepare()
    }
  }

  func endCompactTouch(at point: CGPoint, cancelled: Bool = false) {
    guard let touch = compactTouch else { return }
    let target = touch.destination(
      at: point, expandedFrames: tabTouchFrames(), current: selectedIndex, cancelled: cancelled)
    compactTouch = nil
    // Releasing the current tab returns to compact. A different destination
    // expands and navigates in the same touch; no second tap is required.
    setCompact(touch.keepsCompact(afterSelecting: target))
    selectTab(target, keepingCompact: isCompact)
  }

  private func selectTab(_ index: Int, keepingCompact: Bool) {
    guard let controllers = viewControllers, controllers.indices.contains(index) else { return }
    if index != selectedIndex {
      compactSelectionDestination = keepingCompact ? controllers[index] : nil
      selectedIndex = index
    }
    updateTint()
    view.layoutIfNeeded()
    updateItemLayout(animated: false)
  }

  func setCompact(_ compact: Bool, animated: Bool = true) {
    if compact && compactTouch != nil { return }
    let compact =
      compact && traitCollection.userInterfaceIdiom == .phone
      && !UIAccessibility.isVoiceOverRunning
      && !traitCollection.preferredContentSizeCategory.isAccessibilityCategory
    let changed = compact != isCompact
    isCompact = compact
    tabBar.accessibilityValue = compact ? "compact" : "expanded"
    compactSelectionDestination = compact ? selectedViewController : nil
    // Render-only scaling does not change UIKit's hit testing. Disable the
    // hidden full-size targets while our sibling control handles compact tabs.
    tabBar.isUserInteractionEnabled = !compact
    if changed { updateItemLayout(animated: animated) }
    animateBarScale(compact ? 0.68 : 1, duration: compact ? 0.40 : 0.16, animated: animated)
  }

  private func updateItemLayout(animated: Bool) {
    let compact = isCompact
    guard
      (tabBar.items ?? []).contains(where: { $0.title != (compact ? nil : $0.accessibilityLabel) })
    else { return }
    // Let UIKit lay out icon-only items at their true center. Hiding label
    // alpha preserves the label's empty space; transforming UIKit's image
    // views is overwritten by later internal layout passes.
    tabBar.layoutIfNeeded()
    let changes = {
      for item in self.tabBar.items ?? [] { item.title = compact ? nil : item.accessibilityLabel }
      self.tabBar.layoutIfNeeded()
    }
    if animated && !UIAccessibility.isReduceMotionEnabled {
      // Animate layout without snapshotting/crossfading the glass bar.
      UIView.animate(
        withDuration: compact ? 0.40 : 0.16, delay: 0,
        options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction],
        animations: changes)
    } else {
      UIView.performWithoutAnimation(changes)
    }
  }

  private func animateBarScale(_ scale: CGFloat, duration: TimeInterval, animated: Bool) {
    // Scale the rendered contents, keeping UIKit's layout and safe area
    // stable. Scaling the bar's frame makes Liquid Glass grow its height.
    let layer = tabBar.layer
    let previous = layer.presentation()?.sublayerTransform ?? layer.sublayerTransform
    let target = CATransform3DMakeScale(scale, scale, 1)
    guard !CATransform3DEqualToTransform(layer.sublayerTransform, target) else { return }
    layer.removeAnimation(forKey: "mystock.compactScale")
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.sublayerTransform = target
    CATransaction.commit()
    if animated && !UIAccessibility.isReduceMotionEnabled {
      let animation = CABasicAnimation(keyPath: "sublayerTransform")
      animation.fromValue = NSValue(caTransform3D: previous)
      animation.toValue = NSValue(caTransform3D: target)
      animation.duration = duration
      animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      layer.add(animation, forKey: "mystock.compactScale")
    }
  }

  func updateTint() {
    tabBar.tintColor = UIColor(selectedIndex == 1 ? Color.hyxlAccent : Color.brandAccent)
  }

  func tabBarController(
    _ tabBarController: UITabBarController, didSelect viewController: UIViewController
  ) {
    updateTint()
  }

  func tabBarController(
    _ tabBarController: UITabBarController, shouldSelect viewController: UIViewController
  ) -> Bool {
    setCompact(false)
    return true
  }
}

// Hit testing uses the visible compact platter only. Once tracking begins,
// UIKit keeps delivering movement/release even as the bar expands underneath.
private final class CompactTabTouchSurface: UIControl {
  var acceptsTouch: ((CGPoint) -> Bool)?
  var onBegin: ((CGPoint) -> Void)?
  var onMove: ((CGPoint) -> Void)?
  var onEnd: ((CGPoint, Bool) -> Void)?

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    accessibilityElementsHidden = true
    isExclusiveTouch = true
  }

  required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    acceptsTouch?(point) == true
  }

  override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
    onBegin?(touch.location(in: self))
    return true
  }

  override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
    onMove?(touch.location(in: self))
    return true
  }

  override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
    onEnd?(touch?.location(in: self) ?? .zero, touch == nil)
  }

  override func cancelTracking(with event: UIEvent?) {
    onEnd?(.zero, true)
  }
}

extension UIView {
  fileprivate var allDescendants: [UIView] { subviews + subviews.flatMap(\.allDescendants) }
}

struct CompactTabTouch {
  let start: CGPoint
  let pressedIndex: Int
  let originalSelection: Int
  let initialFrames: [CGRect]
  private(set) var isSliding = false

  func keepsCompact(afterSelecting index: Int) -> Bool {
    !isSliding && index == originalSelection
  }

  mutating func move(to point: CGPoint) {
    let dx = abs(point.x - start.x)
    let dy = abs(point.y - start.y)
    if dx >= 12 && dx > dy { isSliding = true }
  }

  func destination(at point: CGPoint, expandedFrames: [CGRect], current: Int, cancelled: Bool)
    -> Int
  {
    guard !cancelled else { return originalSelection }
    if isSliding {
      return Self.target(at: point, frames: expandedFrames, current: current, verticalMargin: 24)
        ?? originalSelection
    }
    return Self.target(at: point, frames: initialFrames) == pressedIndex
      ? pressedIndex : originalSelection
  }

  static func target(
    at point: CGPoint, frames: [CGRect], current: Int? = nil, verticalMargin: CGFloat = 0
  ) -> Int? {
    let valid = frames.indices.filter { !frames[$0].isNull && !frames[$0].isEmpty }
    guard valid.count == frames.count, !valid.isEmpty else { return nil }
    let area = frames.reduce(CGRect.null) { $0.union($1) }
    let padding = max(0, (44 - area.height) / 2) + verticalMargin
    guard area.insetBy(dx: -4, dy: -padding).contains(point) else { return nil }
    let nearest = valid.min { abs(frames[$0].midX - point.x) < abs(frames[$1].midX - point.x) }!
    // Small reversals around a boundary should not repeatedly switch tabs.
    if let current, valid.contains(current), current != nearest,
      abs(frames[current].midX - point.x) - abs(frames[nearest].midX - point.x) < 8
    {
      return current
    }
    return nearest
  }
}
