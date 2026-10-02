# 실제 체결 방식 — 2026-10-01

`myStockFillTypes.ts`와 테스트를 lst `src/lib/`에 복사하고 `dailyReport-fill-types.patch`의 변경을 `src/jobs/dailyReport.ts`에 반영한다. 현재 로컬 lst와 운영 Lightsail에는 반영되어 있다. 기존 lst 작업 트리에 있던 다른 변경은 커밋하거나 덮어쓰지 않았다.

LS에서 이미 읽은 체결 행의 `OrdprcPtnCode`를 reporting 메타데이터로 보존한다. `00`=LIMIT, `03`=MARKET, `M2`=LOC, `M4`=MOC이며 모르는 코드는 확정하지 않는다. 추가 브로커 호출, 주문 제출, 매매 DB 변경 없이 기존 `fillMap`의 수량·금액 옆에 `executions: [{qty, amount, orderType}]`를 붙인다. 한 주문에서 다른 방식으로 체결되면 방식별 수량과 금액이 분리된다.

My Stock API는 이 배열의 수량·금액 합계가 기존 체결 합계와 일치할 때만 분리해 표시한다. 화면 표기는 `시장가`, `시장가(MOC)`, `지정가`, `LOC`이며 미확인 자료는 `방식 미확인`이다. 주문표의 LOC를 실제 체결 방식으로 추정하지 않는다. HYXL의 KRX 실행은 실제 제출 가격이 null이면 시장가, 가격이 있으면 지정가다. 전략 주문표의 LOC와 구분한다.

9월 23·24·25·28·29·30일 SOXL 정산의 체결 7건은 브로커 주문번호·종목·매수/매도·날짜·수량·금액을 대조해 reporting 발행본에 방식만 추가했다. 관측시각, NAV, 원금, 누적 손익, 기존 체결 수량·금액은 그대로이며 원본 매매 테이블은 수정하지 않았다. 과거 정산/매매 job을 다시 실행하지 않았다.

검증: lst 타입 검사, reporting 테스트 9개, 기존 dailyReport lot replay 5개, My Stock API 테스트 45개, Swift 모델 테스트 35개 통과.

# 주문 취소 및 원래 계획 표시 — 2026-10-03

`order-status-corrections.patch`를 기존 `src/lib/myStockAdapter.ts`, `src/lib/myStockReporting.ts`에 적용하고 `myStockAdapter.test.ts`로 검증한다. 운영 Lightsail에는 리포팅 파일 두 개만 반영했다. 실제 주문 생성·제출·취소 로직과 validated 주문표는 변경하지 않았다.

브로커 주문번호가 있어도 DB 상태가 skipped/cancelled/failed/success이면 그 상태를 유지한다. 발행 관측 시각 `capturedAt`은 갱신하고, 제출 시각은 `activityAt`으로 분리한다. 취소 후 같은 주문 상태로 돌아오는 수정도 새 발행으로 반영되며 화면의 제출 시각은 유지된다. 동일 내용의 주기 조회는 기존 RPC에서 중복 제거한다.

2026-10-02 원래 주문표는 LOC 매도 15주@$166.26, 17주@$163.40, 17주@$158.65 및 매수 155주@$165.99, 매도 158주@$153.87의 5건이다. 대체 지정가 매도 49주@$170은 브로커 취소 완료와 DB skipped를 확인했다. 앱은 이 취소된 대체 주문과 다른 원래 계획을 함께 표시하되, 계획을 제출 완료로 표시하지 않는다. 원래 주문과 동일한 주문이 취소되었거나 체결 결과가 나온 경우에는 계획을 다시 표시하지 않는다.

검증: LST 리포팅 테스트 10개 및 전체 타입 검사, API 테스트 46개, Swift 모델 테스트 37개 통과.
