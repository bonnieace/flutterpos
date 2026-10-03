import {postBrevoEmail} from "../email/brevoProvider";
import {EmailProviderError} from "../email/contracts";
import type {EmailReceiptMessage, EmailReceiptSend} from "./deliveries";

type FetchLike = typeof fetch;

/**
 * Brevo, as an email receipt reaches it.
 *
 * **Tracking off, as on every UzaPay email**: no open pixel and no rewritten
 * links, so the footer's promise holds and the unsubscribe link is the address
 * it says it is. **The PDF attached**, by content rather than by URL, so the
 * receipt arrives whole whether or not anything is hosted.
 *
 * **`List-Unsubscribe` with one-click**, which is how Gmail and Apple Mail draw
 * their own *Unsubscribe* beside the sender - and a receipt a mail client can
 * unsubscribe from is one that does not get reported as spam instead.
 */
export function brevoEmailReceiptSend(
  config: {apiKey: string; senderAddress: string},
  fetchImplementation: FetchLike = fetch
): EmailReceiptSend {
  return async (message: EmailReceiptMessage): Promise<string> => {
    if (
      Buffer.byteLength(config.apiKey, "utf8") < 16 ||
      !config.senderAddress.includes("@")
    ) {
      throw new EmailProviderError("provider_not_configured", false);
    }
    const headers: Record<string, string> = {
      "Idempotency-Key": message.deliveryId,
      "X-Mailin-Track-Clicks": "0",
      "X-Mailin-Track-Opens": "0",
    };
    if (message.unsubscribeUrl) {
      headers["List-Unsubscribe"] = `<${message.unsubscribeUrl}>`;
      headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click";
    }
    return postBrevoEmail(config.apiKey, {
      sender: {email: config.senderAddress, name: message.senderName},
      to: [{email: message.to}],
      subject: message.subject,
      textContent: message.text,
      htmlContent: message.html,
      attachment: [{
        name: message.attachment.name,
        content: Buffer.from(message.attachment.content).toString("base64"),
      }],
      headers,
      tags: ["email-receipt"],
    }, fetchImplementation);
  };
}
