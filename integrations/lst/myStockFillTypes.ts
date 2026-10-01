// Read-only display metadata from LS broker records, never from the order plan.
export function reportingFillType(raw: Record<string, unknown>): string | null {
  const code = String(raw.OrdprcPtnCode ?? "").trim().toUpperCase();
  return ({ "00": "LIMIT", "03": "MARKET", M2: "LOC", M4: "MOC" } as Record<string, string>)[code] ?? null;
}

export function reportingFillExecutions(parts: Array<{qty: number; price: number; orderType: string | null}>) {
  const groups = new Map<string | null, {qty: number; amount: number; orderType: string | null}>();
  for (const part of parts) {
    if (!(part.qty > 0) || !(part.price > 0)) continue;
    const group = groups.get(part.orderType) ?? {qty: 0, amount: 0, orderType: part.orderType};
    group.qty += part.qty;
    group.amount += part.qty * part.price;
    groups.set(part.orderType, group);
  }
  return [...groups.values()];
}
