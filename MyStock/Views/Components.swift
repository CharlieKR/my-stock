import Charts
import SwiftUI

extension Color {
  static let brandAccent = Color(
    uiColor: UIColor { traits in
      traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.38, green: 0.68, blue: 1.00, alpha: 1)
        : UIColor(red: 0.10, green: 0.42, blue: 0.91, alpha: 1)
    })
  static let inspectionAccent = Color(
    uiColor: UIColor { traits in
      traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.31, green: 0.86, blue: 0.66, alpha: 1)
        : UIColor(red: 0.03, green: 0.55, blue: 0.37, alpha: 1)
    })
  static let hyxlAccent = Color(
    uiColor: UIColor { traits in
      traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.60, green: 0.66, blue: 1.0, alpha: 1)
        : UIColor(red: 0.28, green: 0.36, blue: 0.78, alpha: 1)
    })
  static func gain(_ value: Double?) -> Color {
    guard let value else { return .secondary }
    return value >= 0 ? .brandAccent : .red
  }
  static func movement(_ value: Double?) -> Color {
    guard let value else { return .brandAccent }
    if value > 0 { return .inspectionAccent }
    if value < 0 { return .red }
    return .brandAccent
  }
}
extension Investment { var tint: Color { self == .soxl ? .brandAccent : .hyxlAccent } }

enum Format {
  static func money(
    _ value: Double?, _ currency: String, signed: Bool = false, hidden: Bool = false
  ) -> String {
    if hidden { return "••••••" }
    guard let value, value.isFinite else { return "—" }
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.locale = Locale(identifier: "en_US")
    formatter.minimumFractionDigits = currency == "USD" ? 2 : 0
    formatter.maximumFractionDigits = currency == "USD" ? 2 : 0
    let sign = value < 0 ? "−" : signed && value > 0 ? "+" : ""
    return sign + (currency == "USD" ? "$" : "₩")
      + (formatter.string(from: NSNumber(value: abs(value))) ?? "—")
  }
  static func percent(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "—" }
    return String(format: "%@%.2f%%", value > 0 ? "+" : value < 0 ? "−" : "", abs(value))
  }
  static func compact(_ value: Double, _ currency: String) -> String {
    if currency == "KRW" && abs(value) >= 10000 { return String(format: "%.0f만", value / 10000) }
    if abs(value) >= 1000 { return String(format: "%.0fk", value / 1000) }
    return String(format: "%.0f", value)
  }
}

struct Canvas<Content: View>: View {
  @ViewBuilder var content: Content
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) { content }.padding(.horizontal, 20).padding(
        .top, 12
      ).padding(.bottom, 32).frame(maxWidth: 680).frame(maxWidth: .infinity)
    }
    .background(Color(.systemGroupedBackground))
    .modifier(TabBarScrollBehavior())
  }
}
struct Surface<Content: View>: View {
  var padding: CGFloat = 20
  @ViewBuilder var content: Content
  var body: some View {
    VStack(alignment: .leading, spacing: 18) { content }.frame(
      maxWidth: .infinity, alignment: .leading
    ).padding(padding)
      .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
  }
}
struct SectionLabel: View {
  let title: String
  var subtitle: String? = nil
  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title).font(.headline)
      Spacer()
      if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
    }
  }
}
struct Pill: View {
  let text: String
  var symbol: String? = nil
  var color: Color = .brandAccent
  var body: some View {
    HStack(spacing: 4) {
      if let symbol { Image(systemName: symbol) }
      Text(text)
    }.font(.caption.weight(.medium)).foregroundStyle(color).padding(.horizontal, 10).padding(
      .vertical, 6
    ).background(color.opacity(0.09), in: .capsule)
  }
}
struct Notice: View {
  let text: String
  var symbol: String = "info.circle"
  var body: some View {
    Label(text, systemImage: symbol).font(.footnote).foregroundStyle(.secondary).fixedSize(
      horizontal: false, vertical: true)
  }
}
struct Metric: View {
  let title: String
  let value: String
  var color: Color = .primary
  var detail: String? = nil
  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(title).font(.caption).foregroundStyle(.secondary)
      Text(value).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(color)
        .minimumScaleFactor(0.65).lineLimit(1)
      if let detail {
        Text(detail).font(.caption.weight(.medium)).monospacedDigit().foregroundStyle(color)
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}
struct AssetChart: View {
  let points: [AssetPoint]
  let currency: String
  var tint: Color = .brandAccent
  @Binding var selectedPoint: AssetPoint?
  @State private var selectedDate: Date?
  private var selected: AssetPoint? {
    selectedDate.flatMap { target in
      points.min { abs($0.day.timeIntervalSince(target)) < abs($1.day.timeIntervalSince(target)) }
    }
  }
  private var selectedChange: Double? { points.assetChange(at: selected) }
  private var activeTint: Color {
    selectedDate == nil ? tint : .movement(selectedChange)
  }
  private var domain: ClosedRange<Double> {
    let values = points.map(\.assets)
    let low = values.min() ?? 0
    let high = values.max() ?? 1
    let gap = max((high - low) * 0.24, max(1, high * 0.015))
    return max(0, low - gap)...(high + gap)
  }
  var body: some View {
      Chart {
        ForEach(points) { point in
          AreaMark(
            x: .value("날짜", point.day), yStart: .value("기준", domain.lowerBound),
            yEnd: .value("자산", point.assets)
          )
          .foregroundStyle(
            LinearGradient(
              colors: [activeTint.opacity(0.20), activeTint.opacity(0.01)], startPoint: .top, endPoint: .bottom)
          )
          LineMark(x: .value("날짜", point.day), y: .value("자산", point.assets)).lineStyle(
            StrokeStyle(lineWidth: 2.5, lineCap: .round)
          ).foregroundStyle(activeTint)
        }
        if let selected {
          RuleMark(x: .value("선택", selected.day)).foregroundStyle(activeTint.opacity(0.45))
            .lineStyle(StrokeStyle(lineWidth:1,dash:[4,3]))
          PointMark(x: .value("날짜", selected.day), y: .value("자산", selected.assets))
            .foregroundStyle(activeTint).symbolSize(55)
        }
      }
      .chartYScale(domain: domain)
      .chartXAxis {
        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
          AxisValueLabel(format: .dateTime.month(.defaultDigits).day(), centered: false)
        }
      }
      .chartYAxis {
        AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
          AxisGridLine().foregroundStyle(.quaternary)
          AxisValueLabel {
            if let number = value.as(Double.self) {
              Text(Format.compact(number, currency)).font(.caption2)
            }
          }
        }
      }
      .chartOverlay { proxy in
        GeometryReader { geometry in
          Color.clear.contentShape(.rect)
            .gesture(ChartInspectionGesture { location in
              guard let location, let anchor=proxy.plotFrame else { clearSelection(); return }
              let frame=geometry[anchor]
              let x=min(max(location.x-frame.minX,0),frame.width)
              selectedDate=proxy.value(atX:x,as:Date.self)
            })
        }
      }
      .onChange(of:selectedDate) { _, _ in selectedPoint = selected }
      .onChange(of:points.map(\.id)) { _, _ in clearSelection() }
      .onDisappear { clearSelection() }
      .frame(height: 160)
      .accessibilityLabel("자산 변화 차트")
      .accessibilityIdentifier("asset.chart")
      .accessibilityValue(selected.map {
        let change = selectedChange.map { " (\(Format.money($0,currency,signed:true)))" } ?? ""
        return "\(ReportDate.label($0.date,format:"M월 d일")), \(Format.money($0.assets,currency))\(change)"
      } ?? "최신 자산")
  }
  private func clearSelection() {
    selectedDate = nil
    selectedPoint = nil
  }
}

/// A stationary hold must report its position too, without requiring a drag.
/// UIKit also delivers cancellation when a scroll or system gesture takes over.
private struct ChartInspectionGesture: UIGestureRecognizerRepresentable {
  let onChange: (CGPoint?) -> Void
  func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
    let recognizer=UILongPressGestureRecognizer()
    recognizer.minimumPressDuration=0.25
    return recognizer
  }
  func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
    switch recognizer.state {
    case .began, .changed: onChange(context.converter.localLocation)
    default: onChange(nil)
    }
  }
}
