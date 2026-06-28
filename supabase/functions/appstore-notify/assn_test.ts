// Deno tests for the App Store Server Notifications V2 pure mapping logic.
//   run: deno test supabase/functions/appstore-notify/assn_test.ts
import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  base64UrlDecode,
  decodeJwsPayload,
  isUuid,
  mapNotificationToEntitlement,
  productAllowed,
  type DecodedNotification,
  type DecodedTransaction,
  type EntitlementUpdate,
  type SkippedNotification,
} from "./assn.ts";

const HH = "11111111-1111-1111-1111-111111111111";

function b64url(obj: unknown): string {
  const json = JSON.stringify(obj);
  const bytes = new TextEncoder().encode(json);
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function makeJws(payload: unknown): string {
  return `${b64url({ alg: "ES256" })}.${b64url(payload)}.${b64url("sig")}`;
}

function tx(over: Partial<DecodedTransaction> = {}): DecodedTransaction {
  return {
    originalTransactionId: "OTX-1",
    productId: "com.yuta090.SpellingTrainer.parentplan.monthly",
    expiresDate: 1893456000000, // 2030-01-01
    appAccountToken: HH,
    environment: "Production",
    ...over,
  };
}

function notif(type: string, subtype?: string): DecodedNotification {
  return { notificationType: type, subtype, signedDate: 1735689600000, data: { environment: "Production" } };
}

function asUpdate(r: EntitlementUpdate | SkippedNotification): EntitlementUpdate {
  assert(!("skip" in r), `expected update, got skip: ${(r as SkippedNotification).skip}`);
  return r as EntitlementUpdate;
}

Deno.test("base64UrlDecode round-trips JSON", () => {
  const decoded = base64UrlDecode(b64url({ hello: "✓世界" }));
  assertEquals(JSON.parse(decoded).hello, "✓世界");
});

Deno.test("decodeJwsPayload extracts the middle segment", () => {
  const got = decodeJwsPayload<{ notificationType: string }>(makeJws({ notificationType: "DID_RENEW" }));
  assertEquals(got.notificationType, "DID_RENEW");
});

Deno.test("decodeJwsPayload rejects malformed JWS", () => {
  let threw = false;
  try { decodeJwsPayload("not-a-jws"); } catch { threw = true; }
  assert(threw, "must throw on malformed JWS");
});

Deno.test("SUBSCRIBED → active with expiry, household from appAccountToken", () => {
  const u = asUpdate(mapNotificationToEntitlement(notif("SUBSCRIBED", "INITIAL_BUY"), tx()));
  assertEquals(u.status, "active");
  assertEquals(u.householdId, HH);
  assertEquals(u.productId, "com.yuta090.SpellingTrainer.parentplan.monthly");
  assertEquals(u.originalTransactionId, "OTX-1");
  assertEquals(u.expiresAt, new Date(1893456000000).toISOString());
  assertEquals(u.eventAt, new Date(1735689600000).toISOString());
});

Deno.test("introductory offer (offerType 1) → trial", () => {
  const u = asUpdate(mapNotificationToEntitlement(notif("SUBSCRIBED", "INITIAL_BUY"), tx({ offerType: 1 })));
  assertEquals(u.status, "trial");
});

Deno.test("DID_RENEW → active", () => {
  assertEquals(asUpdate(mapNotificationToEntitlement(notif("DID_RENEW"), tx())).status, "active");
});

Deno.test("DID_FAIL_TO_RENEW GRACE_PERIOD → grace (uses gracePeriodExpiresDate)", () => {
  const grace = 1800000000000;
  const u = asUpdate(mapNotificationToEntitlement(
    notif("DID_FAIL_TO_RENEW", "GRACE_PERIOD"), tx(), { gracePeriodExpiresDate: grace }));
  assertEquals(u.status, "grace");
  assertEquals(u.expiresAt, new Date(grace).toISOString());
});

Deno.test("DID_FAIL_TO_RENEW without grace → expired", () => {
  assertEquals(asUpdate(mapNotificationToEntitlement(notif("DID_FAIL_TO_RENEW"), tx())).status, "expired");
});

Deno.test("EXPIRED / GRACE_PERIOD_EXPIRED → expired", () => {
  assertEquals(asUpdate(mapNotificationToEntitlement(notif("EXPIRED", "VOLUNTARY"), tx())).status, "expired");
  assertEquals(asUpdate(mapNotificationToEntitlement(notif("GRACE_PERIOD_EXPIRED"), tx())).status, "expired");
});

Deno.test("REFUND / REVOKE → revoked", () => {
  assertEquals(asUpdate(mapNotificationToEntitlement(notif("REFUND"), tx())).status, "revoked");
  assertEquals(asUpdate(mapNotificationToEntitlement(notif("REVOKE"), tx())).status, "revoked");
});

Deno.test("DID_CHANGE_RENEWAL_STATUS (auto-renew off) stays active until expiry", () => {
  const u = asUpdate(mapNotificationToEntitlement(
    notif("DID_CHANGE_RENEWAL_STATUS", "AUTO_RENEW_DISABLED"), tx(), { autoRenewStatus: 0 }));
  assertEquals(u.status, "active");
});

Deno.test("missing appAccountToken → skip (cannot resolve household)", () => {
  const r = mapNotificationToEntitlement(notif("SUBSCRIBED"), tx({ appAccountToken: undefined }));
  assert("skip" in r);
});

Deno.test("unknown notificationType → skip (no state change)", () => {
  const r = mapNotificationToEntitlement(notif("SOMETHING_NEW"), tx());
  assert("skip" in r);
});

Deno.test("missing productId/originalTransactionId → skip", () => {
  assert("skip" in mapNotificationToEntitlement(notif("SUBSCRIBED"), tx({ productId: undefined })));
  assert("skip" in mapNotificationToEntitlement(notif("SUBSCRIBED"), tx({ originalTransactionId: undefined })));
});

Deno.test("isUuid accepts UUID, rejects junk", () => {
  assert(isUuid(HH));
  assert(!isUuid("not-a-uuid"));
  assert(!isUuid(""));
  assert(!isUuid(undefined));
});

Deno.test("productAllowed enforces allowlist", () => {
  const csv = "com.yuta090.SpellingTrainer.parentplan.monthly, com.yuta090.SpellingTrainer.parentplan.yearly";
  assert(productAllowed("com.yuta090.SpellingTrainer.parentplan.monthly", csv));
  assert(productAllowed("com.yuta090.SpellingTrainer.parentplan.yearly", csv));
  assert(!productAllowed("com.evil.product", csv));
  assert(!productAllowed("anything", ""));   // 空リストは全拒否（fail-closed）
});
