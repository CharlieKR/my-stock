# 운영 반영 기록 — 2026-09-20

## 배포 구조

- iPhone SwiftUI 앱 → `https://my-stock-blue.vercel.app/v2/*` → 기존 lst/kst Supabase의 전용 `reporting` 스키마.
- 신규 DB 프로젝트는 만들지 않았다. Vercel은 별도 `my-stock` 프로젝트이며 기존 `tide-hyx`, `tide-pro`, AppChart 웹 배포와 분리된다.
- 모든 API는 기기의 Bearer 읽기 키가 필요하다. 로그인 UI는 없으며 최초 개인 설치 때 Keychain에 저장한다. 앱 번들에 DB 자격이나 읽기 키를 넣지 않는다.
- API 서버는 `my_stock_reader` 역할로 보고서만 읽는다. 두 운영 DB에서 매매 테이블 조회/쓰기 권한이 없고 보고서 쓰기도 불가능함을 확인했다. TLS 인증서 검증은 유지한다.

## 반영한 데이터

- 기존 보고서 187개를 각 DB의 `reporting.legacy_reports`로 이관했다. 보관된 실제 관측값이며 샘플 데이터가 아니다. Slack 주소/스레드 ID/정산 원문은 이관에서 제외했다.
- HYXL 최근 정산과 다음 거래일 주문 계획은 실제 kst DB 스냅샷/주문 큐에서 발행했다. SOXL의 주문 상태는 lst DB를 조회한다.
- SOXL 과거 NAV는 당시 보관한 정산값을 유지한다. 현재 잔고로 과거 NAV를 재생성하지 않는다. 다음 정상 정산부터 `dailyReport`의 실제 관측이 DB에 발행된다.
- 주문 기록만 추가되더라도 기존 정산 NAV를 보존한다. 정산 결과의 미체결은 제출 성공과 별도로 표시하며, 부분 체결은 잔여 수량만 미체결로 표시한다.
- 같은 종목·방향·가격·유형·상태의 HYXL 주문은 계좌 이름 없이 수량을 합산해 표시한다. 계획 가격은 기존 HYXL 주문표의 호가 반올림 규칙을 따른다.
- 과거 DB NAV·누적 손익이 보관 리포트와 정확히 일치하면 기존 추정 성과를 유지한다. 새/정정 DB 기록은 입출금 원장이 검증되지 않았을 때 수익을 확정하지 않는다. 누적 손익과 기간 손익은 별도 지표다.

## 소스 서버

기존 Lightsail에 보고서 전용 작업만 추가했다. 기존 매매 cron은 유지했고, 검증을 위해 주문/정산 작업을 수동 재실행하지 않았다.

- kst: `myStockSync.ts`, `myStockAdapter.ts`, `myStockReporting.ts`를 배포했다. 매 5분(1, 6, …분)에 최근 DB 기록과 다음 주문 날짜를 조회한다. 기존 runner 시작/정산 실행 파일은 교체하지 않았다.
- lst: 위 세 파일 및 `preValidateOrders.ts`/`dailyReport.ts`의 보고서 발행 연결을 배포했다. 두 기존 작업은 운영 파일이 커밋 기준과 일치함을 확인한 뒤 백업하고 교체했다. 매 5분(3, 8, …분)에 저장된 입력 재발행과 주문 상태 조회를 한다.
- 발행은 `MY_STOCK_REPORTING_ENABLED=true`; 실패 시 outbox로 재시도한다. 운영 점검에서 대기 outbox는 0개였다.
- 환율은 별도 최소권한 writer 작업을 평일 09:10 KST에 실행한다. 앱 요청은 환율 쓰기를 실행하지 않는다.
- Slack 전송은 유지한다. 앞으로 앱/API가 Slack을 호출할 필요는 없으며, 다음 정상 시장 주기의 발행 확인 후 별도로 종료할 수 있다.

두 DB에 `20260920120000_add_my_stock_reporting`와 `20260920130000_add_legacy_reports`를 적용하고 Supabase migration 이력에 기록했다. 두 번째 SQL은 각 소스 프로젝트의 migrations 폴더에도 복사했다.

## 검증 범위

- 2026-08-18 이후 Slack 스레드 49건을 새로 조회했다. 정산 47건의 자산·현금·주식 평가·누적 손익·수익률·일별 손익을 배포 API와 비교했으며 표시 정밀도 이내에서 일치했다. 나머지는 휴장 및 다음 거래일 계획이다.
- 9월 18일 SOXL 4개 주문과 HYXL 합산 2개 주문의 방향·수량·가격, 제출과 미체결 결과를 대조했다. 9월 21일 HYXL 계획은 자산/정산으로 취급하지 않는다.
- Node 회귀 테스트 32개, Swift 모델 테스트 31개, iOS 실기기 서명 빌드가 통과했다. 날짜 선택·기간 필터·리포트 뒤로가기 버튼·설정 UI 테스트와 그래프 선택 시 위치 유지 테스트도 통과했다. kst 기존 테스트 100개, lst 운영 점검 179개 및 동파 테스트 23개, 양쪽 발행 실패/재시도 테스트가 통과했다.
- 배포 API의 정상 조회, 인증 누락 401, 쓰기 요청 405를 확인했다. iPhone에 설치·실행한 앱 캐시에서 HTTPS API 주소, 보고서 187개, 양쪽 소스 `ready`를 확인했다.
- 일요일 배포이므로 다음 실제 주문/정산 주기의 자동 발행은 아직 관측하지 않았다. 현재 점검은 보관 기록/기존 DB 대조 및 회귀 검증이다.

실제 금액·응답·DB 연결 키·개인 기기 식별자는 Git에 포함하지 않는다. 상세 대조 결과와 배포 로그는 `.local/`에만 보관한다.

## 재설치와 롤백

개인 기기는 잠금을 해제한 상태로 `MY_STOCK_DEVICE`, `MY_STOCK_TEAM`을 지정해 `bash scripts/install-iphone.sh`를 실행한다. 읽기 키 파일은 `.local/reader-token` 또는 `MY_STOCK_READER_TOKEN_FILE`로 지정한다. 개발 서명 설치이며 TestFlight 배포는 아니다.

Vercel 배포는 `vercel.json`을 사용한다. 필수 서버 환경변수는 `MY_STOCK_LST_DATABASE_URL`, `MY_STOCK_KST_DATABASE_URL`, `MY_STOCK_READER_TOKEN`이다. DB 연결은 Supabase session pooler와 reader 역할을 사용한다.

API는 이전 Vercel 배포로 되돌릴 수 있다. 소스 작업을 되돌릴 때는 각 서버 프로젝트의 `.my-stock-backups/20260920-my-stock/`에서 대상 파일과 변경 전 cron을 확인한다. 보고서용 cron 세 줄만 제거하고 lst의 `MY_STOCK_REPORTING_ENABLED=false`로 발행을 중지할 수 있다. 매매 cron 전체를 덮어쓰지 않는다. 추가 보고서 테이블은 삭제할 필요가 없다.
