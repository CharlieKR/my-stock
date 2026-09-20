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
  func makeUIViewController(context: Context) -> StockTabBarController {
    let controller = StockTabBarController()
    controller.overrideUserInterfaceStyle = appearance.interfaceStyle
    controller.loadViewIfNeeded()
    let states = (0..<3).map { _ in TabBarState() }
    let contents: [AnyView] = [
      AnyView(NavigationStack { DailyView(investment: .soxl) }),
      AnyView(NavigationStack { DailyView(investment: .hyxl) }),
      AnyView(NavigationStack { MyView() }),
    ]
    let names = ["SOXL", "HYXL", "My"]
    let images = [
      UIImage(named: "SOXLTab"), UIImage(named: "HYXLTab"),
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
    controller.updateTint()
    return controller
  }
  func updateUIViewController(_ controller: StockTabBarController, context: Context) {
    controller.overrideUserInterfaceStyle = appearance.interfaceStyle
    controller.updateTint()
  }
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
        tabs.onAppear?()
      }
  }
}
