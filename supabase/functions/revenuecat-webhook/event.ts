const lifecycle = new Set([
  "INITIAL_PURCHASE",
  "RENEWAL",
  "CANCELLATION",
  "EXPIRATION",
  "BILLING_ISSUE",
]);
const products = new Set(["kindred_plus_monthly", "kindred_plus_3month"]);
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}

function timestamp(value: unknown): number {
  if (
    typeof value !== "number" || !Number.isSafeInteger(value) || value <= 0 ||
    value > 8.64e15
  ) {
    throw new Error("Invalid subscription timestamp");
  }
  return value;
}

export function parsePlusEvent(
  payload: unknown,
  appID: string,
  environment: string,
) {
  const event = record(record(payload)?.event);
  if (!event || typeof event.type !== "string") {
    throw new Error("Missing RevenueCat event");
  }
  if (
    !lifecycle.has(event.type) || event.app_id !== appID ||
    event.environment !== environment ||
    typeof event.product_id !== "string" || !products.has(event.product_id) ||
    !Array.isArray(event.entitlement_ids) ||
    !event.entitlement_ids.includes("plus")
  ) return null;

  const subscriber = event.app_user_id;
  // Purchases use the signed-in Supabase UUID. Never guess an owner from aliases.
  if (typeof subscriber !== "string" || !uuid.test(subscriber)) return null;
  if (
    typeof event.original_transaction_id !== "string" ||
    !event.original_transaction_id.trim()
  ) {
    throw new Error("Missing original transaction identifier");
  }

  const expiration = timestamp(event.expiration_at_ms);
  const grace = event.type === "BILLING_ISSUE" &&
      event.grace_period_expiration_at_ms != null
    ? timestamp(event.grace_period_expiration_at_ms)
    : expiration;
  return {
    subscriber,
    transaction_chain: event.original_transaction_id,
    product: event.product_id,
    event_type: event.type,
    event_time: new Date(timestamp(event.event_timestamp_ms)).toISOString(),
    period_end: new Date(Math.max(expiration, grace)).toISOString(),
  };
}
