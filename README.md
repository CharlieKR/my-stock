# My Stock

SOXL(lst) · HYXL(하이닉스, kst)의 주문·정산과 월별 성과를 보는 개인용 iOS 앱입니다. Supabase 원본 → 읽기 API의 성과 계산 → 앱 디스크 캐시 구조입니다. SwiftUI와 네이티브 Liquid Glass 탭바를 사용합니다. iOS 26 이상, Xcode 26 이상, Node.js 20 이상이 필요합니다.

운영 DB/서버 반영은 [프로젝트별 적용 가이드와 프롬프트](docs/PROJECT_INTEGRATION_GUIDE.md)를 따릅니다. 로컬 구현과 운영 반영은 구분합니다.

## 화면

- **SOXL / HYXL**: Apple 기본 캘린더, 미지원 날짜 토스트, 자산·누적/일별 손익·현금 비중, 주문 계획·주문 상태·체결·정산 근거. 날짜에 기록이 없으면 기존 리포트를 유지합니다.
- **My**: 원화 환산 전체 자산과 전체·SOXL·HYXL 각각의 수익금·수익률을 함께 표시합니다. 종합리포트에서는 전체/투자별 선택, 1주·1개월·3개월·6개월·1년·전체 필터와 선택 기간의 수익금·수익률·자산 변화를 제공합니다.
- **설정**: 시스템/라이트/다크, 금액 숨김, 동기화 상태, 로컬 캐시 삭제, 명시적인 샘플 모드. 서버 주소/키 입력 메뉴는 없습니다.

## 실행

1. MyStock.xcodeproj를 열고 MyStock scheme을 선택합니다.
2. 아래 명령으로 읽기 서버를 실행합니다. 실제 DB 연결은 gateway/.env.example을 참고해 별도 환경파일을 --env-file로 전달합니다.
3. 시뮬레이터는 scripts/run-simulator.sh가 개발용 주소와 읽기 키를 자동 설정합니다. 앱에서 직접 입력하지 않습니다.

~~~sh
npm ci --prefix gateway
node gateway/server.mjs
# 별도 환경파일을 쓸 경우:
node --env-file=/private/path/reader.env gateway/server.mjs
~~~

기본 서버 주소는 http://127.0.0.1:8787입니다. 실기기는 개인 HTTPS 주소가 필요합니다. 연결 키는 Keychain에 저장하며 DB·증권사 비밀 키는 앱에 포함하지 않습니다.

배포용 앱의 API 주소는 Xcode 빌드 설정 MY_STOCK_API_URL에 HTTPS 주소를 지정해 고정합니다. 주소는 비밀이 아니며 Info.plist의 MyStockAPIURL로 전달됩니다. 기기의 읽기 키는 설치/초기 설정 때 Keychain에 준비해야 합니다. 이미 설치된 개인용 앱은 기존 Keychain 키를 유지합니다. 새 기기의 초기 키 설정은 배포 준비 항목이며 키를 없애거나 비인증 DB 조회로 대체하지 않습니다. 운영 API 배포 전에는 개발용 로컬 서버를 계속 사용합니다.

시뮬레이터 설치·연결은 bash scripts/run-simulator.sh로 실행할 수 있습니다. Codex 내부 시뮬레이터는 기존 serve-sim 화면을 이용합니다.

## 데이터와 캐시

- MY_STOCK_LST_DATABASE_URL / MY_STOCK_KST_DATABASE_URL: 전용 my_stock_reader의 PostgreSQL 연결. reporting 스키마만 읽습니다.
- MY_STOCK_READER_TOKEN: 앱 연결 키. MY_STOCK_DATA_DIR: 서버 캐시 위치.
- GET /v2/reports: 전체 기간의 Daily·상세·환율·세 투자 범위 성과·소스 상태.
- GET /v2/performance?scope=all|SOXL|HYXL: 서버가 계산한 월별·일별 성과.
- GET /v2/daily/{SOXL|HYXL}/{YYYY-MM-DD}: 날짜별 주문·정산 상세.
- GET /v2/health: 소스별 연결 상태와 마지막 관측 시각.
- 모든 요청은 Bearer 연결 키가 필요하고 GET 외 메서드는 거절합니다.

앱은 저장된 결과를 먼저 표시하고 ETag로 변경 여부를 확인합니다. 원장 정정·환율·계산 버전이 바뀌면 전체 응답을 원자적으로 갱신합니다. 성과 금액은 서버에서 decimal로 계산하고 문자열로 전달하며, 앱 디스크에는 Decimal 값이 유지됩니다. 차트/표시 모델에서 Double로 변환합니다.

기간 필터는 각 투자 범위의 마지막 기록일을 끝으로 하는 이동 기간입니다. 1주는 달력 7일, 개월/연도는 달력 기준입니다. 서버가 각 기간의 수익과 해당 기간에 포함된 월별 내역을 계산해 함께 내려줍니다. 전체 월의 수익을 1주 수익으로 표시하지 않습니다. 필터 결과도 같은 디스크 캐시에 보관하므로 오프라인 전환이 가능합니다.

자산 그래프를 길게 누르면 기존 총자산 영역이 선택 날짜의 자산·날짜와 직전 기록 대비 증감액으로 바뀝니다. 선택 중에는 증감액을 괄호로 표시하고 금액·그래프·포인트·카드 테두리를 상승 시 초록색, 하락 시 빨간색으로 표시합니다. 손을 떼거나 제스처가 취소되면 블루 기본 상태와 최신 총자산으로 복귀합니다. 선택값을 별도 행으로 삽입하지 않아 그래프 위치와 높이는 유지됩니다. 월별 상세에서는 마지막 자산 영역을 같은 방식으로 사용합니다.

DB 미연결 또는 장애는 화면에 명시합니다. 기존 기록은 node gateway/import-legacy.mjs로 한 번 보존할 수 있습니다. Slack에 접속하지 않고 .local/reports.json을 legacy-reports.json으로 복사하며 기존 보관 파일은 덮어쓰지 않습니다. 앱은 보관 원문 대신 주문표·제출·체결 상태만 카드로 표시합니다. 새 DB 기록이 같은 날짜의 보관 기록을 대체합니다.

Slack 종료 전 과거 주문 스레드를 보관 파일에 한 번 채우려면 아래처럼 실행합니다. 이 명령만 Slack을 읽으며 원문 대신 주문 단계만 정규화해 `.local/legacy-reports.json`에 저장합니다.

~~~sh
npm --prefix gateway run import-orders -- --from=2026-08-18 --to=2026-09-18
~~~

기본 실행 경로는 Slack을 호출하지 않습니다. 기존 /v1 경로는 캐시 호환용이며 Slack 수집은 MY_STOCK_ENABLE_LEGACY_SLACK=true를 명시한 경우에만 동작합니다. 과거 수집 도구 gateway/sync.mjs는 전환 자료로 남겨 두었습니다.

## 성과 계산

월 수익금 = 기말 자산 − 기초 자산 − 순입출금입니다. DB 발행 기록은 원장의 완전성이 확인된 범위만 계산합니다. 원장이 없는 보관 기록(`legacy_archive`)은 자산에서 누적 손익을 뺀 원금의 변화로 입출금을 추정하며 수익금과 수익률에 추정 표시를 합니다. 추정 입출금 날짜는 변화가 처음 관측된 날이며 실제 날짜와 다를 수 있습니다.

입출금은 날짜 가중 Modified Dietz 방식으로 반영합니다. 첫 관측월·진행 중인 달은 일부 기간으로 표시합니다. 누적 손익이 누락된 보관 구간이 있으면 마지막 누락 이후 계산 가능한 구간으로 수익 계산을 한정하고 시작일과 사유를 표시합니다. 계산 가능한 두 관측점이 없으면 수익은 비워둡니다.

SOXL은 USD, HYXL은 KRW, 전체는 일별 USD/KRW 기준환율을 적용합니다. 전체 자산은 먼저 기록된 투자부터 보여주며 아직 기록이 시작되지 않은 투자 자산을 0으로 확정하지 않습니다. 다른 투자가 처음 편입될 때의 관측 자산은 수익으로 세지 않습니다. 전체 수익에는 환율 변동이 포함됩니다. 이미 기록이 시작된 투자나 환율이 7일 넘게 오래되면 해당 합산값을 만들지 않습니다.

환율은 별도 작업 node gateway/sync-fx.mjs로 수집합니다. MY_STOCK_FX_DATABASE_URL은 my_stock_fx_writer 계정이며 읽기 서버와 분리합니다. [Frankfurter](https://frankfurter.dev/) 기준환율은 실제 환전 체결환율과 다릅니다.

## 탭바와 아이콘

appchart의 하단 탭바 동작을 참고했습니다. 아래로 직접 18pt 스크롤하면 세 아이콘을 유지하며 68%로 축소하고 위로 10pt 스크롤하면 복원합니다. 접근성 큰 글씨·VoiceOver·iPad에서는 축소하지 않습니다.

아이콘 원본과 사용 방식은 [아이콘 디자인](docs/design/ICONS.md)에 있습니다. My 및 공통 컨트롤은 SF Symbols를 사용합니다.

## 검증

~~~sh
swift test
node --test gateway/test/*.test.mjs
xcodebuild -project MyStock.xcodeproj -scheme MyStock \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGN_IDENTITY=- test
~~~

SQL 권한/멱등성 테스트는 PGlite의 로컬 PostgreSQL에서 실행하며 운영 DB에는 쓰지 않습니다. 시뮬레이터도 Keychain을 쓰므로 서명을 끄지 않습니다. 프로젝트 재생성은 ruby scripts/generate-project.rb로 수행합니다.

.local, 실제 리포트, 토큰, 스크린샷은 git에서 제외합니다. 번들 샘플은 가상의 데이터입니다.
