# kst / lst 적용 가이드와 후속 프롬프트

2026-09-20. 로컬 코드·마이그레이션 구현 및 회귀 검증 완료. **운영 Supabase 마이그레이션, 운영 서버 배포, cron/Slack 전송 설정 변경은 아직 적용하지 않았다.** 로컬 앱/읽기 서버는 v2로 전환했고, 현재 DB 연결 정보가 없으므로 보존한 과거 리포트 187개를 명시적으로 표시한다.

## 구현 범위

추가 UI 반영: 수동 데이터 연결 메뉴는 제거했다. 시뮬레이터는 실행 스크립트로 연결하며 배포 앱의 주소는 `MY_STOCK_API_URL` 빌드 설정으로 고정한다. 기존 Keychain 읽기 키는 유지한다. 운영 HTTPS API와 신규 기기 키 준비는 배포 단계에서 처리한다. 기간 필터 1주/1개월/3개월/6개월/1년/전체의 결과도 서버가 계산해 앱 캐시에 포함한다.

- kst: 기존 정산 스냅샷·주문·체결·포지션·입출금을 읽는 발행 어댑터. 시작/정산 작업 끝에 호출한다.
- lst: 사전 주문 계획과 최종 자산 요약·현금/RP·실체결 대조 근거 저장. 보고서용 추가 조회가 실패하기 전에 원본 관측을 로컬 입력 파일로 보관한다.
- 양쪽: `MY_STOCK_REPORTING_ENABLED=true`일 때만 저장. 기본 off라 기존 배포에 자동 활성화되지 않는다. RPC 저장 실패는 outbox에 남기고 매매 작업으로 예외를 전파하지 않는다. `myStockSync`는 보관된 결과 재발행과 DB 조회만 하며 주문을 실행하지 않는다.
- Slack: `MY_STOCK_SLACK_ENABLED=false`로 공통 전송 계층을 끈다. 기본은 기존 동작이다. 원래 정산 cron·대사·LOC·RP 처리는 유지한다.
- API: 전용 DB 읽기 역할, decimal 기반 서버 월별 계산, 응답 버전/ETag, 소스 장애 시 캐시. 기본 실행 경로는 Slack에 접속하지 않는다.
- 앱: 기본 graphical DatePicker, 지원하지 않는 날짜의 토스트, 서버가 계산한 성과와 상세 내역 디스크 캐시, 오프라인 표시.

초기 물리 스키마는 설계의 여러 세부 테이블을 `reporting.publication_batches`의 버전 있는 JSON에 묶었다. 일별 자산·주문·포지션·현금흐름·계산 근거가 한 번에 저장되어 부분 발행을 피한다. 환율은 `reporting.fx_rates`에 저장한다. 종합/월별 결과는 DB에 저장하지 않는다. 동일 내용 재발행은 중복 제거하고, 변경 및 이전 값으로의 정정도 revision으로 보존한다.

## 적용 순서

### 1. 변경 검토와 DB 준비

각 프로젝트의 `supabase/migrations/20260920120000_add_my_stock_reporting.sql`을 검토한다. 두 파일과 My Stock의 `integrations/reporting.sql`은 동일하다. 기존 다른 미적용 마이그레이션이 섞여 있는지 확인하고 프로젝트 전체를 무조건 push하지 않는다.

운영 환경과 DB 프로젝트가 로컬에서 검토한 대상과 같은지 확인하고 백업/복구 상태를 점검한다. 마이그레이션을 각 프로젝트에 한 번 적용한다. `my_stock_reader`, `my_stock_fx_writer` 역할에는 초기 비밀번호가 없으므로 비밀번호를 안전하게 설정하고 연결 정보를 서버 비밀 환경변수로 저장한다. 비밀값을 문서·PR·로그에 넣지 않는다.

`reporting` 스키마는 Data API 노출 목록에 추가하지 않는다. 공개 스키마의 `my_stock_publish` 함수만 기존 소스 서버의 service-role 자격으로 호출한다. 이 함수는 보고서 데이터만 저장하며 anon/authenticated/reader는 실행할 수 없다. 읽기 API는 서비스 역할 키를 쓰지 않고 전용 PostgreSQL reader로 접근한다.

### 2. 소스 서버 코드 배포와 관측

새 코드 배포 후 소스 서버에 아래 설정을 추가한다. 기존 매매 환경변수·주문 시간·수량 계산은 바꾸지 않는다.

```dotenv
MY_STOCK_REPORTING_ENABLED=true
MY_STOCK_OUTBOX_DIR=/absolute/persistent/private/path/my-stock-outbox
# 첫 검증 동안은 기존 Slack 유지
MY_STOCK_SLACK_ENABLED=true
# 원장 대조가 끝난 시작일만 명시. 모르면 설정하지 않는다.
# MY_STOCK_CASHFLOW_COVERAGE_FROM=YYYY-MM-DD
```

`MY_STOCK_CASHFLOW_COVERAGE_FROM`은 그 날짜 이후 외부입출금이 누락 없이 기록됨을 운영자가 확인한 날짜다. 첫 원장 행 날짜를 그대로 복사하지 않는다. 비워 두면 자산은 표시하고 월별 수익금·수익률은 미확정으로 둔다.

kst는 기존 runner 실행 경로 기준으로 `node dist/jobs/myStockSync.js`를, lst는 프로젝트 루트에서 `npx tsx src/jobs/myStockSync.ts`를 별도 읽기/재시도 작업으로 실행한다. 운영 서버의 중복 실행 방지 방식으로 감싸 5분 간격을 권장한다. 기존 매매 작업 cron은 유지한다. 두 작업은 수동으로 마지막 인자에 `YYYY-MM-DD`를 받을 수 있다.

kst의 날짜 지정 작업은 해당 날짜의 기존 DB 스냅샷으로 백필할 수 있다. HYXL 도입 전 데이터는 제외한다. lst의 날짜 지정 작업은 주문 상태만 조회하며 과거 NAV를 현재 잔고로 생성하지 않는다. lst의 실제 NAV는 정상 일일 정산 또는 보관된 `inputs/*.json`의 재발행으로 들어온다. 성공한 원본 입력은 `.json.saved`로 보관된다.

DB 장애 후 outbox/입력 파일이 비워지는지 확인한다. 미완료 파일이 남으면 해당 조회 작업만 재실행한다. 복구 목적으로 `dailyReport`, `executeOrders`, `rebalanceStart`, `rebalanceSettle`을 다시 실행하지 않는다.

### 3. 읽기 API와 환율 작업

My Stock `gateway/.env.example`을 기준으로 실제 환경파일을 별도 보관하고 `node --env-file=/private/path/reader.env gateway/server.mjs`로 실행한다. 기존 서버의 여유 자원 확인 후 별도 서비스 프로세스와 HTTPS 역방향 프록시를 사용한다. 두 DB URL은 reader 계정이어야 하며 인증서 검증은 켜져 있다. 풀러 주소/계정 형식은 해당 Supabase 연결 화면의 설정을 따른다.

환율 작업은 별도 비밀 환경파일의 `MY_STOCK_FX_DATABASE_URL`로 `node --env-file=/private/path/fx.env gateway/sync-fx.mjs`를 매일 실행한다. 기본은 최근 10일, 날짜 인자를 주면 해당 날짜부터 가져온다. 환율 쓰기 자격을 읽기 API 프로세스에 제공하지 않는다.

`GET /v2/reports`는 현재 규모에 맞춰 전체 기간의 Daily·상세·세 범위의 성과를 한 응답으로 제공한다. 앱의 메모리/디스크 캐시는 같은 revision으로 원자적으로 교체된다. `GET /v2/performance?scope=all|SOXL|HYXL`도 사용할 수 있다. 날짜 범위별 별도 페이지네이션은 아직 필요하지 않아 전체 이력을 반환한다. ETag는 원본 정정·환율·계산 버전·평가일·소스 상태가 바뀌면 변경된다.

기존 로컬 기록 이관은 `node gateway/import-legacy.mjs`로 한 번 수행한다. 파일을 이미 만들었다면 덮어쓰지 않는다. 추가 Slack 호출 없이 `legacy-reports.json`을 읽는다. 보관 기록은 자산에서 누적 손익을 뺀 원금 변화를 이용한 추정 수익을 별도로 표시한다. 이 추정은 DB 원장 완전성 확인을 대신하지 않으며 실제 원장으로 저장하지 않는다. 원장 이관/대조 후 DB 발행값이 같은 날짜의 보관값을 대체한다.

### 4. 검증 후 Slack 전송 종료

양쪽 시장의 정상 주문 계획과 정산 한 주기를 관측해 DB 수치·원래 정산 수치·앱 수치가 일치하는지 확인한다. 실제 체결과 제출 성공이 구분되는지도 확인한다. 이후 `MY_STOCK_SLACK_ENABLED=false`로 바꾼다. Slack 변수 없이 시작/정산에 필요한 설정이 모두 충족되는지 확인하되 검증을 위해 실주문 작업을 수동 실행하지 않는다.

전체 소스 코드에 다른 직접 Slack 전송 경로가 있는지 검색하고, SOXL/HYXL 외 기능에서 해당 토큰을 사용하는 경우 그 용도까지 일괄 제거하지 않는다. 읽기 API의 `MY_STOCK_ENABLE_LEGACY_SLACK`은 설정하지 않는다.

### 5. 롤백

새 발행만 끄려면 `MY_STOCK_REPORTING_ENABLED=false`로 돌린다. Slack 복구가 필요하면 기존 Slack 환경을 유지한 채 `MY_STOCK_SLACK_ENABLED=true`로 바꾼다. 기존 매매 cron·원장은 그대로 유지한다. 추가 스키마를 급히 삭제할 필요는 없으며 앱은 마지막 캐시를 계속 보여 준다. API 오류 때문에 주문을 재실행하지 않는다.

## 검증 결과와 남은 운영 확인

로컬에서 kst 기존 테스트 100개, 새 발행 재시도 테스트, lst `lint`·`test:ops`·`test:dongpa`·새 발행 테스트가 통과했다. My Stock은 Node 테스트(SQL 권한, 중복/정정, 성과, ETag 포함), Swift 모델 테스트, iOS 빌드와 캘린더/리포트/설정 UI 테스트가 통과했다. 내부 시뮬레이터에서 미지원 날짜 토스트도 직접 확인했다.

이 결과는 기존 동작에 대한 회귀 검사이며 실거래 운영 무중단을 보증하는 결과는 아니다. 이번 작업에서는 실제 주문 실행·잔고 대사 재실행·운영 DB 쓰기를 수행하지 않았다. 운영 DB 연결·예약 발행·백업 복구·실제 원장 완전성은 위 순서에서 확인해야 한다.

과거 계좌 간 동일 날짜 출금/입금은 합산 범위에서 순액이 상계된다. 서로 다른 날짜/통화에 걸친 이체는 명시적인 연결과 이동 중 자산 기록이 필요하다. 현재 자동으로 금액·날짜를 보고 이체라고 확정하지 않는다. 미확인 구간은 cashflow coverage를 넓히지 않는다. 시장별 장기 휴장은 현재 최대 7일 이월 한도를 사용하며 해당 한도 밖 종합값은 생성하지 않는다. 과거 환율을 뒤늦게 수집한 평가에는 추정 표시를 붙인다.

## kst 작업에 붙여 넣을 프롬프트

```text
<workspace>/kst에 추가된 My Stock 리포트 연동을 검토하고 운영 반영을 준비해줘.

먼저 <workspace>/my-stock/docs/PROJECT_INTEGRATION_GUIDE.md와 현재 git status/diff를 읽어줘.
새로 추가된 untracked 파일도 포함해서 검토해줘.
이미 구현된 코드를 다시 작성하지 말고, myStockAdapter.ts / myStockReporting.ts / myStockSync.ts,
rebalanceStart.ts / rebalanceSettle.ts / slack.ts 변경과
20260920120000_add_my_stock_reporting.sql을 검토해줘.

매매 판단, 주문 수량·가격·유형, 정산/대사, 기존 cron을 유지해야 해.
MY_STOCK_REPORTING_ENABLED의 기본 off와 저장 실패 시 매매 결과 불변을 확인하고
npm --prefix apps/runner run lint, npm --prefix apps/runner test,
apps/runner에서 node --import tsx --test src/lib/myStockReporting.test.ts를 실행해줘.

실제 Supabase/운영 서버와 마이그레이션 적용 상태를 확인해 정확한 배포 대상과 변경을 정리해줘.
reader 전용 연결, persistent outbox, 읽기 전용 sync 스케줄, 원장 대조 범위를 준비하고
로컬·운영 적용 여부를 구분해 보고해줘. 실제 반영 전에는 배포 내용과 복구 절차를 보여줘.
검증을 위해 실주문 job을 실행하지 말고, 성공적인 DB 발행 관측 전에는 Slack을 끄지 마.
```

## lst 작업에 붙여 넣을 프롬프트

```text
<workspace>/lst에 추가된 My Stock 리포트 연동을 검토하고 운영 반영을 준비해줘.

AGENTS.md와 <workspace>/my-stock/docs/PROJECT_INTEGRATION_GUIDE.md,
현재 git status/diff와 untracked 파일을 먼저 읽어줘. 구현된 myStockAdapter.ts / myStockReporting.ts / myStockSync.ts,
preValidateOrders.ts / dailyReport.ts / slack.ts 변경과
20260920120000_add_my_stock_reporting.sql을 기준으로 작업해줘.

dailyReport의 DB-broker reconciliation, LOC 정산, RP 수익, 종가 저장을 유지해줘.
Slack 전송만 독립적으로 끌 수 있어야 하며 매매 로직과 주문 스케줄은 바꾸지 마.
정산 관측이 reporting DB 조회 전에 로컬에 보존되는지, 실패한 발행을 원본으로 재시도하는지,
현재 잔고를 과거 날짜 잔고로 기록하지 않는지 확인해줘.

npm run lint, npm run test:ops, npm run test:dongpa,
node --import tsx --test src/lib/myStock*.test.ts를 실행해줘.
운영 환경·마이그레이션을 확인하고 reader 역할, outbox, 읽기 전용 sync 스케줄과
SOXL 실제 입출금 원장 대조 범위를 준비해줘. 운영 반영 전 배포 내용·복구 절차를 보여줘.
확인을 위해 executeOrders/dailyReport를 수동 실행하지 말고, 정상 정산 발행 관측 후
Slack 전송 종료를 진행할 수 있게 로컬 완료와 운영 미적용 항목을 구분해서 보고해줘.
```
