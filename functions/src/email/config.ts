import {defineSecret, defineString} from "firebase-functions/params";

/**
 * JSON keyring, for example:
 * {"currentVersion":"v2","keys":{"v2":"...32+ bytes...","v1":"..."}}
 *
 * Keeping previous keys in the same secret permits suppression lookups across a
 * planned rotation without placing recipient addresses in Firestore.
 */
export const EMAIL_RECIPIENT_HMAC_KEYRING = defineSecret(
  "EMAIL_RECIPIENT_HMAC_KEYRING"
);

// This is intentionally the same deployed secret used by staff invitation email.
export const EMAIL_BREVO_API_KEY = defineSecret("BREVO_API_KEY");
export const EMAIL_BREVO_WEBHOOK_SECRET = defineSecret(
  "BREVO_WEBHOOK_SECRET"
);

export const EMAIL_SENDER_ADDRESS = defineString("EMAIL_SENDER_ADDRESS");
export const EMAIL_SENDER_NAME = defineString("EMAIL_SENDER_NAME", {
  default: "ChillTent",
});
export const PASSWORD_RESET_CONTINUE_URL = defineString(
  "PASSWORD_RESET_CONTINUE_URL"
);
export const EMAIL_VERIFICATION_CONTINUE_URL = defineString(
  "EMAIL_VERIFICATION_CONTINUE_URL"
);
export const PLATFORM_ALERTS_URL = defineString("PLATFORM_ALERTS_URL");

export const PASSWORD_RESET_TASK_FUNCTION = "deliverPasswordReset";
export const ACCOUNT_VERIFICATION_TASK_FUNCTION = "deliverAccountVerification";
export const PLATFORM_ALERT_TASK_FUNCTION = "deliverPlatformAlertNotification";
export const EMAIL_UNAVAILABLE_MESSAGE =
  "Email delivery unavailable. Check the address or contact support.";
