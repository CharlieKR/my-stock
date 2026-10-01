# 실제 체결 방식 — 2026-10-01

`myStockFillTypes.ts`와 테스트를 lst `src/lib/`에 복사하고 `dailyReport-fill-types.patch`의 변경을 `src/jobs/dailyReport.ts`에 반영한다. 현재 로컬 lst와 운영 Lightsail에는 반영되어 있다. 기존 lst 작업 트리에 있던 다른 변경은 커밋하거나 덮어쓰지 않았다.

LS에서 이미 읽은 체결 행의 `OrdprcPtnCode`를 reporting 메타데이터로 보존한다. `00`=LIMIT, `03`=MARKET, `M2`=LOC, `M4`=MOC이며 모르는 코드는 확정하지 않는다. 추가 브로커 호출, 주문 제출, 매매 DB 변경 없이 기존 `fillMap`의 수량·금액 옆에 `executions: [{qty, amount, orderType}]`를 붙인다. 한 주문에서 다른 방식으로 체결되면 방식별 수량과 금액이 분리된다.

My Stock API는 이 배열의 수량·금액 합계가 기존 체결 합계와 일치할 때만 분리해 표시한다. 화면 표기는 `시장가`, `시장가(MOC)`, `지정가`, `LOC`이며 미확인 자료는 `방식 미확인`이다. 주문표의 LOC를 실제 체결 방식으로 추정하지 않는다. HYXL의 KRX 실행은 실제 제출 가격이 null이면 시장가, 가격이 있으면 지정가다. 전략 주문표의 LOC와 구분한다.

9월 23·24·25·28·29·30일 SOXL 정산의 체결 7건은 브로커 주문번호·종목·매수/매도·날짜·수량·금액을 대조해 reporting 발행본에 방식만 추가했다. 관측시각, NAV, 원금, 누적 손익, 기존 체결 수량·금액은 그대로이며 원본 매매 테이블은 수정하지 않았다. 과거 정산/매매 job을 다시 실행하지 않았다.

검증: lst 타입 검사, reporting 테스트 9개, 기존 dailyReport lot replay 5개, My Stock API 테스트 45개, Swift 모델 테스트 35개 통과.
