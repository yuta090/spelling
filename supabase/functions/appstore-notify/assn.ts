// =============================================================================
// App Store Server Notifications V2 — 純粋ロジック（Apple非依存・テスト対象）
//
// 役割: 署名検証済みの通知 payload（＋ネストした取引/更新情報）を、DB の
// app.upsert_entitlement に渡す「世帯権利の更新」へマッピングする。
// 署名検証は verify.ts（要 Apple ルート証明書・登録後にサンドボックス検証）。
//
// 参照: App Store Server Notifications V2
//   responseBodyV2DecodedPayload { notificationType, subtype, notificationUUID, signedDate, data }
//   data { bundleId, environment, signedTransactionInfo(JWS), signedRenewalInfo(JWS) }
//   JWSTransactionDecodedPayload { originalTransactionId, productId, expiresDate(ms),
//                                  appAccountToken, offerType, environment, ... }
//   JWSRenewalInfoDecodedPayload { autoRenewStatus, gracePeriodExpiresDate(ms), ... }
// =============================================================================

export type EntitlementStatus =
  | "none" | "trial" | "active" | "grace" | "expired" | "revoked";

/** DB の app.upsert_entitlement に渡す更新内容。 */
export interface EntitlementUpdate {
  householdId: string;            // appAccountToken（購入時に household_id を載せる）
  productId: string;
  status: EntitlementStatus;
  expiresAt: string | null;       // ISO8601（無期限/不明は null）
  originalTransactionId: string;
  environment: string;            // "Production" | "Sandbox"
  eventAt: string;                // ISO8601（signedDate）＝単調ガードのキー
}

/** マップできない通知（無視）の理由。 */
export interface SkippedNotification { skip: string; }

export interface DecodedNotification {
  notificationType: string;
  subtype?: string;
  signedDate?: number;            // ms epoch
  data?: {
    bundleId?: string;
    environment?: string;
  };
}

export interface DecodedTransaction {
  originalTransactionId?: string;
  productId?: string;
  expiresDate?: number;           // ms epoch
  appAccountToken?: string;
  offerType?: number;             // 1=introductory(無料/イントロ), 2=promo, 3=code
  environment?: string;
  bundleId?: string;
}

export interface DecodedRenewalInfo {
  autoRenewStatus?: number;       // 0=off, 1=on
  gracePeriodExpiresDate?: number;
}

/** base64url → 文字列（UTF-8）。 */
export function base64UrlDecode(input: string): string {
  const b64 = input.replace(/-/g, "+").replace(/_/g, "/")
    .padEnd(Math.ceil(input.length / 4) * 4, "=");
  const bin = atob(b64);
  const bytes = Uint8Array.from(bin, (c) => c.charCodeAt(0));
  return new TextDecoder().decode(bytes);
}

/** JWS の payload 部だけを decode（※署名検証はしない。verify.ts で検証後に使うか、
 *  検証済み JWS のネスト分の取り出しに使う）。 */
export function decodeJwsPayload<T = unknown>(jws: string): T {
  const parts = jws.split(".");
  if (parts.length !== 3) throw new Error("invalid JWS (expected 3 parts)");
  return JSON.parse(base64UrlDecode(parts[1])) as T;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** appAccountToken が UUID 形（= household_id として使える）か。 */
export function isUuid(s: string | undefined | null): boolean {
  return typeof s === "string" && UUID_RE.test(s);
}

/** productId が許可リスト（カンマ区切り）に含まれるか。 */
export function productAllowed(productId: string, allowlistCsv: string): boolean {
  const set = allowlistCsv.split(",").map((s) => s.trim()).filter(Boolean);
  return set.length > 0 && set.includes(productId);
}

function msToIso(ms: number | undefined | null): string | null {
  if (ms === undefined || ms === null) return null;
  return new Date(ms).toISOString();
}

/**
 * 通知タイプ → 世帯権利のステータスへ写像。
 * 不明タイプや households 解決不能（appAccountToken 無し）は skip（状態を変えない）。
 */
export function mapNotificationToEntitlement(
  notification: DecodedNotification,
  transaction: DecodedTransaction,
  renewal?: DecodedRenewalInfo,
): EntitlementUpdate | SkippedNotification {
  const householdId = transaction.appAccountToken;
  if (!householdId) {
    return { skip: "no appAccountToken (cannot resolve household)" };
  }
  if (!transaction.productId || !transaction.originalTransactionId) {
    return { skip: "missing productId/originalTransactionId" };
  }

  const type = notification.notificationType;
  const subtype = notification.subtype;
  let status: EntitlementStatus | null = null;

  switch (type) {
    case "SUBSCRIBED":
    case "DID_RENEW":
    case "OFFER_REDEEMED":
    case "DID_CHANGE_RENEWAL_PREF":   // プラン変更でもアクセスは継続
    case "DID_CHANGE_RENEWAL_STATUS": // 自動更新ON/OFFの切替。失効日まではアクセス可
    case "RENEWAL_EXTENDED":
    case "PRICE_INCREASE":
      // イントロ（無料）オファー利用中は trial 表示に寄せる。
      status = transaction.offerType === 1 ? "trial" : "active";
      break;
    case "DID_FAIL_TO_RENEW":
      // 猶予期間に入っていれば grace（まだアクセス可）、無ければ失効。
      status = subtype === "GRACE_PERIOD" ? "grace" : "expired";
      break;
    case "GRACE_PERIOD_EXPIRED":
    case "EXPIRED":
      status = "expired";
      break;
    case "REFUND":
    case "REVOKE":                    // ファミリー共有の取り消し等
      status = "revoked";
      break;
    default:
      return { skip: `unhandled notificationType: ${type}` };
  }

  // grace のときは猶予失効日を優先（無ければ取引の失効日）。
  const expiresMs = status === "grace" && renewal?.gracePeriodExpiresDate
    ? renewal.gracePeriodExpiresDate
    : transaction.expiresDate;

  return {
    householdId,
    productId: transaction.productId,
    status,
    expiresAt: msToIso(expiresMs),
    originalTransactionId: transaction.originalTransactionId,
    environment: notification.data?.environment ?? transaction.environment ?? "Production",
    eventAt: msToIso(notification.signedDate) ?? new Date(0).toISOString(),
  };
}
