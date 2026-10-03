/** Shared UzaPay email layout, matching the approved landing-page identity.
 * Table layouts, inline styles and Outlook VML preserve the action in mail clients.
 * The hosted logo has a text alternative; no external fonts or trackers are loaded.
 */
export const BRAND_NAME = "UzaPay";

/** Landing-page colours, with darker text accents on the light email surface. */
export const brandPalette = {
  canvas: "#f8f8f4",
  surface: "#f3f5ef",
  card: "#ffffff",
  elevated: "#f3f5ef",
  raised: "#dbe1da",
  ink: "#0e1511",
  muted: "#536158",
  outline: "#667269",
  hairline: "#dbe1da",
  primary: "#c8ff5f",
  primaryBright: "#d4ff7f",
  primaryContainer: "#c8ff5f",
  onPrimary: "#0c1510",
  secondary: "#355c49",
  critical: "#b42318",
  warning: "#87600d",
  info: "#355c49",
} as const;

/** Landing-page font names with installed system fallbacks. */
const INTERFACE_STACK = "'DM Sans', 'Segoe UI', Roboto, " +
  "-apple-system, BlinkMacSystemFont, 'Helvetica Neue', Arial, sans-serif";

const HEADING_STACK = "'Space Grotesk', 'Segoe UI', Roboto, " +
  "'Helvetica Neue', Arial, sans-serif";

/** Monospace fallback links and step numbers. */
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

/** One labelled figure on a receipt: its date, who served, a total. */
export interface BrandedFact {
  label: string;
  value: string;
  /** Drawn larger and bold, for the one figure the reader is looking for. */
  emphasis?: boolean;
}

/** One line of a receipt: what was bought, at what, and what it came to. */
export interface BrandedLineItem {
  description: string;
  /** The smaller line under it - the unit price, the SKU. */
  detail?: string;
  amount: string;
}

/**
 * An itemised record, in the paper receipt's order: whose it is and when,
 * what was bought, and what it came to.
 *
 * **Only the receipt email draws one.** The account emails carry a single
 * action and nothing to itemise, and render exactly as they did before this
 * block existed.
 */
export interface BrandedReceipt {
  heading: string;
  subheading?: string;
  facts: BrandedFact[];
  items: BrandedLineItem[];
  totals: BrandedFact[];
  closing?: string;
}

/** A link in the footer: the way out of messages the reader keeps getting. */
export interface BrandedFooterLink {
  text: string;
  label: string;
  url: string;
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
  receipt?: BrandedReceipt;
  body?: string[];
  steps?: string[];
  action?: BrandedAction;
  notice?: BrandedNotice;
  footnote: string;
  footerLink?: BrandedFooterLink;
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
  return brandPalette.secondary;
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
    `font-weight:500;color:${brandPalette.secondary};">` +
    `${index + 1}.</td>` +
    `<td valign="top" style="padding:0 0 12px;` +
    `font-family:${INTERFACE_STACK};font-size:15px;line-height:24px;` +
    `color:${brandPalette.ink};">${htmlEscape(value)}</td>` +
    "</tr>"
  ).join("");
  return `<tr><td style="padding-top:20px;">` +
    `<table role="presentation" cellpadding="0" cellspacing="0" ` +
    `border="0" width="100%" style="table-layout:fixed;">${rows}</table></td></tr>`;
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
    `border="0" width="100%" style="table-layout:fixed;"><tr>` +
    `<td bgcolor="${brandPalette.surface}" style="padding:14px 16px;` +
    `border:1px solid ${brandPalette.hairline};border-radius:10px;` +
    `font-family:${MONO_STACK};font-size:12px;line-height:20px;` +
    `word-break:break-all;overflow-wrap:break-word;">` +
    `<a href="${url}" style="color:${brandPalette.secondary};` +
    `text-decoration:none;word-break:break-all;">${url}</a>` +
    "</td></tr></table></td></tr>";
}

/** A left rule in the tone's colour over a barely-there wash of the same. */
function noticePanel(notice: BrandedNotice): string {
  const colour = toneColour(notice.tone);
  return `<tr><td style="padding-top:32px;">` +
    `<table role="presentation" cellpadding="0" cellspacing="0" ` +
    `border="0" width="100%" style="table-layout:fixed;"><tr>` +
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

const FACT_LABEL_STYLE = `font-family:${INTERFACE_STACK};font-size:14px;` +
  `line-height:22px;color:${brandPalette.muted};`;

const FACT_VALUE_STYLE = `font-family:${INTERFACE_STACK};font-size:14px;` +
  `line-height:22px;color:${brandPalette.ink};`;

const EMPHASIS_STYLE = `font-family:${HEADING_STACK};font-size:18px;` +
  `line-height:26px;font-weight:700;color:${brandPalette.ink};`;

/** Label left, value right; the value never wraps, the label may. */
function factRows(facts: BrandedFact[]): string {
  return facts.map((fact) => {
    const label = fact.emphasis ? EMPHASIS_STYLE : FACT_LABEL_STYLE;
    const value = fact.emphasis ? EMPHASIS_STYLE : FACT_VALUE_STYLE;
    const top = fact.emphasis ? 8 : 3;
    return "<tr>" +
      `<td valign="top" style="padding:${top}px 12px 3px 0;${label}">` +
      `${htmlEscape(fact.label)}</td>` +
      `<td valign="top" align="right" style="padding:${top}px 0 3px;` +
      `white-space:nowrap;${value}">${htmlEscape(fact.value)}</td>` +
      "</tr>";
  }).join("");
}

/** A dashed rule, the paper receipt's separator, as a one-row table. */
function receiptRule(): string {
  return '<tr><td style="padding:0 20px;">' +
    `<table role="presentation" cellpadding="0" cellspacing="0" border="0" ` +
    `width="100%"><tr><td style="border-top:1px dashed ${brandPalette.raised};` +
    'font-size:0;line-height:0;height:1px;">&nbsp;</td></tr></table>' +
    "</td></tr>";
}

/**
 * The receipt, boxed.
 *
 * **The inner tables are not fixed-layout**, unlike the rest of this file: an
 * amount is set `nowrap` and takes the width it needs, and the description
 * beside it wraps into what is left - which on a 320 px phone is the only
 * arrangement that keeps `KES 12,450.00` on one line.
 */
function receiptBlock(receipt: BrandedReceipt): string {
  const table = (rows: string) =>
    `<table role="presentation" cellpadding="0" cellspacing="0" border="0" ` +
    `width="100%">${rows}</table>`;
  const items = receipt.items.map((item) =>
    "<tr>" +
    `<td valign="top" style="padding:6px 12px 6px 0;` +
    `font-family:${INTERFACE_STACK};font-size:15px;line-height:22px;` +
    `color:${brandPalette.ink};">${htmlEscape(item.description)}` +
    (item.detail ?
      `<div style="font-size:13px;line-height:20px;color:${brandPalette.muted};">` +
      `${htmlEscape(item.detail)}</div>` :
      "") +
    "</td>" +
    `<td valign="top" align="right" style="padding:6px 0;white-space:nowrap;` +
    `font-family:${INTERFACE_STACK};font-size:15px;line-height:22px;` +
    `color:${brandPalette.ink};">${htmlEscape(item.amount)}</td>` +
    "</tr>"
  ).join("");
  return `<tr><td style="padding-top:28px;">` +
    `<table role="presentation" cellpadding="0" cellspacing="0" border="0" ` +
    `width="100%" style="table-layout:fixed;border-collapse:separate;` +
    `border:1px solid ${brandPalette.hairline};border-radius:14px;">` +
    `<tr><td style="padding:20px 20px 4px;">` +
    `<p style="margin:0;font-family:${HEADING_STACK};font-size:18px;` +
    `line-height:26px;font-weight:700;color:${brandPalette.ink};">` +
    `${htmlEscape(receipt.heading)}</p>` +
    (receipt.subheading ?
      `<p style="margin:2px 0 0;font-family:${INTERFACE_STACK};font-size:13px;` +
      `line-height:20px;color:${brandPalette.muted};">` +
      `${htmlEscape(receipt.subheading)}</p>` :
      "") +
    "</td></tr>" +
    `<tr><td style="padding:8px 20px 14px;">${table(factRows(receipt.facts))}</td></tr>` +
    receiptRule() +
    `<tr><td style="padding:10px 20px;">${table(items)}</td></tr>` +
    receiptRule() +
    `<tr><td style="padding:12px 20px 18px;">` +
    `${table(factRows(receipt.totals))}</td></tr>` +
    "</table>" +
    (receipt.closing ?
      `<p style="margin:14px 0 0;font-family:${INTERFACE_STACK};font-size:13px;` +
      `line-height:20px;text-align:center;color:${brandPalette.muted};">` +
      `${htmlEscape(receipt.closing)}</p>` :
      "") +
    "</td></tr>";
}

/** Approved UzaPay logo on the landing page's deep-green header. */
function masthead(): string {
  return '<tr><td bgcolor="#0c1510" ' +
    'style="padding:30px 40px;background-color:#0c1510;' +
    'border-radius:18px 18px 0 0;">' +
    '<img src="https://uzapay.co.ke/assets/brand/uzapay-logo.webp" ' +
    'width="160" alt="UzaPay" style="display:block;width:160px;' +
    'max-width:100%;height:auto;color:#f7f9f4;font-family:Arial,sans-serif;' +
    'font-size:24px;"></td></tr>';
}

/** Mobile spacing and explicit colours for clients that support overrides. */
const PROGRESSIVE_STYLES = `
    :root { color-scheme: light; supported-color-schemes: light; }
    body { margin: 0 !important; padding: 0 !important; width: 100% !important; }
    table { border-collapse: collapse; }
    a { color: ${brandPalette.secondary}; }
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

/** The footer's one link, underlined so it reads as a link without colour. */
function footerLink(link: BrandedFooterLink): string {
  return `<p class="muted" style="margin:12px 0 0;font-family:${INTERFACE_STACK};` +
    `font-size:12px;line-height:19px;color:${brandPalette.outline};">` +
    `${htmlEscape(link.text)} <a href="${htmlEscape(link.url)}" ` +
    `style="color:${brandPalette.secondary};text-decoration:underline;">` +
    `${htmlEscape(link.label)}</a></p>\n`;
}

export function renderBrandedEmailHtml(email: BrandedEmail): string {
  const sections = [
    "<tr><td>" +
      `<p style="margin:0;font-family:${INTERFACE_STACK};font-size:12px;` +
      `line-height:16px;font-weight:700;letter-spacing:0.12em;` +
      `text-transform:uppercase;color:${brandPalette.secondary};">` +
      `${htmlEscape(email.eyebrow)}</p></td></tr>`,
    `<tr><td style="padding-top:12px;">` +
      `<h1 class="title ink" style="margin:0;font-family:${HEADING_STACK};` +
      `font-size:30px;line-height:38px;font-weight:700;` +
      `letter-spacing:-0.02em;color:${brandPalette.ink};">` +
      `${htmlEscape(email.title)}</h1></td></tr>`,
    `<tr><td style="padding-top:14px;">` +
      `<p class="ink" style="${LEAD_STYLE}">${htmlEscape(email.lead)}</p>` +
      "</td></tr>",
    email.receipt ? receiptBlock(email.receipt) : "",
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
<meta name="color-scheme" content="light">
<meta name="supported-color-schemes" content="light">
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
<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="600" style="width:100%;max-width:600px;table-layout:fixed;">
${masthead()}
<tr><td class="card pad" bgcolor="${brandPalette.card}" style="padding:40px;background-color:${brandPalette.card};border:1px solid ${brandPalette.hairline};border-radius:0 0 18px 18px;">
<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="table-layout:fixed;">${sections}</table>
</td></tr>
<tr><td style="padding:24px 8px 0;">
<p class="muted" style="margin:0;font-family:${INTERFACE_STACK};font-size:12px;line-height:19px;color:${brandPalette.outline};">${htmlEscape(email.footnote)}</p>
${email.footerLink ? footerLink(email.footerLink) : ""}<p class="muted" style="margin:12px 0 0;font-family:${INTERFACE_STACK};font-size:12px;line-height:19px;color:${brandPalette.outline};">Sent by ${htmlEscape(BRAND_NAME)}. This message carries no tracking pixel and no click tracking.</p>
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
  if (email.receipt) lines.push("", ...receiptText(email.receipt));
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
  if (email.footerLink) {
    lines.push("", `${email.footerLink.text} ${email.footerLink.label}:`,
      email.footerLink.url);
  }
  return lines.join("\n");
}

/** The receipt as plain lines: facts, items with their detail, totals. */
function receiptText(receipt: BrandedReceipt): string[] {
  const fact = (item: BrandedFact) => `${item.label}: ${item.value}`;
  const lines = [receipt.heading];
  if (receipt.subheading) lines.push(receipt.subheading);
  lines.push("", ...receipt.facts.map(fact), "");
  for (const item of receipt.items) {
    lines.push(`${item.description} - ${item.amount}`);
    if (item.detail) lines.push(`  ${item.detail}`);
  }
  lines.push("", ...receipt.totals.map(fact));
  if (receipt.closing) lines.push("", receipt.closing);
  return lines;
}
