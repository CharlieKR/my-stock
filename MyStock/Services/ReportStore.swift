import Security
import SwiftUI

enum ConnectionError: LocalizedError {
  case invalidURL, missingKey
  case server(String)
  case invalidData
  var errorDescription: String? {
    switch self {
    case .invalidURL: "HTTPS 서버 주소를 입력해 주세요. 로컬 개발은 localhost를 사용할 수 있습니다."
    case .missingKey: "읽기 전용 연결 키를 입력해 주세요."
    case .server(let message): message
    case .invalidData: "리포트 형식을 확인할 수 없습니다."
    }
  }
}

enum Keychain {
  static let service = "com.charlie.mystock.reader"
  static func read() -> String {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data
    else { return "" }
    return String(data: data, encoding: .utf8) ?? ""
  }
  static func save(_ value: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
    ]
    let attrs: [String: Any] = [
      kSecValueData as String: Data(value.utf8),
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
    if status == errSecItemNotFound {
      let added = SecItemAdd(query.merging(attrs) { _, new in new } as CFDictionary, nil)
      guard added == errSecSuccess else {
        throw ConnectionError.server("연결 키를 안전하게 저장하지 못했습니다. (\(added))")
      }
    } else if status != errSecSuccess {
      throw ConnectionError.server("연결 키를 저장하지 못했습니다.")
    }
  }
}

private struct ReportDiskCache: Codable {
  let serverURL: String
  let checkedAt: Date?
  let envelope: ReportEnvelope
}

@MainActor @Observable final class ReportStore {
  private(set) var envelope: ReportEnvelope = .empty
  private(set) var isLoading = false
  private(set) var isDemo = false
  private(set) var error: String?
  private(set) var lastLoadedAt: Date?
  private(set) var serverURL: String
  var configured: Bool { !serverURL.isEmpty && !Keychain.read().isEmpty }
  private var refreshID = UUID()
  private let cacheURL: URL

  init() {
    serverURL = UserDefaults.standard.string(forKey: "readerServer") ?? ""
    if let bundledURL=Bundle.main.object(forInfoDictionaryKey:"MyStockAPIURL") as? String,
       !bundledURL.isEmpty, !bundledURL.contains("$("), let url=try? Self.validatedURL(bundledURL),url.scheme=="https" {
      serverURL=url.absoluteString
      UserDefaults.standard.set(url.absoluteString,forKey:"readerServer")
    }
    cacheURL = URL.applicationSupportDirectory.appending(path: "report-cache.json")
    if let data = try? Data(contentsOf: cacheURL) {
      if let cache=try? JSONDecoder().decode(ReportDiskCache.self,from:data),
         cache.serverURL==serverURL,cache.envelope.schemaVersion==2 {
        envelope=cache.envelope;lastLoadedAt=cache.checkedAt
      } else if let legacy=try? JSONDecoder().decode(ReportEnvelope.self,from:data),
                [1,2].contains(legacy.schemaVersion) {
        envelope=legacy
      }
    }
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
        UserDefaults.standard.set(false, forKey: "hideAmounts")
        UserDefaults.standard.set(
          ProcessInfo.processInfo.arguments.contains("--dark") ? "dark" : "system",
          forKey: "appearance")
      }
      let env = ProcessInfo.processInfo.environment
      if let url = env["MY_STOCK_SERVER"], let token = env["MY_STOCK_KEY"] {
        if url != serverURL { envelope = .empty }
        serverURL = url
        do { try Keychain.save(token) } catch { self.error = error.localizedDescription }
        UserDefaults.standard.set(url, forKey: "readerServer")
      }
      if ProcessInfo.processInfo.arguments.contains("--demo") { showDemo() }
    #endif
  }

  static func validatedURL(_ value: String) throws -> URL {
    guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
      let host = url.host,
      url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
      url.scheme == "https"
        || (url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host))
    else { throw ConnectionError.invalidURL }
    return url
  }

  private func fetch<T: Decodable>(_ path: String, base: URL, key: String) async throws -> T {
    var request = URLRequest(url: base.appending(path: path))
    request.httpMethod = "GET"
    request.timeoutInterval = 90
    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    request.cachePolicy = .reloadIgnoringLocalCacheData
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw ConnectionError.invalidData }
    guard (200..<300).contains(http.statusCode) else {
      let message = (try? JSONSerialization.jsonObject(with: data) as? [String: String])?["error"]
      throw ConnectionError.server(message ?? "서버 응답을 확인해 주세요. (\(http.statusCode))")
    }
    return try JSONDecoder().decode(T.self, from: data)
  }

  func connect(url: String, key: String) async throws {
    let base = try Self.validatedURL(url)
    let secret = key.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !secret.isEmpty else { throw ConnectionError.missingKey }
    let result: ReportEnvelope = try await fetch("v2/reports", base: base, key: secret)
    guard result.schemaVersion == 2 else { throw ConnectionError.invalidData }
    try Keychain.save(secret)
    refreshID = UUID()
    serverURL = base.absoluteString
    UserDefaults.standard.set(serverURL, forKey: "readerServer")
    isDemo = false
    error = nil
    envelope = result
    lastLoadedAt = .now
    persist(result)
  }

  func refresh() async {
    guard configured, !isLoading, !isDemo else { return }
    let id = refreshID
    isLoading = true
    defer { isLoading = false }
    do {
      var request = URLRequest(url:try Self.validatedURL(serverURL).appending(path:"v2/reports"))
      request.timeoutInterval=30
      request.cachePolicy = .reloadIgnoringLocalCacheData
      request.setValue("Bearer \(Keychain.read())",forHTTPHeaderField:"Authorization")
      if let revision=envelope.revision { request.setValue("\"\(revision)\"",forHTTPHeaderField:"If-None-Match") }
      let (data,response)=try await URLSession.shared.data(for:request)
      guard id == refreshID else { return }
      guard let http=response as? HTTPURLResponse else { throw ConnectionError.invalidData }
      if http.statusCode == 304 { error=nil;lastLoadedAt = .now;persist(envelope);return }
      guard http.statusCode == 200 else { throw ConnectionError.server("서버 응답 오류 (\(http.statusCode))") }
      let result=try JSONDecoder().decode(ReportEnvelope.self,from:data)
      guard result.schemaVersion == 2 else { throw ConnectionError.invalidData }
      envelope = result
      error = nil
      lastLoadedAt = .now
      persist(result)
    } catch {
      if id == refreshID {
        self.error = "동기화하지 못했습니다. 저장된 리포트를 표시합니다. \(error.localizedDescription)"
      }
    }
  }

  func thread(for report: DailyReport) async throws -> ThreadEnvelope {
    if isDemo { return DemoData.thread(report) }
    if let messages=report.messages { return ThreadEnvelope(messages:messages,partial:false) }
    return try await fetch(
      "v2/daily/\(report.investment.rawValue)/\(report.date)", base: Self.validatedURL(serverURL), key: Keychain.read())
  }
  func reports(for investment: Investment) -> [DailyReport] {
    envelope.reports.filter { $0.investment == investment }.sorted { $0.date > $1.date }
  }
  func showDemo() {
    refreshID = UUID()
    envelope = DemoData.envelope
    isDemo = true
    error = nil
  }
  func leaveDemo() async {
    envelope = .empty
    isDemo = false
    await refresh()
  }
  func clearCache() {
    refreshID = UUID()
    envelope = .empty
    try? FileManager.default.removeItem(at: cacheURL)
  }
  private func persist(_ result: ReportEnvelope) {
    do {
      try FileManager.default.createDirectory(
        at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(ReportDiskCache(serverURL:serverURL,checkedAt:lastLoadedAt,envelope:result)).write(
        to: cacheURL, options: [.atomic, .completeFileProtectionUnlessOpen])
      var url=cacheURL
      var values=URLResourceValues(); values.isExcludedFromBackup=true
      try url.setResourceValues(values)
    } catch { self.error = "리포트는 갱신했지만 오프라인 저장에 실패했습니다." }
  }
}
