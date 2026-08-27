/**
 * `removeProductBackground`: the catalog form's *Remove background* action,
 * proxied.
 *
 * **The old app called remove.bg straight from the phone with the key compiled
 * into the APK** (`lib/pos/goods.dart:1927,3012` held the same literal twice,
 * and `lib/pos/goods.dart:2277` posted to the API with it).
 * `CLIENT_CONFIGURATION_AUDIT.md` §10 records that key as compromised and says
 * what to do instead in as many words - *"rotate it, and proxy this operation
 * through a protected backend/Cloud Function using a secret manager. Do not
 * place the replacement key in a client profile or Firestore document readable
 * by the app."* That is this file.
 *
 * **It removes no background itself and it stores nothing.** The image arrives
 * base64, goes to the vendor, and the result goes back to the caller; whether
 * the operator keeps it is decided in the form, and only a *saved* correction
 * ever reaches Storage. So a cancelled edit leaves nothing behind here.
 *
 * **Unconfigured is a first-class answer, not a crash.** A deployment with no
 * `REMOVE_BG_API_KEY` refuses with `failed-precondition` and a sentence the
 * client turns into "not available in this business", because the alternative -
 * a button that throws `internal` - tells an operator that something broke when
 * in fact nothing was ever set up.
 */
import {getFirestore} from "firebase-admin/firestore";
import {defineSecret} from "firebase-functions/params";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {requireTenantMember} from "../core/authorization";
import {requireDocumentId, requireObject} from "../core/validation";
import {PRODUCT_UPDATE_ROLES} from "./productUpdate";

export const REMOVE_BG_API_KEY = defineSecret("REMOVE_BG_API_KEY");

const REMOVE_BG_ENDPOINT = "https://api.remove.bg/v1.0/removebg";

/**
 * The same ceiling the client enforces before it offers the button
 * (`maximumTenantProductImageBytes`). Declared again rather than shared because
 * this side may not trust the other one to have checked.
 */
const MAXIMUM_IMAGE_BYTES = 5 * 1024 * 1024;

/**
 * Base64 costs four characters per three bytes, so this is the widest string
 * `MAXIMUM_IMAGE_BYTES` can arrive as, plus its padding. Checked before the
 * decode so an oversized payload is refused without being materialised.
 */
const MAXIMUM_IMAGE_BASE64_LENGTH = Math.ceil(MAXIMUM_IMAGE_BYTES / 3) * 4 + 4;

/** Long enough for a large photo over a slow link, short of the 60s deadline. */
const UPSTREAM_TIMEOUT_MS = 45_000;

/** What the vendor returns, and the only type this hands back. */
const PROCESSED_CONTENT_TYPE = "image/png";

interface RemoveProductBackgroundRequest {
  tenantId?: unknown;
  imageBase64?: unknown;
}

export interface RemoveProductBackgroundResponse {
  imageBase64: string;
  contentType: string;
  /** What the vendor billed this call, when it says. Purely informational. */
  creditsCharged?: number;
}

function requireImageBase64(value: unknown): Buffer {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", "imageBase64 must be a string.");
  }
  if (value.length === 0) {
    throw new HttpsError("invalid-argument", "imageBase64 must not be empty.");
  }
  if (value.length > MAXIMUM_IMAGE_BASE64_LENGTH) {
    throw new HttpsError(
      "invalid-argument",
      "imageBase64 exceeds the maximum product image size."
    );
  }
  const bytes = Buffer.from(value, "base64");
  // `Buffer.from` never throws on malformed base64; it stops at the first
  // character it cannot read, so an empty result is how corruption presents.
  if (bytes.length === 0) {
    throw new HttpsError("invalid-argument", "imageBase64 is not valid base64.");
  }
  if (bytes.length > MAXIMUM_IMAGE_BYTES) {
    throw new HttpsError(
      "invalid-argument",
      "imageBase64 exceeds the maximum product image size."
    );
  }
  return bytes;
}

/**
 * Maps the vendor's status onto a callable code the client can word honestly.
 *
 * The distinction that matters to an operator is *whose problem is this*: a
 * spent quota and an unreadable photo need different next actions, and both
 * need to be told apart from "the service is down, try again".
 */
function upstreamFailure(status: number, body: string): HttpsError {
  switch (status) {
  case 400:
    return new HttpsError(
      "invalid-argument",
      "The image could not be processed. Choose a different photo."
    );
  case 401:
  case 403:
    return new HttpsError(
      "failed-precondition",
      "Background removal is not configured for this deployment."
    );
  case 402:
  case 429:
    return new HttpsError(
      "resource-exhausted",
      "The background removal allowance for this business is used up."
    );
  default:
    return new HttpsError(
      "unavailable",
      `Background removal is unavailable (${status}): ${body.slice(0, 200)}`
    );
  }
}

export const removeProductBackground = onCall<
  RemoveProductBackgroundRequest,
  Promise<RemoveProductBackgroundResponse>
>(
  {
    secrets: [REMOVE_BG_API_KEY],
    // A 5 MiB image, its base64, and the vendor's answer are all in memory at
    // once; the 256MiB default leaves no room for the largest permitted photo.
    memory: "512MiB",
    timeoutSeconds: 60,
  },
  async (
    request: CallableRequest<RemoveProductBackgroundRequest>
  ): Promise<RemoveProductBackgroundResponse> => {
    const data = requireObject(request.data);
    const tenantId = requireDocumentId(data.tenantId, "tenantId");
    const image = requireImageBase64(data.imageBase64);
    const db = getFirestore();
    // The same roles that may correct a product. Editing its picture is
    // editing the product, so a role list of its own would be a second
    // opinion about one question.
    await requireTenantMember(db, request, tenantId, PRODUCT_UPDATE_ROLES);

    const apiKey = REMOVE_BG_API_KEY.value();
    if (!apiKey) {
      throw new HttpsError(
        "failed-precondition",
        "Background removal is not configured for this deployment."
      );
    }

    let response: Response;
    try {
      response = await fetch(REMOVE_BG_ENDPOINT, {
        method: "POST",
        headers: {
          "X-Api-Key": apiKey,
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: new URLSearchParams({
          image_file_b64: image.toString("base64"),
          size: "auto",
        }),
        signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
      });
    } catch {
      // Deliberately swallows the cause: it can carry the request URL, and the
      // request URL is where the key would end up in a log.
      throw new HttpsError(
        "unavailable",
        "Background removal could not be reached. Nothing was changed."
      );
    }

    if (!response.ok) {
      throw upstreamFailure(response.status, await response.text().catch(() => ""));
    }

    const processed = Buffer.from(await response.arrayBuffer());
    if (processed.length === 0) {
      throw new HttpsError(
        "unavailable",
        "Background removal returned an empty image. Nothing was changed."
      );
    }
    if (processed.length > MAXIMUM_IMAGE_BYTES) {
      // The vendor returns a transparent PNG, which can be larger than the
      // JPEG that went in. Refused here rather than sent, because the client
      // holds the same ceiling and would reject the answer it just paid for
      // with a message about the file the operator chose.
      throw new HttpsError(
        "out-of-range",
        "The processed image is larger than a product image may be. Choose a smaller photo."
      );
    }
    const charged = Number(response.headers.get("x-credits-charged"));
    return {
      imageBase64: processed.toString("base64"),
      contentType: PROCESSED_CONTENT_TYPE,
      ...(Number.isFinite(charged) && charged > 0 ? {creditsCharged: charged} : {}),
    };
  }
);
