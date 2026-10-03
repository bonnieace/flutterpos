/**
 * What one business has chosen for its email receipts.
 *
 * `tenants/{tenantId}/configuration/email_receipts`, written by an owner or
 * administrator from the Email tile. **Its own document, not a field on
 * `e_receipts`**: the WhatsApp screen writes that one whole, and a till
 * running a build from before email receipts would write it without them.
 *
 * Absent or unreadable means off: a business that never chose to send
 * receipts by email sends none.
 */

export type EmailReceiptMode = "automatic" | "manual";

export interface EmailReceiptSettings {
  emailEnabled: boolean;
  /** Sent on its own to customers who agreed, or only when a cashier sends. */
  mode: EmailReceiptMode;
}

export const EMAIL_RECEIPTS_OFF: EmailReceiptSettings = {
  emailEnabled: false,
  mode: "manual",
};

export function readEmailReceiptSettings(data: unknown): EmailReceiptSettings {
  if (!data || typeof data !== "object") return EMAIL_RECEIPTS_OFF;
  const record = data as Record<string, unknown>;
  if (typeof record.emailEnabled !== "boolean") return EMAIL_RECEIPTS_OFF;
  return {
    emailEnabled: record.emailEnabled,
    mode: record.mode === "automatic" ? "automatic" : "manual",
  };
}
