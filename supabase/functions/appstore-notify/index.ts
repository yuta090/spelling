// =============================================================================
// Edge Function: appstore-notify
//   App Store Server Notifications V2 の受け口。
//   署名検証(verify.ts) → decode/マッピング(assn.ts) → public.upsert_entitlement(service_role)。
//
// デプロイ後の設定（Apple Developer 登録後）:
//   - App Store Connect → App → Server Notifications V2 の本番/サンドボックスURLに
//     `https://<project-ref>.functions.supabase.co/appstore-notify` を設定。
//   - Edge secrets（すべて必須・未設定は fail-closed で 500）:
//       APPLE_ROOT_CA_G3_PEM   … Apple Root CA G3 の PEM（署名検証の信頼アンカー）
//       APPLE_BUNDLE_ID        … com.yuta090.SpellingTrainer（受理する bundleId）
//       APPLE_ENVIRONMENT      … "Production" または "Sandbox"（環境混同を防ぐ）
//       APPLE_PRODUCT_IDS      … 許可する Product ID（カンマ区切り）
//       SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY … service_role で upsert するため
//   - 本番用とサンドボックス用は **別 Supabase プロジェクト/関数** に分けるのが安全
//     （APPLE_ENVIRONMENT で取り違えを拒否はするが、分離が確実）。
//   - **デプロイ後、Sandbox の実通知で end-to-end 検証すること**（verify.ts はサンドボックス未検証）。
//
// 返却方針: 署名/形式/環境不正は 400。受理して状態変更不要/未対応タイプ/対象外は 200
//   （Apple の再送嵐を避ける）。upsert 失敗など一時障害は 500（Apple は再送する）。
// =============================================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { verifyAppleJws } from "./verify.ts";
import {
  isUuid,
  mapNotificationToEntitlement,
  productAllowed,
  type DecodedNotification,
  type DecodedRenewalInfo,
  type DecodedTransaction,
} from "./assn.ts";

const env = (k: string) => Deno.env.get(k) ?? "";
const MAX_BODY_BYTES = 256 * 1024; // ASSN は数KB。過大ボディは弾く。

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("method not allowed", { status: 405 });

  // すべての必須シークレットが揃っていなければ動かさない（fail-closed）。
  const cfg = {
    appleRoot: env("APPLE_ROOT_CA_G3_PEM"),
    bundleId: env("APPLE_BUNDLE_ID"),
    environment: env("APPLE_ENVIRONMENT"),
    productIds: env("APPLE_PRODUCT_IDS"),
    supabaseUrl: env("SUPABASE_URL"),
    serviceKey: env("SUPABASE_SERVICE_ROLE_KEY"),
  };
  if (Object.values(cfg).some((v) => !v)) {
    console.error("appstore-notify: missing required secrets");
    return new Response("server not configured", { status: 500 });
  }

  // 1) ボディ取得（サイズ上限）→ signedPayload 取り出し。
  let signedPayload: string;
  try {
    const raw = await req.text();
    if (raw.length > MAX_BODY_BYTES) return new Response("payload too large", { status: 413 });
    const body = JSON.parse(raw);
    signedPayload = body.signedPayload;
    if (typeof signedPayload !== "string") throw new Error("no signedPayload");
  } catch {
    return new Response("bad request", { status: 400 });
  }

  // 2) 外側通知の署名検証。
  let notification: DecodedNotification;
  try {
    notification = await verifyAppleJws(signedPayload, cfg.appleRoot) as DecodedNotification;
  } catch (e) {
    console.error("appstore-notify: signature verification failed", String(e));
    return new Response("invalid signature", { status: 400 });
  }

  // 3) 外側の bundleId / environment を照合（他アプリ・Sandbox→本番混入を拒否）。
  const ndata = (notification.data ?? {}) as { bundleId?: string; environment?: string; signedTransactionInfo?: unknown; signedRenewalInfo?: unknown };
  if (ndata.bundleId !== cfg.bundleId) {
    console.warn("appstore-notify: bundleId mismatch, ignoring");
    return new Response("ok", { status: 200 });
  }
  if (ndata.environment !== cfg.environment) {
    console.warn(`appstore-notify: environment mismatch (got ${ndata.environment}), ignoring`);
    return new Response("ok", { status: 200 });
  }

  // 4) ネストした取引/更新情報を独立に署名検証し、identity を再照合。
  let transaction: DecodedTransaction = {};
  let renewal: DecodedRenewalInfo | undefined;
  try {
    if (typeof ndata.signedTransactionInfo === "string") {
      transaction = await verifyAppleJws(ndata.signedTransactionInfo, cfg.appleRoot) as DecodedTransaction;
    }
    if (typeof ndata.signedRenewalInfo === "string") {
      renewal = await verifyAppleJws(ndata.signedRenewalInfo, cfg.appleRoot) as DecodedRenewalInfo;
    }
  } catch (e) {
    console.error("appstore-notify: nested JWS verification failed", String(e));
    return new Response("invalid signature", { status: 400 });
  }
  if (transaction.bundleId !== undefined && transaction.bundleId !== cfg.bundleId) {
    console.warn("appstore-notify: transaction bundleId mismatch, ignoring");
    return new Response("ok", { status: 200 });
  }
  if (transaction.environment !== undefined && transaction.environment !== cfg.environment) {
    console.warn("appstore-notify: transaction environment mismatch, ignoring");
    return new Response("ok", { status: 200 });
  }

  // 5) 世帯権利の更新へマッピング。
  const mapped = mapNotificationToEntitlement(notification, transaction, renewal);
  if ("skip" in mapped) {
    console.log(`appstore-notify: skipped (${mapped.skip})`);
    return new Response("ok", { status: 200 });
  }
  // 6) household(=appAccountToken) の形と商品の許可リストを確認（不正は無視＝200）。
  if (!isUuid(mapped.householdId)) {
    console.warn("appstore-notify: appAccountToken is not a UUID, ignoring");
    return new Response("ok", { status: 200 });
  }
  if (!productAllowed(mapped.productId, cfg.productIds)) {
    console.warn(`appstore-notify: product not allowlisted (${mapped.productId}), ignoring`);
    return new Response("ok", { status: 200 });
  }

  // 7) service_role で upsert（単調ガード/なりすまし防止は DB 側）。
  const supabase = createClient(cfg.supabaseUrl, cfg.serviceKey, { auth: { persistSession: false } });
  const { error } = await supabase.rpc("upsert_entitlement", {
    p_household_id: mapped.householdId,
    p_product_id: mapped.productId,
    p_status: mapped.status,
    p_expires_at: mapped.expiresAt,
    p_original_transaction_id: mapped.originalTransactionId,
    p_environment: mapped.environment,
    p_event_at: mapped.eventAt,
  });
  if (error) {
    console.error("appstore-notify: upsert_entitlement failed", error.message);
    return new Response("upsert failed", { status: 500 }); // Apple に再送させる
  }

  return new Response("ok", { status: 200 });
});
