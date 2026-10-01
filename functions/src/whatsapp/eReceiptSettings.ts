/**
 * What one business has chosen for its WhatsApp receipts.
 *
 * `tenants/{tenantId}/configuration/e_receipts`, written by an owner or
 * administrator from the WhatsApp tile. Absent or unreadable means off: a
 * business that never chose to send receipts sends none.
 */

export type ReceiptFormat = "pdf" | "summary";
export type ReceiptMode = "automatic" | "manual";

export interface EReceiptSettings {
  whatsappEnabled: boolean;
  /** Sent on its own to customers who agreed, or only when a cashier sends. */
  mode: ReceiptMode;
  /** The receipt attached as a PDF, or its totals in the message. */
  format: ReceiptFormat;
}

export const E_RECEIPTS_OFF: EReceiptSettings = {
  whatsappEnabled: false,
  mode: "manual",
  format: "pdf",
};

export function readEReceiptSettings(data: unknown): EReceiptSettings {
  if (!data || typeof data !== "object") return E_RECEIPTS_OFF;
  const record = data as Record<string, unknown>;
  if (typeof record.whatsappEnabled !== "boolean") return E_RECEIPTS_OFF;
  const mode = record.mode === "automatic" ? "automatic" : "manual";
  const format = record.format === "summary" ? "summary" : "pdf";
  return {whatsappEnabled: record.whatsappEnabled, mode, format};
}
