import {defineSecret, defineString} from "firebase-functions/params";

/**
 * Where the daily WhatsApp report is sent from and to.
 *
 * The sender is the WhatsApp Business number UzaPay's e-receipts use (the
 * multitenant app's `functions/src/whatsapp/config.ts`). Sending only needs
 * the number's phone number ID, a token allowed to message from its account,
 * and an approved template on that account, so this project holds copies of
 * the first two and nothing in UzaPay changes. Replies and delivery statuses
 * go to UzaPay's webhook, which drops statuses it has no record of.
 *
 * Inert until configured: with the phone number ID or the recipient `unset`,
 * the scheduled run logs that it skipped and sends nothing.
 */

/** A system-user token with `whatsapp_business_messaging` on the shared account. */
export const WHATSAPP_ACCESS_TOKEN = defineSecret("WHATSAPP_ACCESS_TOKEN");

export const UNSET = "unset";

/** The shared number's phone number ID. */
export const WHATSAPP_PHONE_NUMBER_ID = defineString("WHATSAPP_PHONE_NUMBER_ID", {
  default: UNSET,
});

/** Meta retires a Graph version about two years after it ships. */
export const WHATSAPP_GRAPH_VERSION = defineString("WHATSAPP_GRAPH_VERSION", {
  default: "v23.0",
});

/** The approved template's name and language. */
export const DAY_REPORT_TEMPLATE = defineString("DAY_REPORT_TEMPLATE", {
  default: "thamani_day_summary_v1",
});
export const DAY_REPORT_TEMPLATE_LANGUAGE = defineString(
  "DAY_REPORT_TEMPLATE_LANGUAGE",
  {default: "en"}
);

/** Who gets the report, in E.164 (`+254712345678`). */
export const DAY_REPORT_RECIPIENT = defineString("DAY_REPORT_RECIPIENT", {
  default: UNSET,
});

export interface DayReportSendConfig {
  accessToken: string;
  phoneNumberId: string;
  graphVersion: string;
  templateName: string;
  languageCode: string;
  recipient: string;
}

function configured(value: string): string | null {
  const trimmed = value.trim();
  return trimmed.length === 0 || trimmed === UNSET ? null : trimmed;
}

/**
 * What a send would use, or null where it is not set up.
 *
 * Read at call time, inside the function that binds the secret: a secret read
 * anywhere else throws.
 */
export function dayReportSendConfig(): DayReportSendConfig | null {
  const phoneNumberId = configured(WHATSAPP_PHONE_NUMBER_ID.value());
  const recipient = configured(DAY_REPORT_RECIPIENT.value());
  if (!phoneNumberId || !recipient) return null;
  let accessToken: string | null = null;
  try {
    accessToken = configured(WHATSAPP_ACCESS_TOKEN.value());
  } catch {
    return null;
  }
  if (!accessToken) return null;
  return {
    accessToken,
    phoneNumberId,
    recipient,
    graphVersion: WHATSAPP_GRAPH_VERSION.value().trim() || "v23.0",
    templateName: DAY_REPORT_TEMPLATE.value().trim(),
    languageCode: DAY_REPORT_TEMPLATE_LANGUAGE.value().trim() || "en",
  };
}
