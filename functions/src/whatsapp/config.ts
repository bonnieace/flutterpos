import {defineSecret, defineString} from "firebase-functions/params";

/**
 * Where UzaPay's WhatsApp receipts are sent from.
 *
 * **One number for every business, and it is carerota's** - the developer's
 * call on 2026-10-01. The access token, phone number ID and App Secret are the
 * same values carerota's server holds; UzaPay is the authority for the number,
 * and receives its webhooks through a per-number override the developer sets
 * by hand (`functions/src/cli/whatsappWebhookOverride.ts`). Carerota itself is
 * not changed.
 *
 * **Inert until configured.** With no phone number ID every delivery is
 * written as `skipped: not_configured` and nothing is sent, so a deploy with
 * these unset changes nothing a business can see beyond that word.
 */

/** A system-user token with `whatsapp_business_messaging` on the shared WABA. */
export const WHATSAPP_ACCESS_TOKEN = defineSecret("WHATSAPP_ACCESS_TOKEN");

/** The Meta app's App Secret, which signs every webhook it delivers. */
export const WHATSAPP_APP_SECRET = defineSecret("WHATSAPP_APP_SECRET");

/** What the webhook answers Meta's verification challenge with. UzaPay's own. */
export const WHATSAPP_WEBHOOK_VERIFY_TOKEN = defineSecret(
  "WHATSAPP_WEBHOOK_VERIFY_TOKEN"
);

/** The shared number's phone number ID. Empty leaves the channel off. */
export const WHATSAPP_PHONE_NUMBER_ID = defineString("WHATSAPP_PHONE_NUMBER_ID", {
  default: "",
});

/**
 * The Graph API version every call names.
 *
 * **Check this at deploy time.** Meta retires a version about two years after
 * it ships; carerota's `v21.0` dates from late 2024 and is at the end of that
 * window, so this defaults later and is a parameter rather than a constant.
 */
export const WHATSAPP_GRAPH_VERSION = defineString("WHATSAPP_GRAPH_VERSION", {
  default: "v23.0",
});

/** The language every receipt template was approved in. */
export const WHATSAPP_TEMPLATE_LANGUAGE = defineString(
  "WHATSAPP_TEMPLATE_LANGUAGE",
  {default: "en"}
);

export const WHATSAPP_RECEIPT_TASK_FUNCTION = "deliverWhatsappReceipt";

/** The three values a send needs, or null where the channel is off. */
export interface WhatsappSendConfig {
  accessToken: string;
  phoneNumberId: string;
  graphVersion: string;
  languageCode: string;
}

/**
 * What a send would use, or null where the channel is not set up.
 *
 * **Read at call time, inside a function that binds the secrets.** A secret
 * read outside such a function throws, which is why nothing here is evaluated
 * at module load.
 */
export function whatsappSendConfig(): WhatsappSendConfig | null {
  const phoneNumberId = WHATSAPP_PHONE_NUMBER_ID.value().trim();
  if (phoneNumberId.length === 0) return null;
  let accessToken = "";
  try {
    accessToken = WHATSAPP_ACCESS_TOKEN.value().trim();
  } catch {
    return null;
  }
  if (accessToken.length === 0) return null;
  return {
    accessToken,
    phoneNumberId,
    graphVersion: WHATSAPP_GRAPH_VERSION.value().trim() || "v23.0",
    languageCode: WHATSAPP_TEMPLATE_LANGUAGE.value().trim() || "en",
  };
}
