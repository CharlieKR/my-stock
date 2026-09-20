import Foundation

enum ReportPeriod: String, CaseIterable, Identifiable {
  case week, month, quarter, halfYear, year, all
  var id: Self { self }
  var title: String {
    switch self {
    case .week: "1주"
    case .month: "1개월"
    case .quarter: "3개월"
    case .halfYear: "6개월"
    case .year: "1년"
    case .all: "전체"
    }
  }
  func start(ending end: String) -> String? {
    guard self != .all else { return nil }
    let date=ReportDate.parse(end)
    let component: Calendar.Component = self == .week ? .day : .month
    let amount: Int = switch self {
    case .week: -6
    case .month: -1
    case .quarter: -3
    case .halfYear: -6
    case .year: -12
    case .all: 0
    }
    let start=ReportDate.calendar.date(byAdding:component,value:amount,to:date)!
    return ReportDate.key(self == .week ? start : ReportDate.calendar.date(byAdding:.day,value:1,to:start)!)
  }
}
