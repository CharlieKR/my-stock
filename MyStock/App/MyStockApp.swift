import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
  case system
  case light
  case dark

  var id: Self { self }
  var title: String {
    switch self {
    case .system: "자동"
    case .light: "라이트"
    case .dark: "다크"
    }
  }
  var symbol: String {
    switch self {
    case .system: "circle.lefthalf.filled"
    case .light: "sun.max.fill"
    case .dark: "moon.stars.fill"
    }
  }
  var colorScheme: ColorScheme? {
    switch self {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }
}

@main struct MyStockApp: App {
  @State private var store = ReportStore()
  @AppStorage("appearance") private var appearance: AppAppearance = .system
  var body: some Scene {
    WindowGroup {
      RootView(appearance: appearance).environment(store)
        .preferredColorScheme(appearance.colorScheme)
        .environment(\.locale, Locale(identifier: "ko_KR"))
    }
  }
}

struct RootView: View {
  @Environment(ReportStore.self) private var store
  @Environment(\.scenePhase) private var scenePhase
  let appearance: AppAppearance
  var body: some View {
    NativeTabs(store: store, appearance: appearance).ignoresSafeArea()
      .task { await store.refresh() }
      .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await store.refresh() } }
      }
  }
}
