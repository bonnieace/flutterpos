import {defineString} from "firebase-functions/params";

/**
 * The origin every Firebase email action link is moved onto, for example
 * `https://auth.uzapay.co.ke`. Empty leaves the links exactly as Auth made them.
 *
 * **Why this is not the console's "Action URL".** That setting lives in the
 * project's email template configuration, and Firebase refuses template edits
 * on this project (`EMAIL_TEMPLATE_UPDATE_NOT_ALLOWED`, seen 2026-09-27). The
 * emails are sent by this code through Brevo, not by Firebase, so nothing needs
 * the template - only the host of the link it hands back. Any Firebase Hosting
 * domain of the same project serves the same `/__/auth/action` handler, so the
 * path and every query parameter (the one-time code, the API key, the continue
 * URL) carry over unchanged.
 *
 * The origin must be a Hosting domain of this project and listed under Auth ->
 * Settings -> Authorized domains, or the handler page will refuse the code.
 */
export const AUTH_ACTION_LINK_ORIGIN = defineString("AUTH_ACTION_LINK_ORIGIN", {
  default: "",
});

const ACTION_HANDLER_PATH = "/__/auth/action";

/** Moves a Firebase action link onto [origin]; any other link is returned as is. */
export function rehostActionLink(link: string, origin: string): string {
  if (origin === "") return link;
  const target = new URL(origin);
  if (
    target.protocol !== "https:" ||
    target.pathname !== "/" ||
    target.search !== "" ||
    target.hash !== ""
  ) {
    throw new Error("AUTH_ACTION_LINK_ORIGIN must be an HTTPS origin with no path.");
  }
  const url = new URL(link);
  if (url.pathname !== ACTION_HANDLER_PATH) return link;
  url.protocol = target.protocol;
  url.host = target.host;
  return url.toString();
}
