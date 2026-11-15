import { parsePlusEvent } from "./event.ts";

const event = {
  type: "INITIAL_PURCHASE",
  app_id: "app_test",
  environment: "SANDBOX",
  app_user_id: "00000000-0000-4000-8000-000000000001",
  original_transaction_id: "transaction-1",
  product_id: "kindred_plus_monthly",
  entitlement_ids: ["plus"],
  expiration_at_ms: 1_800_000_000_000,
  event_timestamp_ms: 1_797_000_000_000,
};

Deno.test("parses both plans and required lifecycle events", () => {
  for (
    const type of ["INITIAL_PURCHASE", "RENEWAL", "CANCELLATION", "EXPIRATION"]
  ) {
    for (const product_id of ["kindred_plus_monthly", "kindred_plus_3month"]) {
      const result = parsePlusEvent(
        { event: { ...event, type, product_id } },
        "app_test",
        "SANDBOX",
      );
      if (
        result?.subscriber !== event.app_user_id ||
        result.product !== product_id ||
        result.event_type !== type ||
        result.period_end !== new Date(event.expiration_at_ms).toISOString()
      ) {
        throw new Error("Unexpected entitlement projection");
      }
    }
  }
});

Deno.test("ignores unrelated events and anonymous customer IDs", () => {
  for (
    const override of [
      { entitlement_ids: [] },
      { app_id: "another_app" },
      { environment: "PRODUCTION" },
      { type: "TEST" },
      { app_user_id: "$RCAnonymousID:example" },
      { product_id: "another_product" },
    ]
  ) {
    if (
      parsePlusEvent(
        { event: { ...event, ...override } },
        "app_test",
        "SANDBOX",
      ) !== null
    ) {
      throw new Error("Unexpected entitlement for unrelated event");
    }
  }
});

Deno.test("rejects invalid expiration timestamps", () => {
  try {
    parsePlusEvent(
      { event: { ...event, expiration_at_ms: null } },
      "app_test",
      "SANDBOX",
    );
  } catch {
    return;
  }
  throw new Error("Accepted a missing expiration date");
});
