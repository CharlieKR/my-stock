// Reporting worker. Never import or run a trading job here.
import { getSupabase } from "../lib/supabase";
import { getUSMarketDate } from "../lib/marketCalendar";
import { flushReportingOutbox, reportingEnabled } from "../lib/myStockReporting";
import { publishLstReporting, replayLstReportingInputs } from "../lib/myStockAdapter";
import { syncLstExecutablePlan } from "../lib/myStockExecutablePlan";

async function main() {
  const sb = getSupabase();
  if (!reportingEnabled()) return;
  console.log("[my-stock] retry", await flushReportingOutbox(sb));
  await replayLstReportingInputs();
  const today = getUSMarketDate();
  const requestedDate = process.argv[2];
  if (requestedDate && !/^\d{4}-\d{2}-\d{2}$/.test(requestedDate)) throw new Error("Expected YYYY-MM-DD");

  // Plan refresh must run even when no order has been submitted yet.
  // Historical execution repair never rewrites historical plans.
  if (!requestedDate || requestedDate === today) {
    try {
      const status = await syncLstExecutablePlan(today, (date, opts) => publishLstReporting(date, "plan", opts));
      if (status === "published") console.log("[my-stock] executable plan changed", today);
    } catch {
      console.warn("[my-stock] executable plan unavailable; keeping last report");
      process.exitCode = 1;
    }
  }

  let dates = [requestedDate ?? today];
  if (!requestedDate && sb) {
    const from = new Date(today + "T00:00:00Z"); from.setUTCDate(from.getUTCDate() - 7);
    const { data, error } = await sb.from("orders").select("us_date").eq("symbol", "SOXL").gte("us_date", from.toISOString().slice(0, 10));
    if (error) throw new Error("Reporting date lookup failed");
    dates = [...new Set((data ?? []).map(r => String(r.us_date)))].sort();
  }
  for (const date of dates) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) throw new Error("Expected YYYY-MM-DD");
    await publishLstReporting(date, "execution");
  }
}
if (require.main === module) main().catch(() => { console.error("[my-stock] retry failed"); process.exitCode = 1; });
