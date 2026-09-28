import SwiftUI
import UIKit

@MainActor @Observable final class TabBarState {
  var onScroll: ((Bool) -> Void)?
  var onAppear: (() -> Void)?
}

/// UIKit keeps the native Liquid Glass tab bar; SwiftUI owns screen content.
struct NativeTabs: UIViewControllerRepresentable {
  let store: ReportStore
  let appearance: AppAppearance
  @AppStorage("viewer.selectedTab") private var selectedTab = 0
  func makeUIViewController(context: Context) -> StockTabBarController {
    let controller = StockTabBarController()
    controller.overrideUserInterfaceStyle = appearance.interfaceStyle
    controller.loadViewIfNeeded()
    let states = (0..<3).map { _ in TabBarState() }
    let contents: [AnyView] = [
      AnyView(TabRootScreen(investment: .soxl)),
      AnyView(TabRootScreen(investment: .hyxl)),
      AnyView(TabRootScreen(investment: nil)),
    ]
    let names = ["SOXL", "HYXL", "My"]
    let images = [
      orbitTabImage("SO"), orbitTabImage("HY"),
      UIImage(systemName: "person.crop.circle"),
    ]
    controller.viewControllers = contents.enumerated().map { index, content in
      let state = states[index]
      state.onScroll = { [weak controller] compact in
        guard let controller, controller.selectedIndex == index,
          controller.presentedViewController == nil
        else { return }
        controller.setCompact(compact)
      }
      state.onAppear = { [weak controller] in
        guard let controller, controller.selectedIndex == index else { return }
        controller.setCompact(false)
      }
      let host = UIHostingController(
        rootView: content.environment(store).environment(state)
          .environment(\.locale, Locale(identifier: "ko_KR")).tint(
            index == 1 ? Color.hyxlAccent : .brandAccent))
      host.view.backgroundColor = .systemGroupedBackground
      host.tabBarItem = UITabBarItem(
        title: names[index], image: images[index]?.withRenderingMode(.alwaysTemplate), tag: index)
      host.tabBarItem.accessibilityLabel = names[index]
      host.tabBarItem.accessibilityIdentifier = "tab.\(names[index])"
      return host
    }
    controller.selectedIndex = (0..<contents.count).contains(selectedTab) ? selectedTab : 0
    let selection = $selectedTab
    controller.onSelectionChange = { selection.wrappedValue = $0 }
    controller.updateTint()
    return controller
  }
  func updateUIViewController(_ controller: StockTabBarController, context: Context) {
    controller.overrideUserInterfaceStyle = appearance.interfaceStyle
    controller.updateTint()
  }
}

/// Each tab restores its own top-level destination independently.
private struct TabRootScreen: View {
  let investment: Investment?
  @State private var path: [String]
  private var storageKey: String { "viewer.navigation.\(investment?.rawValue ?? "My")" }
  init(investment: Investment?) {
    self.investment = investment
    let saved = UserDefaults.standard.string(forKey: "viewer.navigation.\(investment?.rawValue ?? "My")") ?? ""
    _path = State(initialValue: ["report", "settings"].contains(saved) ? [saved] : [])
  }
  private var initialScope: ReportScope {
    investment == .soxl ? .soxl : investment == .hyxl ? .hyxl : .all
  }
  var body: some View {
    NavigationStack(path: $path) {
      Group {
        if let investment { DailyView(investment: investment) }
        else { MyView() }
      }
      .navigationDestination(for: String.self) { route in
        if route == "settings" { SettingsView() }
        else { ReportView(initialScope: initialScope) }
      }
    }
    .onChange(of: path) { _, value in
      UserDefaults.standard.set(value.last ?? "", forKey: storageKey)
    }
  }
}

private func orbitTabImage(_ text: String) -> UIImage {
  let size = CGSize(width: 28, height: 28)
  let format = UIGraphicsImageRendererFormat()
  format.scale = 3
  let font = UIFont.systemFont(ofSize: 10, weight: .bold)
  let roundedFont = font.fontDescriptor.withDesign(.rounded).map {
    UIFont(descriptor: $0, size: font.pointSize)
  } ?? font
  let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
    let center = CGPoint(x: size.width / 2, y: size.height / 2)
    let radius: CGFloat = 11.8
    // The opening and satellite dot keep the monogram light at tab-bar size.
    let orbit = UIBezierPath(
      arcCenter: center, radius: radius,
      startAngle: -.pi / 4, endAngle: .pi / 14, clockwise: false)
    UIColor.black.setStroke()
    orbit.lineWidth = 1.4
    orbit.lineCapStyle = .round
    orbit.stroke()
    let dotAngle: CGFloat = -.pi / 7
    let dot = CGPoint(
      x: center.x + radius * cos(dotAngle), y: center.y + radius * sin(dotAngle))
    UIColor.black.setFill()
    UIBezierPath(ovalIn: CGRect(x: dot.x - 1.4, y: dot.y - 1.4, width: 2.8, height: 2.8))
      .fill()
    let attributes: [NSAttributedString.Key: Any] = [
      .font: roundedFont,
      .foregroundColor: UIColor.black,
      .kern: -0.5,
    ]
    let measured = (text as NSString).size(withAttributes: attributes)
    let origin = CGPoint(
      x: (size.width - measured.width) / 2,
      y: (size.height - measured.height) / 2 - 0.25)
    (text as NSString).draw(at: origin, withAttributes: attributes)
  }
  return image.withRenderingMode(.alwaysTemplate)
}

private extension AppAppearance {
  var interfaceStyle: UIUserInterfaceStyle {
    switch self {
    case .system: .unspecified
    case .light: .light
    case .dark: .dark
    }
  }
}

private struct ScrollSample: Equatable {
  let offset: CGFloat
  let maximum: CGFloat
  let contentHeight: CGFloat
  let viewportHeight: CGFloat
}

struct TabBarScrollBehavior: ViewModifier {
  var resetOnAppear = true
  @Environment(TabBarState.self) private var tabs
  @State private var tracker = TabBarScrollTracker()
  @State private var interacting = false
  func body(content: Content) -> some View {
    content
      .onScrollPhaseChange { _, phase in interacting = phase == .interacting }
      .onScrollGeometryChange(for: ScrollSample.self) { geometry in
        ScrollSample(
          offset: geometry.contentOffset.y + geometry.contentInsets.top,
          maximum: geometry.contentSize.height - geometry.containerSize.height
            + geometry.contentInsets.top + geometry.contentInsets.bottom,
          contentHeight: geometry.contentSize.height, viewportHeight: geometry.containerSize.height)
      } action: { old, new in
        guard old.contentHeight == new.contentHeight, old.viewportHeight == new.viewportHeight
        else {
          tracker = TabBarScrollTracker()
          return
        }
        if let compact = tracker.update(
          from: old.offset, to: new.offset, maximum: new.maximum, userScrolling: interacting)
        {
          tabs.onScroll?(compact)
        }
      }
      .onAppear {
        tracker = TabBarScrollTracker()
        if resetOnAppear { tabs.onAppear?() }
      }
  }
}
