import SwiftUI

struct MyView: View {
  @Environment(ReportStore.self) private var store
  @AppStorage("appearance") private var appearance: AppAppearance = .system
  @AppStorage("hideAmounts") private var hidden = false
  private var latest: AssetPoint? {
    if let performance=store.envelope.performance?["all"] { return performance.assetPoints(in:store.envelope).last }
    return store.isDemo ? Performance.points(store.envelope, scope:.all).last : nil
  }
  var body: some View {
    Canvas {
      HStack {
        VStack(alignment: .leading, spacing: 5) {
          Text("나의 투자 기록").font(.title3.weight(.medium))
          Text("매일의 기록이 쌓이는 곳").font(.subheadline).foregroundStyle(.secondary)
        }
        Spacer()
        Image(systemName: "leaf").font(.title2).foregroundStyle(Color.brandAccent).padding(16)
          .background(Color.brandAccent.opacity(0.08), in: .circle)
      }
      Surface {
        HStack {
          Text("전체 자산").font(.subheadline).foregroundStyle(.secondary)
          Spacer()
          Pill(text: "KRW")
        }
        Text(Format.money(latest?.assets, "KRW", hidden: hidden)).font(
          .system(.largeTitle, design: .rounded).weight(.semibold)
        ).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
        if let latest {
          Text("\(ReportDate.label(latest.date, format: "M월 d일")) 기준 · 원화 환산").font(.caption)
            .foregroundStyle(.secondary)
          Divider()
          ForEach(latest.constituents) { report in
            HStack {
              Circle().fill(report.investment.tint).frame(width: 7, height: 7)
              Text(report.investment.rawValue).font(.subheadline.weight(.medium))
              Spacer()
              Text(
                Format.money(
                  (report.totalAssets ?? 0) * (report.currency == "USD" ? latest.fx : 1), "KRW",
                  hidden: hidden)
              ).font(.subheadline).monospacedDigit()
            }
          }
          Notice(text: "1 USD = \(Format.money(latest.fx, "KRW")) · 날짜별 기준환율")
          if latest.hasCarriedValuation { Notice(text: "휴장 등으로 각 투자의 최근 정산일이 다릅니다.") }
        } else {
          Notice(text: "두 투자 리포트와 날짜별 환율이 모이면 전체 자산이 표시됩니다.")
        }
      }
      NavigationLink {
        ReportView(initialScope: .all)
      } label: {
        HStack(spacing: 16) {
          Image(systemName: "chart.bar.doc.horizontal").font(.title2).foregroundStyle(
            Color.brandAccent
          ).frame(width: 48, height: 48).background(
            Color.brandAccent.opacity(0.09), in: .rect(cornerRadius: 16))
          VStack(alignment: .leading, spacing: 5) {
            Text("종합리포트").font(.headline)
            Text("투자별 · 월별 수익과 자산 변화").font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(
            .tertiary)
        }.padding(20).background(
          Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
      }.buttonStyle(.plain)
      VStack(spacing: 12) {
        SectionLabel(title: "설정")
        Surface {
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Label("테마", systemImage: appearance.symbol)
              Spacer()
              Text(appearance == .system ? "기기 설정에 맞춤" : appearance.title)
                .font(.caption).foregroundStyle(.secondary)
            }.font(.subheadline)
            Picker("테마", selection: $appearance) {
              ForEach(AppAppearance.allCases) { option in
                Label(option.title, systemImage: option.symbol).tag(option)
              }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("theme.picker")
          }
          Divider()
          NavigationLink {
            SettingsView()
          } label: {
            HStack {
              Label("앱 설정", systemImage: "slider.horizontal.3")
              Spacer()
              Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }.font(.subheadline).foregroundStyle(.primary).padding(.vertical, 4)
          }
        }
      }
      if store.isDemo {
        Notice(text: "현재 샘플 데이터를 보고 있습니다.")
        Button("샘플 종료") { Task { await store.leaveDemo() } }.buttonStyle(.glass)
      }
      if let error = store.error { Notice(text: error) }
      Text("MY STOCK\n나만의 투자 다이어리").font(.caption2).tracking(1.5).lineSpacing(6).foregroundStyle(
        .tertiary
      ).multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, 12)
    }.navigationTitle("My").refreshable { await store.refresh() }
  }
}

struct SettingsView: View {
  @Environment(ReportStore.self) private var store
  @AppStorage("appearance") private var appearance: AppAppearance = .system
  @AppStorage("hideAmounts") private var hidden = false
  @State private var clearConfirmation = false
  var body: some View {
    Form {
      Section("화면") {
        Picker("화면 스타일", selection: $appearance) {
          ForEach(AppAppearance.allCases) { option in
            Label(option.title, systemImage: option.symbol).tag(option)
          }
        }.pickerStyle(.segmented)
        Toggle("금액 숨기기", isOn: $hidden)
      }
      Section("데이터") {
        ForEach(store.envelope.sources) { source in
          VStack(alignment: .leading, spacing: 6) {
            HStack {
              Text(source.investment.rawValue)
              Spacer()
              Text(source.status == "ready" ? "연결됨" : "확인 필요").foregroundStyle(
                source.status == "ready" ? .brandAccent : .orange)
            }
            Text(source.message).font(.caption).foregroundStyle(.secondary)
            if let date = source.lastSyncedAt,
              let parsed = ISO8601DateFormatter().date(
                from: date.replacingOccurrences(
                  of: "\\.\\d+Z$", with: "Z", options: .regularExpression))
            {
              Text("마지막 동기화 \(parsed.formatted(date: .abbreviated, time: .shortened))").font(
                .caption2
              ).foregroundStyle(.tertiary)
            }
          }
        }
        Button("지금 동기화") { Task { await store.refresh() } }.disabled(
          store.isLoading || !store.configured || store.isDemo)
        Button("저장된 리포트 지우기", role: .destructive) { clearConfirmation = true }
      }
      Section("둘러보기") {
        Button("샘플 데이터 보기") { store.showDemo() }
        if store.isDemo { Button("실제 데이터로 돌아가기") { Task { await store.leaveDemo() } } }
      }
      Section {
        LabeledContent("앱 버전", value: "1.0.0")
        Text("개인용 투자 리포트 뷰어").foregroundStyle(.secondary)
      }
    }.modifier(TabBarScrollBehavior()).navigationTitle("앱 설정").navigationBarTitleDisplayMode(
      .inline
    )
    .confirmationDialog(
      "이 기기에 저장된 리포트를 지울까요?", isPresented: $clearConfirmation, titleVisibility: .visible
    ) {
      Button("저장된 리포트 지우기", role: .destructive) { store.clearCache() }
    } message: {
      Text("서버의 원본 기록은 유지되며 다음 동기화 때 다시 가져옵니다.")
    }
  }
}
