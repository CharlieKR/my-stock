import Charts
import SwiftUI

struct ReportView: View {
  @Environment(ReportStore.self) private var store
  @AppStorage("hideAmounts") private var hidden = false
  @State private var scope: ReportScope = .all
  @State private var period: ReportPeriod = .all
  @State private var showMethod = false
  @State private var metric = "수익금"
  @State private var inspectedPoint: AssetPoint?
  init(initialScope: ReportScope) {
    _scope = State(initialValue: initialScope)
  }
  private var fullPerformance: ServerPerformance? { store.envelope.performance?[scope == .all ? "all" : scope.rawValue] }
  private var serverPerformance: ServerPerformance? {
    period == .all ? fullPerformance : fullPerformance?.periods?[period.rawValue]
  }
  private var points: [AssetPoint] {
    if let serverPerformance { return serverPerformance.assetPoints(in:store.envelope) }
    let all=store.isDemo ? Performance.points(store.envelope,scope:scope) : []
    guard let end=all.last?.date,let start=period.start(ending:end) else { return all }
    return all.filter { $0.date >= start }
  }
  private var allMonths: [MonthlyPerformance] {
    if let serverPerformance { return serverPerformance.months.map(\.display) }
    guard store.isDemo,let first=points.first,let last=points.last else { return [] }
    return Performance.monthly(store.envelope,scope:scope).filter { $0.endDate>=first.date && $0.startDate<=last.date }.map { month in
      guard month.startDate<first.date else { return month }
      return MonthlyPerformance(month:month.month,startDate:first.date,endDate:month.endDate,
        startAssets:first.assets,endAssets:month.endAssets,profit:month.endAssets-first.assets,
        returnPercent:first.assets>0 ? (month.endAssets-first.assets)/first.assets*100 : nil,
        cashflow:0,partial:true,estimated:false)
    }
  }
  private var months: [MonthlyPerformance] { allMonths }
  private var inspectedChange: Double? { yearPoints.assetChange(at: inspectedPoint) }
  private var inspectionColor: Color { .movement(inspectedChange) }
  private var inspectedChangeText: String? {
    guard inspectedPoint != nil else { return nil }
    guard let inspectedChange else { return "(이전 기록 없음)" }
    return "(\(Format.money(inspectedChange, scope.currency, signed: true, hidden: hidden)))"
  }
  private var selectedSummary: MonthlyPerformance? {
    if let summary=serverPerformance?.summary { return summary.display }
    guard store.isDemo,let first=points.first,let last=points.last else { return nil }
    return MonthlyPerformance(month:String(first.date.prefix(7)),startDate:first.date,endDate:last.date,
      startAssets:first.assets,endAssets:last.assets,profit:last.assets-first.assets,
      returnPercent:first.assets>0 ? (last.assets-first.assets)/first.assets*100 : nil,
      cashflow:0,partial:false,estimated:false)
  }
  private var yearPoints: [AssetPoint] { points }
  var body: some View {
    Canvas {
      Picker("투자 선택", selection: $scope) {
        ForEach(ReportScope.allCases) { Text($0.rawValue).tag($0) }
      }.pickerStyle(.segmented)
      HStack {
        Text(scope == .all ? "모든 투자를, 하나의 흐름으로" : "\(scope.rawValue)의 투자 흐름").font(.subheadline)
          .foregroundStyle(.secondary)
        Spacer()
        if store.isDemo { Pill(text: "샘플", color: .orange) }
      }
      Picker("조회 기간",selection:$period) {
        ForEach(ReportPeriod.allCases) { Text($0.title).tag($0) }
      }.pickerStyle(.segmented).accessibilityIdentifier("report.period")
      if points.isEmpty {
        Surface {
          ContentUnavailableView(
            "아직 성과 기록이 없어요", systemImage: "chart.xyaxis.line",
            description: Text(
              scope == .all ? "두 투자 리포트와 날짜별 환율이 필요합니다." : "정산된 리포트가 쌓이면 성과를 보여드릴게요."))
        }
      } else {
        if let first = yearPoints.first, let last = yearPoints.last {
          Text("\(ReportDate.label(first.date, format: "yyyy.MM.dd")) – \(ReportDate.label(last.date, format: "yyyy.MM.dd")) · \(points.count)일 기록")
            .font(.caption).foregroundStyle(.secondary)
            .accessibilityIdentifier("report.dateRange")
        }
        Surface {
          HStack {
            Text(inspectedPoint == nil ? "총 자산" : "선택일 자산").font(.subheadline)
              .lineLimit(1).minimumScaleFactor(0.7)
              .foregroundStyle(inspectedPoint == nil ? Color.secondary : inspectionColor)
              .accessibilityIdentifier("report.assetTitle")
            Spacer()
            Pill(text: inspectedPoint == nil ? scope.currency : "조회 중", color:inspectedPoint == nil ? .brandAccent : inspectionColor)
          }
          Text(Format.money((inspectedPoint ?? yearPoints.last)?.assets, scope.currency, hidden: hidden)).font(
            .system(.largeTitle, design: .rounded).weight(.semibold)
          ).monospacedDigit().lineLimit(1).minimumScaleFactor(0.55)
            .foregroundStyle(inspectedPoint == nil ? Color.primary : inspectionColor)
            .accessibilityIdentifier("report.assetAmount")
          if let latest = inspectedPoint ?? yearPoints.last {
            HStack(spacing: 4) {
              Text("\(ReportDate.label(latest.date, format: "yyyy년 M월 d일")) 기준")
              if let inspectedChangeText { Text(inspectedChangeText).foregroundStyle(inspectionColor) }
            }.font(.caption)
              .foregroundStyle(inspectedPoint == nil ? Color.secondary : inspectionColor)
              .lineLimit(1).minimumScaleFactor(0.8)
              .accessibilityIdentifier("report.assetDate")
          }
          if !hidden && yearPoints.count > 1 {
            AssetChart(
              points: yearPoints, currency: scope.currency,
              tint: scope == .hyxl ? .hyxlAccent : .brandAccent, selectedPoint:$inspectedPoint)
          }
          if let month = selectedSummary {
            Divider()
            HStack(spacing: 16) {
              Metric(
                title: "기간 수익금\(month.estimated ? " (추정)" : "")",
                value: Format.money(month.profit, scope.currency, signed: true, hidden: hidden),
                color: .gain(month.profit))
              Metric(
                title: "기간 수익률\(month.estimated ? " (추정)" : "")",
                value: hidden ? "•••" : Format.percent(month.returnPercent),
                color: .gain(month.returnPercent))
            }
            Text("수익 계산 · \(ReportDate.label(month.startDate, format: "yyyy.MM.dd")) – \(ReportDate.label(month.endDate, format: "yyyy.MM.dd"))")
              .font(.caption2).foregroundStyle(.secondary)
            if let reason=month.reason { Notice(text:reason) }
          }
        }
        .overlay {
          RoundedRectangle(cornerRadius:26).strokeBorder(inspectionColor.opacity(inspectedPoint == nil ? 0 : 0.35),lineWidth:1)
            .allowsHitTesting(false)
        }
        if scope == .all, let latest = yearPoints.last {
          Notice(
            text:
              "원화 환산 · 1 USD = \(Format.money(latest.fx, "KRW"))\n각 날짜의 기준환율을 적용하며 환율 변동을 포함합니다.")
          Notice(text: "종합 자산은 먼저 기록된 투자부터 표시합니다. HYXL 기록 이전에는 SOXL만 포함하며, 미기록 자산이 없었다는 뜻은 아닙니다. 각 투자 자산은 첫 기록일부터 합산합니다.")
        }
        if let message = store.envelope.fxMessage, scope == .all { Notice(text: message) }
        if let error = store.error { Notice(text: error) }
        VStack(spacing: 14) {
          HStack {
            Text("월별 성과").font(.headline)
            Spacer()
            Text("\(months.count)개월").font(.caption).foregroundStyle(.secondary)
          }
          Picker("차트 항목", selection: $metric) {
            Text("수익금").tag("수익금")
            Text("수익률").tag("수익률")
            Text("자산 변화").tag("자산 변화")
          }.pickerStyle(.segmented)
          if !hidden { monthlyChart }
          Surface(padding: 0) {
            VStack(spacing: 0) {
              HStack {
                Text("월").frame(width: 42, alignment: .leading)
                Spacer()
                Text("수익금 / 수익률")
                Spacer()
                Text("기말 자산")
              }.font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 18).padding(
                .vertical, 14)
              ForEach(months) { month in
                Divider().padding(.horizontal, 18)
                NavigationLink {
                  MonthDetailView(
                    month: month, scope: scope,
                    points: points.filter { $0.date >= month.startDate && $0.date <= month.endDate }
                  )
                } label: {
                  HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 5) {
                      Text(month.label).font(.subheadline.weight(.semibold))
                      Text(String(month.month.prefix(4))).font(.caption2).foregroundStyle(.secondary)
                      if month.partial {
                        Text("일부 기간").font(.system(size: 9)).foregroundStyle(.orange)
                      }
                    }.frame(width: 48, alignment: .leading)
                    VStack(alignment: .leading, spacing: 5) {
                      Text(Format.money(month.profit, scope.currency, signed: true, hidden: hidden))
                        .font(.subheadline.weight(.medium)).lineLimit(1).minimumScaleFactor(0.65)
                      Text(
                        hidden
                          ? "•••"
                          : Format.percent(month.returnPercent) + (month.estimated ? " 추정" : "")
                      ).font(.caption)
                    }.foregroundStyle(Color.gain(month.profit)).frame(
                      maxWidth: .infinity, alignment: .leading)
                    Text(Format.money(month.endAssets, scope.currency, hidden: hidden)).font(
                      .caption
                    ).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6).foregroundStyle(
                      .primary)
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                      .foregroundStyle(.tertiary)
                  }.padding(.horizontal, 18).padding(.vertical, 18).contentShape(.rect)
                }.buttonStyle(.plain)
              }
            }
          }
        }
        Notice(text: "과거 기록은 누적 손익과 자산으로 원금 변화를 추정합니다. ‘—’는 손익 근거가 부족한 항목이며, 월을 누르면 계산 범위와 사유를 볼 수 있어요.")
        Notice(text: "최근 기록일 기준으로 조회합니다. 월별 내역도 선택한 기간만 포함하며, 수익 계산에는 시작일 직전 정산액을 기준으로 사용합니다.")
      }
    }
    .navigationTitle("종합리포트").navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          showMethod = true
        } label: {
          Image(systemName: "info.circle")
        }.accessibilityLabel("성과 계산 기준")
      }
    }
    .sheet(isPresented: $showMethod) { methodSheet }
    .onChange(of:scope) { _, _ in inspectedPoint = nil }
    .onChange(of:period) { _, _ in inspectedPoint = nil }
    .onChange(of:hidden) { _, _ in inspectedPoint = nil }
    .refreshable { await store.refresh() }
  }
  private var monthlyChart: some View {
    Surface {
      Chart(months.reversed()) { month in
        let value =
          metric == "수익률"
          ? month.returnPercent : metric == "자산 변화" ? month.assetChange : month.profit
        if let value {
          BarMark(x: .value("월", month.month), y: .value(metric, value)).foregroundStyle(
            Color.gain(value).opacity(0.8)
          ).cornerRadius(5)
        }
      }
      .chartXAxis {
        AxisMarks(values: .automatic(desiredCount: 6)) { value in
          AxisValueLabel {
            if let key = value.as(String.self) {
              Text(ReportDate.label(key + "-01", format: "yy.M"))
                .font(.caption2)
            }
          }
        }
      }
      .chartYAxis {
        AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
          AxisGridLine().foregroundStyle(.quaternary)
          AxisValueLabel {
            if let n = value.as(Double.self) {
              Text(
                metric == "수익률" ? String(format: "%.0f%%", n) : Format.compact(n, scope.currency)
              ).font(.caption2)
            }
          }
        }
      }
      .frame(height: 145).accessibilityLabel("월별 \(metric) 차트")
      if months.allSatisfy({ $0.profit == nil }) && metric != "자산 변화" {
        Notice(text: "누적 손익 또는 입출금 기록이 확인되면 수익 차트가 표시됩니다.")
      }
    }
  }
  private var methodSheet: some View {
    NavigationStack {
      List {
        Section("월별 손익") {
          Text(
            "자산 증감에서 순입출금을 제외합니다. 원장이 없는 보관 기록은 ‘자산 − 누적 손익’의 변화로 원금 증감을 추정합니다. 첫 달은 첫 관측일부터 계산하고 일부 기간으로 표시합니다. 결과는 기기에 저장합니다."
          )
        }
        Section("수익률") {
          Text(
            "입출금은 날짜로 가중한 Modified Dietz 방식으로 반영합니다. 과거 복원값은 원금 변화가 처음 관측된 날짜를 사용하므로 실제 입출금 시점과 차이가 있으며 추정 수익금·수익률로 표시합니다."
          )
        }
        Section("전체 · 원화 기준") {
          Text(
            "SOXL은 해당 날짜의 USD/KRW 기준환율로 환산합니다. 먼저 기록된 투자부터 표시하고 다른 투자는 첫 기록일부터 추가합니다. 새로 편입된 자산은 수익에서 제외합니다. 환율 변동은 포함하며, 기록이 시작된 투자의 정산이 7일 넘게 누락되면 합산을 중단합니다."
          )
        }
        Section("데이터가 부족한 달") {
          Text(
            "누적 손익이 누락된 과거 구간은 수익으로 추측하지 않습니다. 누락 이후 연속으로 계산 가능한 구간이 있으면 그 시작일을 명시하고 일부 기간 수익으로 표시합니다. 월말까지 근거가 없으면 수익은 비워두고 자산만 표시합니다."
          )
        }
        Section("환율 출처") {
          Text(store.envelope.fxSource ?? "Frankfurter · 날짜별 기준환율")
          Link("Frankfurter 안내", destination: URL(string: "https://frankfurter.dev/")!)
        }
      }.font(.subheadline).navigationTitle("계산 기준").navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) { Button("완료") { showMethod = false } }
        }
    }
  }
}

struct MonthDetailView: View {
  let month: MonthlyPerformance
  let scope: ReportScope
  let points: [AssetPoint]
  @AppStorage("hideAmounts") private var hidden = false
  @State private var inspectedPoint: AssetPoint?
  private var inspectedChange: Double? { points.assetChange(at: inspectedPoint) }
  private var inspectionColor: Color { .movement(inspectedChange) }
  private var inspectedAssetTitle: String {
    guard let inspectedPoint else { return "마지막 자산" }
    let date = ReportDate.label(inspectedPoint.date, format: "M.d")
    guard let inspectedChange else { return "\(date) 자산 (이전 기록 없음)" }
    return "\(date) 자산 (\(Format.money(inspectedChange, scope.currency, signed: true, hidden: hidden)))"
  }
  var body: some View {
    Canvas {
      Text(
        "\(scope.rawValue) · \(ReportDate.label(month.startDate, format: "M.d")) – \(ReportDate.label(month.endDate, format: "M.d"))"
      ).font(.subheadline).foregroundStyle(.secondary)
      Surface {
        Metric(
          title: "수익금\(month.estimated ? " (추정)" : "")",
          value: Format.money(month.profit, scope.currency, signed: true, hidden: hidden),
          color: .gain(month.profit))
        Divider()
        HStack {
          Metric(
            title: "수익률\(month.estimated ? " (추정)" : "")",
            value: hidden ? "•••" : Format.percent(month.returnPercent),
            color: .gain(month.returnPercent))
          Metric(
            title: "자산 변화",
            value: Format.money(month.assetChange, scope.currency, signed: true, hidden: hidden))
        }
        Divider()
        HStack {
          Metric(
            title: "시작 자산", value: Format.money(month.startAssets, scope.currency, hidden: hidden))
          Metric(
            title: inspectedAssetTitle,
            value: Format.money(inspectedPoint?.assets ?? month.endAssets, scope.currency, hidden: hidden),
            color:inspectedPoint == nil ? .primary : inspectionColor)
            .lineLimit(1).minimumScaleFactor(0.7)
        }
        if !hidden { AssetChart(points: points, currency: scope.currency,
          tint:scope == .hyxl ? .hyxlAccent : .brandAccent, selectedPoint:$inspectedPoint) }
        if month.partial { Notice(text: "월 전체가 아닌 위에 표시한 계산 기간의 결과입니다.") }
        if let reason=month.reason { Notice(text:reason) }
        if month.estimated {
          Notice(
            text:
              "순입출금 \(Format.money(month.cashflow, scope.currency, signed: true, hidden: hidden)) · 날짜 가중 수익률 또는 과거 복원 자료가 포함된 결과입니다."
          )
        }
      }
      .overlay {
        RoundedRectangle(cornerRadius:26).strokeBorder(inspectionColor.opacity(inspectedPoint == nil ? 0 : 0.35),lineWidth:1)
          .allowsHitTesting(false)
      }
      SectionLabel(title: "일별 자산")
      Surface {
        ForEach(points.reversed()) { point in
          HStack {
            VStack(alignment: .leading, spacing: 4) {
              Text(ReportDate.label(point.date, format: "M월 d일 E"))
              if point.hasCarriedValuation {
                Text("일부 투자 최근 정산 기준").font(.caption2).foregroundStyle(.secondary)
              }
            }
            Spacer()
            Text(Format.money(point.assets, scope.currency, hidden: hidden)).monospacedDigit()
          }.font(.subheadline)
        }
      }
    }.navigationTitle(ReportDate.label(month.month + "-01", format: "yyyy년 M월"))
      .navigationBarTitleDisplayMode(.inline)
  }
}
