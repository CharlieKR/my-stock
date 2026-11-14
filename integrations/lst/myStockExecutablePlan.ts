import { readFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { isJobRunDone } from "./jobRunState";
import { tideSoxlMainHoldQty, tideSoxlMainSellSkipReason } from "./mainSellOrder";
import { isUSMarketDateOpen } from "./marketCalendar";
import { STRATEGIES } from "./strategies";
import { isEngineValidatedOrdersFile, type ValidatedOrdersFile } from "./validatedOrders";

type PlanInput = {
  capturedAt: string;
  details: Array<{ id: string; title: string; text: string }>;
  orders: Array<ValidatedOrdersFile["orders"][number] & { strategy: string; status: "validated" }>;
};

async function readJson<T>(path: string): Promise<T | null> {
  try {
    return JSON.parse(await readFile(path, "utf8")) as T;
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return null;
    throw error;
  }
}

// Read the same day, strategies and files as executeOrders. No broker calls
// and no writes to the executable plan. A missing file removes its rows;
// unreadable or partially written files do not replace a known-good plan.
export async function syncLstExecutablePlan(
  usDate: string,
  publish: (date: string, opts: PlanInput) => Promise<void>,
  options: { cwd?: string; outboxDir?: string; holdQty?: string } = {},
): Promise<"published" | "unchanged" | "inactive"> {
  const cwd = options.cwd ?? process.cwd();
  const done = () => isJobRunDone("execute_orders", usDate, cwd);
  if (!isUSMarketDateOpen(usDate) || done()) return "inactive";

  const outbox = resolve(cwd, options.outboxDir ?? process.env.MY_STOCK_OUTBOX_DIR ?? "data/my-stock-outbox");
  const savedPath = join(outbox, "inputs", `${usDate}-plan.json`);
  const previous = await readJson<{ opts: PlanInput }>(savedPath)
    ?? await readJson<{ opts: PlanInput }>(`${savedPath}.saved`);
  const capturedAt = new Date().toISOString();
  const files = await Promise.all(STRATEGIES.map(async strategy => {
    const file = await readJson<ValidatedOrdersFile>(join(cwd, "data", `validated_orders_${strategy.name}.json`));
    if (!file || file.usDate !== usDate) return null;
    if (!isEngineValidatedOrdersFile(strategy.name, file) || !Array.isArray(file.orders)) {
      throw new Error(`Invalid executable plan for ${strategy.name}`);
    }
    return { strategy, orders: file.orders };
  }));
  if ((!files.some(Boolean) && !previous) || done()) return "inactive";

  const holdQty = tideSoxlMainHoldQty(options.holdQty ?? process.env.TIDE_SOXL_MAIN_HOLD_QTY);
  const input: PlanInput = { capturedAt, orders: [], details: [] };
  for (const file of files) {
    if (!file) continue;
    const { strategy } = file;
    const soxl = file.orders.filter(order => order.symbol === "SOXL");
    const orders = soxl.filter(order => !(strategy.name === "ttulsa" && order.side === "매도"
      && tideSoxlMainSellSkipReason(order, holdQty, Infinity)));
    input.orders.push(...orders.map(order => ({ ...order, strategy: strategy.name, status: "validated" as const })));
    input.details.push({ id: strategy.name, title: strategy.label, text: `실행용 주문표: ${orders.length}건` });
  }
  if (JSON.stringify(input.orders) === JSON.stringify(previous?.opts.orders)
    && JSON.stringify(input.details) === JSON.stringify(previous?.opts.details)) return "unchanged";

  if (done()) return "inactive";
  await publish(usDate, input);
  return "published";
}
