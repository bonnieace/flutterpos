/**
 * The one place an outgoing email decides what it looks like.
 *
 * **Every template renders through here, and none of them writes a colour.**
 * Before this file existed, four emails carried four hand-written `<p>` tags in
 * two different modules, and the only thing they had in common was that neither
 * looked like the app. The palette below is the app's own - `AppColorRoles`
 * `profoundVerdant` in `lib/ui/tokens.dart`, value for value - so an email and
 * the screen it hands off to are the same product.
 *
 * **Email is not a browser and this file assumes the worst one.** Three rules
 * follow from that and every helper below obeys them:
 *
 * 1. **Layout is tables and paint is inline.** The `<style>` block carries only
 *    what a stripped client can afford to lose - the mobile media query and the
 *    forced-dark-mode overrides. A client that drops it still gets the finished
 *    design, because every colour, size and space is also on the element.
 * 2. **The call to action is drawn twice.** Outlook renders through Word, which
 *    has no padding on an anchor and no border radius, so the button is a VML
 *    roundrect there and an anchor everywhere else. Conditional comments keep
 *    each client seeing exactly one of them.
 * 3. **No image, no web font, no tracker.** An image the recipient must agree
 *    to load is a design that arrives broken by default, and the send path sets
 *    `X-Mailin-Track-Clicks: 0` deliberately. The mark is drawn in table cells
 *    and the type is a stack, headed by the family the app bundles for anyone
 *    whose client already has it.
 */

/** The wordmark. Its first letter is also the mark, so a rename moves both. */
export const BRAND_NAME = "ChillTent";

/**
 * `AppColorRoles.profoundVerdant`, transcribed.
 *
 * The names are the roles' names rather than the primitives', so a value that
 * moves in `lib/ui/tokens.dart` has one obvious line to move to here.
 */
export const brandPalette = {
  canvas: "#03110B",
  surface: "#071610",
  card: "#0D1F16",
  elevated: "#132A1F",
  raised: "#283831",
  ink: "#D4E7DD",
  muted: "#BCCBB9",
  outline: "#869585",
  hairline: "#3D4A3D",
  primary: "#4BE277",
  primaryBright: "#6BFF8F",
  primaryContainer: "#22C55E",
  onPrimary: "#003915",
  secondary: "#B0CDBD",
  critical: "#EF4444",
  warning: "#F2C14E",
  info: "#6FB7F2",
} as const;

/**
 * Hanken Grotesk first, for the minority of clients that already hold it, then
 * the grotesques a mail client is actually likely to have. The fallbacks are
 * ordered by how close their x-height and terminals sit to the real family, so
 * the layout does not reflow between one recipient and the next.
 */
const INTERFACE_STACK = "'Hanken Grotesk', 'Segoe UI', Roboto, " +
  "-apple-system, BlinkMacSystemFont, 'Helvetica Neue', Arial, sans-serif";

/** The app's figure and identifier family, with the same treatment. */
const MONO_STACK = "'JetBrains Mono', ui-monospace, SFMono-Regular, " +
  "'Cascadia Mono', Consolas, 'Liberation Mono', monospace";

export type BrandTone = "primary" | "critical" | "warning" | "info";

export interface BrandedAction {
  label: string;
  url: string;
}

/** A tinted panel for the one thing the recipient must not skim past. */
export interface BrandedNotice {
  tone: BrandTone;
  title: string;
  body: string;
}

export interface BrandedEmail {
  /**
   * The snippet an inbox prints beside the subject. It is the second thing a
   * recipient reads and the first thing most templates leave to chance.
   */
  preheader: string;
  eyebrow: string;
  title: string;
  lead: string;
  body?: string[];
  steps?: string[];
  action?: BrandedAction;
  notice?: BrandedNotice;
  footnote: string;
}

export function htmlEscape(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function toneColour(tone: BrandTone): string {
  if (tone === "critical") return brandPalette.critical;
  if (tone === "warning") return brandPalette.warning;
  if (tone === "info") return brandPalette.info;
  return brandPalette.primary;
}

const PARAGRAPH_STYLE = `margin:0;font-family:${INTERFACE_STACK};` +
  `font-size:15px;line-height:24px;color:${brandPalette.muted};`;

const LEAD_STYLE = `margin:0;font-family:${INTERFACE_STACK};font-size:17px;` +
  `line-height:27px;color:${brandPalette.ink};`;

function paragraphs(values: string[]): string {
  return values.map((value) =>
    `<tr><td style="padding-top:16px;"><p style="${PARAGRAPH_STYLE}">` +
    `${htmlEscape(value)}</p></td></tr>`
  ).join("");
}

/**
 * A numbered list drawn as table rows rather than an `<ol>`.
 *
 * Outlook indents a list by a margin it invents and Gmail's mobile client
 * clips the marker; a cell holding a mint numeral is the same design in every
 * client and costs one extra table.
 */
function steps(values: string[]): string {
  const rows = values.map((value, index) =>
    "<tr>" +
    `<td width="28" valign="top" style="padding:0 0 12px;` +
    `font-family:${MONO_STACK};font-size:13px;line-height:24px;` +
    `font-weight:500;color:${brandPalette.primary};">` +
    `${index + 1}.</td>` +
    `<td valign="top" style="padding:0 0 12px;` +
    `font-family:${INTERFACE_STACK};font-size:15px;line-height:24px;` +
    `color:${brandPalette.ink};">${htmlEscape(value)}</td>` +
    "</tr>"
  ).join("");
  return `<tr><td style="padding-top:20px;">` +
    `<table role="presentation" cellpadding="0" cellspacing="0" ` +
    `border="0" width="100%">${rows}</table></td></tr>`;
}

/**
 * The button, twice: a VML roundrect for Word-rendered Outlook and an anchor
 * for everything else, each inside the conditional comment that hides it from
 * the other.
 */
function actionButton(action: BrandedAction): string {
  const url = htmlEscape(action.url);
  const label = htmlEscape(action.label);
  return `<tr><td style="padding-top:32px;">` +
    `<table role="presentation" cellpadding="0" cellspacing="0" ` +
    `border="0"><tr><td align="center" ` +
    `bgcolor="${brandPalette.primary}" style="border-radius:12px;">` +
    "<!--[if mso]>" +
    `<v:roundrect xmlns:v="urn:schemas-microsoft-com:vml" ` +
    `xmlns:w="urn:schemas-microsoft-com:office:word" ` +
    `href="${url}" style="height:52px;v-text-anchor:middle;width:300px;" ` +
    `arcsize="24%" stroke="f" fillcolor="${brandPalette.primary}">` +
    `<w:anchorlock/><center style="color:${brandPalette.onPrimary};` +
    `font-family:'Segoe UI',Arial,sans-serif;font-size:16px;` +
    `font-weight:700;">${label}</center></v:roundrect>` +
    "<![endif]-->" +
    "<!--[if !mso]><!-->" +
    `<a class="cta" href="${url}" ` +
    `style="display:inline-block;padding:15px 32px;` +
    `font-family:${INTERFACE_STACK};font-size:16px;line-height:20px;` +
    `font-weight:700;letter-spacing:0.01em;color:${brandPalette.onPrimary};` +
    `background-color:${brandPalette.primary};border-radius:12px;` +
    `text-decoration:none;mso-hide:all;">${label}</a>` +
    "<!--<![endif]-->" +
    "</td></tr></table></td></tr>";
}

/**
 * The same link again, spelled out.
 *
 * A corporate gateway that rewrites or strips the button leaves the recipient
 * with nothing to act on, and the address is also the only way they can check
 * where the mail is actually sending them before they go.
 */
function actionFallback(action: BrandedAction): string {
  const url = htmlEscape(action.url);
  return `<tr><td style="padding-top:28px;">` +
    `<p style="${PARAGRAPH_STYLE}font-size:13px;line-height:20px;">` +
    "Button not working? Copy this address into your browser:</p>" +
    "</td></tr>" +
    `<tr><td style="padding-top:10px;">` +
    `<table role="presentation" cellpadding="0" cellspacing="0" ` +
    `border="0" width="100%"><tr>` +
    `<td bgcolor="${brandPalette.surface}" style="padding:14px 16px;` +
    `border:1px solid ${brandPalette.hairline};border-radius:10px;` +
    `font-family:${MONO_STACK};font-size:12px;line-height:20px;` +
    `word-break:break-all;overflow-wrap:break-word;">` +
    `<a href="${url}" style="color:${brandPalette.primary};` +
    `text-decoration:none;word-break:break-all;">${url}</a>` +
    "</td></tr></table></td></tr>";
}

/** A left rule in the tone's colour over a barely-there wash of the same. */
function noticePanel(notice: BrandedNotice): string {
  const colour = toneColour(notice.tone);
  return `<tr><td style="padding-top:32px;">` +
    `<table role="presentation" cellpadding="0" cellspacing="0" ` +
    `border="0" width="100%"><tr>` +
    `<td bgcolor="${brandPalette.elevated}" style="padding:18px 20px;` +
    `border-left:3px solid ${colour};border-radius:4px 10px 10px 4px;">` +
    `<p style="margin:0 0 6px;font-family:${INTERFACE_STACK};` +
    `font-size:13px;line-height:18px;font-weight:700;letter-spacing:0.06em;` +
    `text-transform:uppercase;color:${colour};">` +
    `${htmlEscape(notice.title)}</p>` +
    `<p style="${PARAGRAPH_STYLE}color:${brandPalette.ink};font-size:14px;` +
    `line-height:22px;">${htmlEscape(notice.body)}</p>` +
    "</td></tr></table></td></tr>";
}

/**
 * The wordmark: a mint tile carrying the brand's initial, beside the name in
 * tracked caps. Outlook squares off the tile's corners and nothing else about
 * it changes, which is the whole reason the mark is a letter in a cell rather
 * than a shape that has to be a picture.
 */
function masthead(): string {
  return `<tr><td style="padding:0 0 28px;">` +
    `<table role="presentation" cellpadding="0" cellspacing="0" ` +
    `border="0"><tr>` +
    `<td width="40" height="40" align="center" valign="middle" ` +
    `bgcolor="${brandPalette.primary}" style="width:40px;height:40px;` +
    `border-radius:11px;font-family:${INTERFACE_STACK};font-size:20px;` +
    `line-height:40px;font-weight:700;color:${brandPalette.onPrimary};">` +
    `${htmlEscape(BRAND_NAME.slice(0, 1))}</td>` +
    `<td style="padding-left:12px;` +
    `font-family:${INTERFACE_STACK};font-size:15px;line-height:40px;` +
    `font-weight:600;letter-spacing:0.14em;text-transform:uppercase;` +
    `color:${brandPalette.ink};">${htmlEscape(BRAND_NAME)}</td>` +
    "</tr></table></td></tr>";
}

/**
 * Progressive enhancement only.
 *
 * The mobile query tightens the gutters and stretches the button; the
 * `[data-ogsc]` and `[data-ogsb]` selectors are Outlook.com's dark mode, which
 * repaints a palette it thinks is light and has to be told this one is not.
 * Losing all of it costs the design nothing a recipient would name.
 */
const PROGRESSIVE_STYLES = `
    :root { color-scheme: dark; supported-color-schemes: dark; }
    body { margin: 0 !important; padding: 0 !important; width: 100% !important; }
    table { border-collapse: collapse; }
    a { color: ${brandPalette.primary}; }
    .cta:hover { background-color: ${brandPalette.primaryBright} !important; }
    [data-ogsc] .ink { color: ${brandPalette.ink} !important; }
    [data-ogsc] .muted { color: ${brandPalette.outline} !important; }
    [data-ogsb] .canvas { background-color: ${brandPalette.canvas} !important; }
    [data-ogsb] .card { background-color: ${brandPalette.card} !important; }
    @media only screen and (max-width: 600px) {
      .gutter { padding-left: 16px !important; padding-right: 16px !important; }
      .pad { padding: 28px 22px !important; }
      .title { font-size: 26px !important; line-height: 34px !important; }
      .cta { display: block !important; text-align: center !important; }
    }`;

export function renderBrandedEmailHtml(email: BrandedEmail): string {
  const sections = [
    masthead(),
    "<tr><td>" +
      `<p style="margin:0;font-family:${INTERFACE_STACK};font-size:12px;` +
      `line-height:16px;font-weight:700;letter-spacing:0.12em;` +
      `text-transform:uppercase;color:${brandPalette.primary};">` +
      `${htmlEscape(email.eyebrow)}</p></td></tr>`,
    `<tr><td style="padding-top:12px;">` +
      `<h1 class="title ink" style="margin:0;font-family:${INTERFACE_STACK};` +
      `font-size:30px;line-height:38px;font-weight:700;` +
      `letter-spacing:-0.02em;color:${brandPalette.ink};">` +
      `${htmlEscape(email.title)}</h1></td></tr>`,
    `<tr><td style="padding-top:14px;">` +
      `<p class="ink" style="${LEAD_STYLE}">${htmlEscape(email.lead)}</p>` +
      "</td></tr>",
    email.body?.length ? paragraphs(email.body) : "",
    email.steps?.length ? steps(email.steps) : "",
    email.action ? actionButton(email.action) : "",
    email.action ? actionFallback(email.action) : "",
    email.notice ? noticePanel(email.notice) : "",
  ].join("");

  // A run of zero-width joiners, which is the only reliable way to stop Gmail
  // padding the preview snippet with the first words of the body.
  const preheaderPadding = "&#847;&zwnj;&nbsp;".repeat(60);

  return `<!doctype html>
<html lang="en" dir="ltr" xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="x-ua-compatible" content="ie=edge">
<meta name="x-apple-disable-message-reformatting">
<meta name="color-scheme" content="dark">
<meta name="supported-color-schemes" content="dark">
<title>${htmlEscape(email.title)}</title>
<!--[if mso]>
<noscript><xml><o:OfficeDocumentSettings><o:PixelsPerInch>96</o:PixelsPerInch></o:OfficeDocumentSettings></xml></noscript>
<![endif]-->
<style>${PROGRESSIVE_STYLES}
</style>
</head>
<body class="canvas" style="margin:0;padding:0;width:100%;background-color:${brandPalette.canvas};">
<div style="display:none;max-height:0;overflow:hidden;mso-hide:all;font-size:1px;line-height:1px;color:${brandPalette.canvas};opacity:0;">${htmlEscape(email.preheader)}${preheaderPadding}</div>
<table role="presentation" class="canvas" cellpadding="0" cellspacing="0" border="0" width="100%" bgcolor="${brandPalette.canvas}" style="background-color:${brandPalette.canvas};">
<tr><td class="gutter" align="center" style="padding:40px 24px;">
<!--[if mso]><table role="presentation" cellpadding="0" cellspacing="0" border="0" width="600"><tr><td><![endif]-->
<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="600" style="width:100%;max-width:600px;">
<tr><td class="card pad" bgcolor="${brandPalette.card}" style="padding:40px;background-color:${brandPalette.card};border:1px solid ${brandPalette.hairline};border-radius:18px;">
<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%">${sections}</table>
</td></tr>
<tr><td style="padding:24px 8px 0;">
<p class="muted" style="margin:0;font-family:${INTERFACE_STACK};font-size:12px;line-height:19px;color:${brandPalette.outline};">${htmlEscape(email.footnote)}</p>
<p class="muted" style="margin:12px 0 0;font-family:${INTERFACE_STACK};font-size:12px;line-height:19px;color:${brandPalette.outline};">Sent by ${htmlEscape(BRAND_NAME)}. This message carries no tracking pixel and no click tracking.</p>
</td></tr>
</table>
<!--[if mso]></td></tr></table><![endif]-->
</td></tr>
</table>
</body>
</html>`;
}

/**
 * The same content as text, for the part of the alternative that gets read.
 *
 * It is written out rather than stripped from the markup: a regex over the HTML
 * would carry the button's label and its URL as two unrelated fragments, and
 * the plain part is what a text-only client announces.
 */
export function renderBrandedEmailText(email: BrandedEmail): string {
  const lines: string[] = [
    BRAND_NAME.toUpperCase(),
    "",
    email.title,
    "",
    email.lead,
  ];
  for (const paragraph of email.body ?? []) lines.push("", paragraph);
  if (email.steps?.length) {
    lines.push("");
    email.steps.forEach((step, index) => lines.push(`${index + 1}. ${step}`));
  }
  if (email.action) {
    lines.push("", `${email.action.label}:`, email.action.url);
  }
  if (email.notice) {
    lines.push("", `${email.notice.title.toUpperCase()}: ${email.notice.body}`);
  }
  lines.push("", email.footnote);
  return lines.join("\n");
}
