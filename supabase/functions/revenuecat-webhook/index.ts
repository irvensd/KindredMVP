import { timingSafeEqual } from "node:crypto";
import { parsePlusEvent } from "./event.ts";

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return new Response(null, { status: 405, headers: { Allow: "POST" } });
  }

  const secret = Deno.env.get("REVENUECAT_WEBHOOK_SECRET");
  const appID = Deno.env.get("REVENUECAT_APP_ID");
  const environment = Deno.env.get("REVENUECAT_WEBHOOK_ENVIRONMENT") ??
    "PRODUCTION";
  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (
    !secret || !appID || !supabaseURL || !serviceKey ||
    !["SANDBOX", "PRODUCTION"].includes(environment)
  ) {
    return new Response("Webhook configuration unavailable", { status: 503 });
  }

  const encoder = new TextEncoder();
  const expected = encoder.encode(`Bearer ${secret}`);
  const supplied = encoder.encode(request.headers.get("Authorization") ?? "");
  if (
    expected.length !== supplied.length || !timingSafeEqual(expected, supplied)
  ) {
    return new Response(null, { status: 401 });
  }

  let event;
  try {
    event = parsePlusEvent(await request.json(), appID, environment);
  } catch {
    return new Response("Invalid subscription event", { status: 400 });
  }
  if (!event) return new Response("OK", { status: 200 });

  try {
    const result = await fetch(
      `${supabaseURL}/rest/v1/rpc/apply_revenuecat_plus_event`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${serviceKey}`,
          apikey: serviceKey,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(event),
        signal: AbortSignal.timeout(8000),
      },
    );
    if (result.ok) return new Response("OK", { status: 200 });
    console.error("Kindred Plus event write failed", result.status);
  } catch {
    console.error("Kindred Plus event write unavailable");
  }
  return new Response("Subscription update unavailable", { status: 503 });
});
