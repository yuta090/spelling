// =============================================================================
// App Store Server Notifications V2 — JWS 署名検証（ES256 + x5c チェーン → Apple Root CA）
//
// ⚠️ 登録後タスク（先回り実装・サンドボックス未検証）:
//   - 実際の検証には **Apple Root CA - G3** 証明書が必要（env `APPLE_ROOT_CA_G3_PEM`）。
//     入手: https://www.apple.com/certificateauthority/ （AppleRootCA-G3.cer を PEM 化）。
//   - **登録後、必ず Sandbox の実 ASSN で検証すること**（本関数は decode 前の防壁。
//     ここが甘いと誰でも「課金済み」を捏造できるため fail-closed を厳守）。
//
// 設計: x5c[0]=leaf, x5c[1]=intermediate, x5c[2]=root。各証明書の有効期限と署名連鎖を確認し、
//       チェーン最上位が Apple Root CA G3 と一致することを検証 → leaf 公開鍵で JWS 署名検証。
// =============================================================================
import * as x509 from "https://esm.sh/@peculiar/x509@1.12.3";
import { compactVerify, importX509 } from "https://esm.sh/jose@5.9.6";

x509.cryptoProvider.set(crypto);

// Apple の ASSN 署名証明書プロファイル OID（Apple 公式 SignedDataVerifier と同じ）。
// これを検証しないと「Apple Root に繋がる任意の ECDSA 証明書」で偽造できてしまう
// （Apple Root CA は ASSN 以外の用途にも署名するため、root ピンだけでは不十分）。
const OID_ASSN_LEAF = "1.2.840.113635.100.6.11.1";          // ASSN リーフ
const OID_WWDR_INTERMEDIATE = "1.2.840.113635.100.6.2.1";   // WWDR 中間
const MAX_CERT_CHARS = 4000;                                 // 1証明書(base64)の上限

function pemFromDerBase64(derBase64: string): string {
  const body = derBase64.match(/.{1,64}/g)?.join("\n") ?? derBase64;
  return `-----BEGIN CERTIFICATE-----\n${body}\n-----END CERTIFICATE-----`;
}

function hasExtension(cert: x509.X509Certificate, oid: string): boolean {
  return cert.extensions.some((e) => e.type === oid);
}

/**
 * Apple ASSN V2 の signedPayload(JWS) を検証し、検証済みの payload(JSON) を返す。
 * いずれかの検証に失敗したら例外（fail-closed）。
 *
 * @param jws            signedPayload / signedTransactionInfo / signedRenewalInfo のいずれか
 * @param appleRootPem   Apple Root CA G3 の PEM（env から）
 * @param atDate         検証基準時刻（既定: 現在）
 */
export async function verifyAppleJws(
  jws: string,
  appleRootPem: string,
  atDate: Date = new Date(),
): Promise<unknown> {
  if (!appleRootPem || !appleRootPem.includes("BEGIN CERTIFICATE")) {
    throw new Error("APPLE_ROOT_CA_G3_PEM not configured (fail-closed)");
  }
  const segments = jws.split(".");
  if (segments.length !== 3) throw new Error("invalid JWS (expected 3 segments)");
  const header = JSON.parse(atob(segments[0].replace(/-/g, "+").replace(/_/g, "/")));

  // alg を ES256 に固定（alg 混同/none を排除）。
  if (header.alg !== "ES256") throw new Error(`unexpected alg: ${header.alg}`);

  const x5c: unknown = header.x5c;
  // Apple ASSN は厳密に leaf/intermediate/root の3枚（Apple 公式と同じ前提）。
  if (!Array.isArray(x5c) || x5c.length !== 3) {
    throw new Error("x5c chain must be exactly 3 certificates");
  }
  if (x5c.some((c) => typeof c !== "string" || c.length > MAX_CERT_CHARS)) {
    throw new Error("x5c entry invalid or too large");
  }

  const chain = x5c.map((c) => new x509.X509Certificate(pemFromDerBase64(String(c))));
  const root = new x509.X509Certificate(appleRootPem);

  // 1) 各証明書の有効期限。
  for (const cert of chain) {
    if (atDate < cert.notBefore || atDate > cert.notAfter) {
      throw new Error("certificate in chain is expired or not yet valid");
    }
  }
  // 2) ASSN 証明書プロファイル: leaf と intermediate に Apple 専用 OID があること。
  //    （root ピンだけだと Apple-root に繋がる別用途証明書で偽造できるため必須）
  if (!hasExtension(chain[0], OID_ASSN_LEAF)) {
    throw new Error("leaf is not an App Store Server Notification signing cert");
  }
  if (!hasExtension(chain[1], OID_WWDR_INTERMEDIATE)) {
    throw new Error("intermediate is not the Apple WWDR CA");
  }
  // 3) 署名連鎖: chain[i] は chain[i+1] の公開鍵で署名検証できること。
  for (let i = 0; i < chain.length - 1; i++) {
    const ok = await chain[i].verify({ publicKey: await chain[i + 1].publicKey.export(), date: atDate });
    if (!ok) throw new Error(`chain link ${i} signature invalid`);
  }
  // 4) チェーン最上位が設定された Apple Root CA G3 と一致（指紋一致）。
  const top = chain[chain.length - 1];
  if (toHex(await top.getThumbprint("SHA-256")) !== toHex(await root.getThumbprint("SHA-256"))) {
    throw new Error("chain does not anchor to the configured Apple Root CA G3");
  }
  // 5) leaf 公開鍵で JWS 署名検証（ES256）。
  const leafKey = await importX509(chain[0].toString("pem"), "ES256");
  const { payload } = await compactVerify(jws, leafKey, { algorithms: ["ES256"] });
  return JSON.parse(new TextDecoder().decode(payload));
}

function toHex(buf: ArrayBuffer): string {
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
