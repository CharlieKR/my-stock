import SwiftUI
import UIKit

struct DailyView: View {
  let investment: Investment
  @Environment(ReportStore.self) private var store
  @AppStorage("hideAmounts") private var hidden = false
  @State private var selectedDate: String?
  @State private var showDates = false
  @State private var calendarDate = Date()
  @State private var toast: String?
  private var reports: [DailyReport] { store.reports(for: investment) }
  private var report: DailyReport? {
    if let selectedDate { return reports.first { $0.date == selectedDate } }
    return reports.first { $0.isValued } ?? reports.first
  }
  var body: some View {
    Canvas {
      HStack {
        Text(investment.subtitle).font(.subheadline).foregroundStyle(.secondary)
        Spacer()
        if store.isDemo {
          Pill(text: "샘플", color: .orange)
        } else {
          Label("DAILY", systemImage: "circle.fill").font(
            .system(size: 10, weight: .semibold, design: .rounded)
          ).tracking(1.3).foregroundStyle(investment.tint)
        }
      }
      if let error = store.error { Notice(text: error, symbol: "wifi.exclamationmark") }
      if let source = store.envelope.sources.first(where: { $0.investment == investment }),
        source.status != "ready"
      {
        Notice(text: source.message, symbol: "exclamationmark.circle")
      }
      if let report {
        datePicker(report)
        if report.isValued {
          assetCard(report)
        } else {
          Surface {
            ContentUnavailableView(
              report.statusTitle, systemImage: report.status == "closed" ? "moon.zzz" : "clock",
              description: Text(
                report.status == "closed"
                  ? "이 날은 시장이 쉬어갑니다." : "주문 정보를 먼저 확인할 수 있어요.\n정산이 끝나면 자산과 손익이 표시됩니다."))
          }
        }
        if !report.details.isEmpty {
          VStack(spacing: 12) {
            SectionLabel(title: "오늘의 요약", subtitle: report.statusTitle)
            Surface {
              ForEach(
                Array(report.details.filter { !["오늘", "체결"].contains($0.title) }.enumerated()),
                id: \.element.id
              ) { index, detail in
                if index > 0 { Divider() }
                HStack(alignment: .top, spacing: 14) {
                  Image(
                    systemName: detail.title == "Tail"
                      ? "arrow.triangle.branch"
                      : detail.title == "RP" || detail.title == "CMA"
                        ? "banknote" : "text.alignleft"
                  )
                  .font(.body).foregroundStyle(investment.tint).frame(width: 24)
                  VStack(alignment: .leading, spacing: 5) {
                    Text(detail.title).font(.subheadline.weight(.semibold))
                    Text(hidden ? "금액 숨김" : detail.text).font(.subheadline).foregroundStyle(
                      .secondary
                    ).fixedSize(horizontal: false, vertical: true)
                  }
                }
              }
              if let fills = report.details.first(where: { $0.title == "체결" }) {
                HStack {
                  Label("체결", systemImage: "checkmark.circle").font(.subheadline)
                  Spacer()
                  Text(hidden ? "숨김" : fills.text).font(.subheadline).foregroundStyle(.secondary)
                }
              }
            }
          }
        }
        ThreadSection(report: report)
        NavigationLink {
          ReportView(initialScope: investment == .soxl ? .soxl : .hyxl)
        } label: {
          HStack {
            Label("월별 성과 보기", systemImage: "chart.bar.doc.horizontal").font(
              .subheadline.weight(.medium))
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
          }.padding(20).background(investment.tint.opacity(0.07), in: .rect(cornerRadius: 22))
        }
        Notice(text: "\(investment.timezone) · 아래로 당겨 새로고침")
      } else if store.isLoading {
        ProgressView("리포트를 불러오는 중").frame(maxWidth: .infinity).padding(.vertical, 100)
      } else {
        Surface {
          ContentUnavailableView(
            "하루의 투자를 한눈에", systemImage: investment.symbol,
            description: Text("주문부터 정산까지,\n투자 기록을 모아보세요."))
          Text(store.configured ? "아래로 당겨 다시 불러올 수 있어요." : "리포트 서비스 연결을 준비하고 있습니다.")
            .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth:.infinity)
          Button("샘플로 둘러보기") { store.showDemo() }.font(.subheadline).frame(maxWidth: .infinity)
            .padding(.bottom, 12)
        }
      }
    }
    .navigationTitle(investment.rawValue)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          calendarDate = report?.day ?? Date()
          showDates = true
        } label: {
          Image(systemName: "calendar")
        }.accessibilityLabel("리포트 날짜 선택").disabled(reports.isEmpty)
      }
    }
    .refreshable { await store.refresh() }
    .sheet(isPresented: $showDates) { datesSheet }
    .overlay(alignment:.top) {
      if let toast {
        Label(toast,systemImage:"calendar.badge.exclamationmark")
          .font(.subheadline).padding(.horizontal,18).padding(.vertical,14)
          .glassEffect(.regular,in:.capsule).padding(.top,8)
          .accessibilityIdentifier("daily.noDataToast")
          .allowsHitTesting(false)
      }
    }
    .task(id:toast) {
      guard toast != nil else { return }
      do { try await Task.sleep(for:.seconds(3));toast=nil } catch { }
    }
  }

  private func datePicker(_ report: DailyReport) -> some View {
    HStack(spacing: 6) {
      Button {
        moveDate(-1)
      } label: {
        Image(systemName: "chevron.left").frame(width: 44, height: 44)
      }.disabled(!canMove(-1)).accessibilityLabel("이전 리포트")
      Spacer(minLength: 0)
      Button {
        calendarDate = report.day
        showDates = true
      } label: {
        VStack(spacing: 3) {
          Text(ReportDate.label(report.date)).font(.subheadline.weight(.semibold))
          Text(
            report.date == reports.first(where: { $0.isValued })?.date
              ? "최근 정산일" : String(report.date.prefix(4))
          ).font(.caption2).foregroundStyle(.secondary)
        }.padding(.vertical, 8)
      }.foregroundStyle(.primary)
      Spacer(minLength: 0)
      Button {
        moveDate(1)
      } label: {
        Image(systemName: "chevron.right").frame(width: 44, height: 44)
      }.disabled(!canMove(1)).accessibilityLabel("다음 리포트")
    }
    .padding(.horizontal, 4).glassEffect(.regular, in: .capsule)
  }
  private func canMove(_ direction: Int) -> Bool {
    guard let report, let index = reports.firstIndex(where: { $0.id == report.id }) else {
      return false
    }
    return reports.indices.contains(index - direction)
  }
  private func moveDate(_ direction: Int) {
    guard let report, let index = reports.firstIndex(where: { $0.id == report.id }),
      reports.indices.contains(index - direction)
    else { return }
    selectedDate = reports[index - direction].date
  }
  private var datesSheet: some View {
    NavigationStack {
      VStack {
        DatePicker("리포트 날짜",selection:$calendarDate,displayedComponents:[.date])
          .datePickerStyle(.graphical)
          .environment(\.timeZone,TimeZone(secondsFromGMT:0)!)
          .environment(\.calendar,ReportDate.calendar)
          .environment(\.locale,Locale(identifier:"ko_KR"))
          .tint(investment.tint).padding()
          .accessibilityIdentifier("daily.calendar")
        Spacer(minLength:0)
      }.navigationTitle("리포트 날짜").navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement:.cancellationAction) { Button("취소") { showDates=false } }
          ToolbarItem(placement: .confirmationAction) {
            Button("선택") {
              let date=ReportDate.key(calendarDate)
              showDates=false
              if reports.contains(where:{$0.date==date}) { selectedDate=date;toast=nil }
              else {
                let message="\(ReportDate.label(date,format:"M월 d일")) 데이터가 없습니다."
                toast=message
                UIAccessibility.post(notification:.announcement,argument:message)
              }
            }.accessibilityIdentifier("daily.confirmDate")
          }
        }
    }.presentationDetents([.height(480), .large])
  }
  private func assetCard(_ report: DailyReport) -> some View {
    Surface {
      HStack {
        Text("총 자산").font(.subheadline).foregroundStyle(.secondary)
        Spacer()
        Pill(text: report.currency, color: investment.tint)
      }
      VStack(alignment: .leading, spacing: 9) {
        Text(Format.money(report.totalAssets, report.currency, hidden: hidden)).font(
          .system(.largeTitle, design: .rounded).weight(.semibold)
        ).monospacedDigit().lineLimit(1).minimumScaleFactor(0.55)
        HStack(spacing: 7) {
          Image(
            systemName: (report.cumulativePnl ?? 0) >= 0 ? "arrow.up.right" : "arrow.down.right")
          Text(Format.money(report.cumulativePnl, report.currency, signed: true, hidden: hidden))
          Text("(\(hidden ? "•••" : Format.percent(report.cumulativeReturn)))")
        }.font(.subheadline.weight(.medium)).foregroundStyle(Color.gain(report.cumulativePnl))
        Text("누적 손익").font(.caption).foregroundStyle(.secondary)
      }
      Divider()
      HStack(spacing: 16) {
        Metric(
          title: "오늘 손익",
          value: Format.money(report.dailyPnl, report.currency, signed: true, hidden: hidden),
          color: .gain(report.dailyPnl))
        Metric(title: "현금", value: Format.money(report.cash, report.currency, hidden: hidden))
      }
      if let total = report.totalAssets, let stock = report.stockValue, total > 0 {
        VStack(spacing: 8) {
          GeometryReader { geo in
            Capsule().fill(investment.tint.opacity(0.09))
            Capsule().fill(investment.tint.opacity(0.75)).frame(
              width: geo.size.width * min(1, max(0, stock / total)))
          }.frame(height: 5).accessibilityHidden(true)
          HStack {
            Text("주식 \(stock / total * 100, specifier: "%.1f")%")
            Spacer()
            Text("현금 \((1 - stock / total) * 100, specifier: "%.1f")%")
          }.font(.caption2).foregroundStyle(.secondary).monospacedDigit()
        }
      }
    }
  }
}

struct ThreadSection: View {
  let report: DailyReport
  @Environment(ReportStore.self) private var store
  @AppStorage("hideAmounts") private var hidden = false
  @State private var thread: ThreadEnvelope?
  @State private var error: String?
  @State private var loading = false
  @State private var activeID = ""
  var body: some View {
    VStack(spacing: 12) {
      SectionLabel(title: "주문과 리포트", subtitle: "시간순 기록")
      if hidden {
        Surface { Notice(text: "금액 숨김을 끄면 주문과 상세 리포트를 볼 수 있어요.", symbol: "eye.slash") }
      } else {
        if loading { ProgressView().padding() }
        if let error {
          Surface {
            Notice(text: error)
            Button("다시 불러오기") { Task { await load() } }.font(.subheadline)
          }
        }
        if let thread {
          if thread.partial { Notice(text: "스레드가 길어 일부 메시지만 표시됩니다. Slack에서 전체를 볼 수 있습니다.") }
          if thread.messages.isEmpty {
            Surface { Notice(text: "아직 상세 리포트가 없습니다.", symbol: "tray") }
          }
          ForEach(thread.messages) { message in
            Surface(padding: 18) {
              DisclosureGroup {
                if !message.orderPreviews.isEmpty {
                  VStack(spacing: 16) {
                    ForEach(message.orderPreviews) { order in
                      HStack(alignment: .top, spacing: 10) {
                        Pill(text: order.side, color: order.side == "매수" ? .hyxlAccent : .red)
                        VStack(alignment: .leading, spacing: 5) {
                          Text(order.name).font(.subheadline.weight(.semibold))
                          Text("\(order.quantity)주 × \(order.price)").font(.caption)
                            .foregroundStyle(.secondary)
                          if !order.type.isEmpty {
                            Text(order.type).font(.caption2).foregroundStyle(.tertiary)
                          }
                        }
                        Spacer(minLength: 2)
                        Text(order.amount).font(.subheadline.weight(.medium)).monospacedDigit()
                          .lineLimit(1).minimumScaleFactor(0.6)
                      }
                    }
                    DisclosureGroup("상세 원문") { messageText(message) }.font(.caption).tint(
                      .secondary)
                  }.padding(.top, 14)
                } else {
                  messageText(message)
                }
              } label: {
                HStack(spacing: 12) {
                  Image(systemName: message.symbol).foregroundStyle(report.investment.tint).frame(
                    width: 24)
                  Text(message.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                }.padding(.vertical, 4)
              }
            }
          }
        }
        if report.hasLegacySettlementSource {
          Surface(padding: 18) {
            DisclosureGroup {
              Text(ThreadMessage.clean(report.rawText)).font(.subheadline).lineSpacing(6)
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(
                  .top, 12)
            } label: {
              Label("정산 요약 원문", systemImage: "doc.plaintext").font(.subheadline).foregroundStyle(
                .primary)
            }
          }
        }
        if let url = URL(string: report.slackURL), !report.slackURL.isEmpty {
          Link(destination: url) {
            Label("Slack에서 보기", systemImage: "arrow.up.right.square").font(.footnote)
          }.frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 4)
        }
      }
    }
    .task(id: report.id + report.updatedAt) { await load() }
  }
  private func load() async {
    let id = report.id
    activeID = id
    loading = true
    error = nil
    thread = nil
    do {
      let result = try await store.thread(for: report)
      guard activeID == id, !Task.isCancelled else { return }
      thread = result
    } catch {
      if activeID == id && !Task.isCancelled {
        self.error = "상세 메시지를 불러오지 못했습니다. \(error.localizedDescription)"
      }
    }
    if activeID == id { loading = false }
  }
  private func messageText(_ message: ThreadMessage) -> some View {
    Text(message.body).font(.subheadline).lineSpacing(6).textSelection(.enabled).frame(
      maxWidth: .infinity, alignment: .leading
    ).padding(.top, 12)
  }
}
