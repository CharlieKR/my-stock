import test from "node:test";
import assert from "node:assert/strict";
import { reportingFillType, reportingFillExecutions } from "./myStockFillTypes";

test("broker codes distinguish LOC, market, MOC and limit without guessing missing types", () => {
  for (const [code, type] of [["00","LIMIT"],["03","MARKET"],["M2","LOC"],["M4","MOC"]]) {
    assert.equal(reportingFillType({OrdprcPtnCode:code}),type);
  }
  assert.equal(reportingFillType({}),null);
  assert.equal(reportingFillType({OrdprcPtnCode:"unknown"}),null);
});
test("partial limit and LOC executions retain their own quantities and amounts", () => {
  const result = reportingFillExecutions([
    {qty:2,price:100,orderType:"LIMIT"},{qty:3,price:110,orderType:"LIMIT"},
    {qty:5,price:120,orderType:"LOC"},{qty:0,price:120,orderType:"LOC"},
  ]);
  assert.deepEqual(result,[{qty:5,amount:530,orderType:"LIMIT"},{qty:5,amount:600,orderType:"LOC"}]);
});
