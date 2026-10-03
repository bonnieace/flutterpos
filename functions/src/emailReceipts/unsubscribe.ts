import {createHmac, timingSafeEqual} from "node:crypto";
import {FieldValue} from "firebase-admin/firestore";
import type {Firestore} from "firebase-admin/firestore";
import {BRAND_NAME, brandPalette, htmlEscape} from "../email/branding";
import {hashRecipient, suppressionDocumentId} from "../email/recipientHash";
import type {RecipientHash, RecipientHmacKeyring} from "../email/recipientHash";

/**
 * The way out of email receipts: WhatsApp's STOP, for an inbox.
 *
 * **One link per receipt, naming the address without containing it.** The
 * token is the address's keyed digest (`email/recipientHash.ts`) and a
 * signature over it, so the page can stop receipts to that address and could
 * not tell anybody what the address is.
 *
 * **Stopping is for every shop**, as STOP is: a customer who no longer wants
 * receipts by email from shops using UzaPay should not have to unsubscribe
 * from each one. It is its own list, `email_receipt_suppressions`, rather than
 * `email_suppressions`: that list is bounces and complaints, and it stops
 * password resets too - which nobody who declined a receipt meant to stop.
 *
 * **A link opens a question; only a POST answers it.** Mail scanners and
 * link previewers fetch every URL in a message, and a GET that unsubscribed
 * would unsubscribe people who never clicked. The mail client's own one-click
 * (`List-Unsubscribe-Post`, RFC 8058) is a POST, and so is the button.
 */

export const EMAIL_RECEIPT_SUPPRESSIONS = "email_receipt_suppressions";

const TOKEN_PREFIX = "r1";
const SIGNATURE_LABEL = "email-receipt-unsubscribe";

function signature(keyVersion: string, recipientHash: string, secret: string): string {
  return createHmac("sha256", secret)
    .update([SIGNATURE_LABEL, keyVersion, recipientHash].join("\u0000"), "utf8")
    .digest("base64url");
}

/** The token one receipt's link carries, for [recipient]. */
export function emailReceiptUnsubscribeToken(
  recipient: RecipientHash,
  keyring: RecipientHmacKeyring
): string {
  const secret = keyring.keys[recipient.keyVersion];
  return [
    TOKEN_PREFIX,
    recipient.keyVersion,
    recipient.recipientHash,
    signature(recipient.keyVersion, recipient.recipientHash, secret),
  ].join(".");
}

/** The link itself, or undefined where no page is set up. */
export function emailReceiptUnsubscribeUrl(
  baseUrl: string,
  normalizedEmail: string,
  keyring: RecipientHmacKeyring
): string | undefined {
  if (!baseUrl.startsWith("https://") && !baseUrl.startsWith("http://localhost")) {
    return undefined;
  }
  let url: URL;
  try {
    url = new URL(baseUrl);
  } catch {
    // A setting that is not a URL leaves the link out rather than holding
    // every receipt in a retry loop it can never leave.
    return undefined;
  }
  url.searchParams.set(
    "t",
    emailReceiptUnsubscribeToken(hashRecipient(normalizedEmail, keyring), keyring)
  );
  return url.toString();
}

/**
 * The recipient a token names, or null for one this keyring did not sign.
 *
 * A token signed with a key since rotated out of the keyring is refused: its
 * receipt is older than every key still held, and its customer has had newer
 * receipts with working links since.
 */
export function readEmailReceiptUnsubscribeToken(
  token: unknown,
  keyring: RecipientHmacKeyring
): RecipientHash | null {
  if (typeof token !== "string" || token.length > 256) return null;
  const parts = token.split(".");
  if (parts.length !== 4 || parts[0] !== TOKEN_PREFIX) return null;
  const [, keyVersion, recipientHash, supplied] = parts;
  const secret = keyring.keys[keyVersion];
  if (!secret || !/^[A-Za-z0-9_-]{16,128}$/.test(recipientHash)) return null;
  const expected = Buffer.from(signature(keyVersion, recipientHash, secret), "utf8");
  const given = Buffer.from(supplied, "utf8");
  if (expected.length !== given.length || !timingSafeEqual(expected, given)) {
    return null;
  }
  return {
    keyVersion,
    recipientHash,
    documentId: suppressionDocumentId(keyVersion, recipientHash),
  };
}

export type UnsubscribeAction = "stop" | "resume";

/** Stops, or restarts, email receipts to [recipient]. */
export async function applyEmailReceiptUnsubscribe(
  db: Firestore,
  recipient: RecipientHash,
  action: UnsubscribeAction,
  via: "page" | "one_click"
): Promise<void> {
  const ref = db.collection(EMAIL_RECEIPT_SUPPRESSIONS).doc(recipient.documentId);
  if (action === "resume") {
    await ref.delete();
    return;
  }
  await ref.set({
    recipientHash: recipient.recipientHash,
    recipientHashKeyVersion: recipient.keyVersion,
    via,
    at: FieldValue.serverTimestamp(),
  });
}

export type UnsubscribePage = "confirm" | "stopped" | "resumed" | "invalid";

/**
 * The page a customer lands on, in the emails' colours.
 *
 * **One self-contained document**: inline styles, the hosted logo and no
 * script. The form posts back to the same address, token and all, which is the
 * one thing the Content-Security-Policy the handler sends allows it to do.
 */
export function renderUnsubscribePage(page: UnsubscribePage, token: string): string {
  const copy = {
    confirm: {
      title: "Stop email receipts?",
      body: "Shops that use " + BRAND_NAME + " will stop emailing receipts to " +
        "this address. You can still ask for a paper receipt at the counter.",
      button: {label: "Stop email receipts", action: "stop"},
    },
    stopped: {
      title: "Email receipts stopped",
      body: "No more receipts will be emailed to this address. Changed your " +
        "mind? You can turn them back on.",
      button: {label: "Turn email receipts back on", action: "resume"},
    },
    resumed: {
      title: "Email receipts are back on",
      body: "Shops that use " + BRAND_NAME + " can email receipts to this " +
        "address again, when you ask them to.",
      button: undefined,
    },
    invalid: {
      title: "This link does not work",
      body: "It may be incomplete, or from an old receipt. Use the link in " +
        "your most recent email receipt instead.",
      button: undefined,
    },
  }[page];
  const palette = brandPalette;
  const font = "'DM Sans','Segoe UI',Roboto,-apple-system,BlinkMacSystemFont," +
    "'Helvetica Neue',Arial,sans-serif";
  const heading = "'Space Grotesk','Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif";
  const form = copy.button ?
    `<form method="post" action="?t=${htmlEscape(encodeURIComponent(token))}">` +
    `<input type="hidden" name="action" value="${copy.button.action}">` +
    `<button type="submit">${htmlEscape(copy.button.label)}</button></form>` :
    "";
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>${htmlEscape(copy.title)} - ${BRAND_NAME}</title>
<style>
  body { margin: 0; background: ${palette.canvas}; color: ${palette.ink}; font-family: ${font}; }
  main { max-width: 520px; margin: 40px auto; padding: 0 16px; }
  header { background: ${palette.onPrimary}; border-radius: 18px 18px 0 0; padding: 26px 32px; }
  header img { display: block; width: 140px; height: auto; }
  section { background: ${palette.card}; border: 1px solid ${palette.hairline}; border-top: 0; border-radius: 0 0 18px 18px; padding: 32px; }
  h1 { margin: 0 0 12px; font-family: ${heading}; font-size: 26px; line-height: 34px; letter-spacing: -0.02em; }
  p { margin: 0; font-size: 16px; line-height: 26px; color: ${palette.muted}; }
  form { margin: 28px 0 0; }
  button { min-height: 48px; padding: 12px 28px; border: 0; border-radius: 12px; background: ${palette.primary}; color: ${palette.onPrimary}; font: 700 16px/20px ${font}; cursor: pointer; }
  button:hover { background: ${palette.primaryBright}; }
  button:focus-visible { outline: 3px solid ${palette.secondary}; outline-offset: 3px; }
  @media (max-width: 480px) { section { padding: 24px 20px; } button { width: 100%; } }
</style>
</head>
<body>
<main>
<header><img src="https://uzapay.co.ke/assets/brand/uzapay-logo.webp" alt="${BRAND_NAME}" width="140"></header>
<section>
<h1>${htmlEscape(copy.title)}</h1>
<p>${htmlEscape(copy.body)}</p>
${form}
</section>
</main>
</body>
</html>`;
}

/** What the page may do, and nothing else. */
export const UNSUBSCRIBE_PAGE_POLICY = "default-src 'none'; " +
  "style-src 'unsafe-inline'; img-src https://uzapay.co.ke; " +
  "form-action 'self'; frame-ancestors 'none'; base-uri 'none'";
