import {defineString} from "firebase-functions/params";

/**
 * Where UzaPay's email receipts are sent from, and where their way out lives.
 *
 * **The account emails' Brevo account and sender.** The API key, the sender
 * address and the recipient keyring are the ones `email/config.ts` already
 * binds; a receipt only changes the name a customer's inbox shows, which is the
 * business's (`emailReceiptSenderName`).
 *
 * **Inert where those are not set up.** A delivery with no usable key, sender
 * or keyring is written as `skipped: not_configured` and nothing is sent -
 * which is every emulator run, whose `.env.local` holds placeholders on
 * purpose.
 */

export const EMAIL_RECEIPT_TASK_FUNCTION = "deliverEmailReceipt";

/**
 * The page a customer stops email receipts on, without its query.
 *
 * **A Hosting rewrite onto `unsubscribeEmailReceipts`** (`firebase.json`), so
 * the link in every receipt is on UzaPay's own domain rather than a Cloud Run
 * hostname a spam filter has never seen. Empty sends receipts with no link and
 * no `List-Unsubscribe` header - which is a receipt a customer can only stop by
 * asking the shop, so leave it empty only where nothing is really sent.
 *
 * Written out in both `.env` files for the reason `whatsapp/config.ts` gives:
 * the CLI prompts for a parameter it cannot resolve, default or not.
 */
export const EMAIL_RECEIPT_UNSUBSCRIBE_URL = defineString(
  "EMAIL_RECEIPT_UNSUBSCRIBE_URL",
  {default: ""}
);
