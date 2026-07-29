import {defineSecret} from "firebase-functions/params";
import {HttpsError} from "firebase-functions/v2/https";

export const STAFF_INVITATION_HMAC_SECRET = defineSecret(
  "STAFF_INVITATION_HMAC_SECRET_V1"
);

export function invitationHmacSecretValue(): string {
  const value = STAFF_INVITATION_HMAC_SECRET.value();
  if (Buffer.byteLength(value, "utf8") < 32) {
    throw new HttpsError(
      "failed-precondition",
      "Staff invitation proof is not configured."
    );
  }
  return value;
}
