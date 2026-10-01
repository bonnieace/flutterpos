import {readFileSync} from "node:fs";
import {join} from "node:path";
import fontkit from "@pdf-lib/fontkit";
import {PDFDocument, PDFFont, PDFImage, PDFPage, rgb} from "pdf-lib";
import {RECEIPT_WORDS, formatReceiptMoney} from "./receiptContent";
import type {ReceiptContent} from "./receiptContent";

/**
 * One sale's receipt as a PDF a customer can keep.
 *
 * **Shaped like the paper one.** A single column the width of an 80 mm roll,
 * as tall as the sale needs, in the order the thermal receipt prints: the
 * business, the receipt and its date, who served and who bought, the lines,
 * the totals, how it was paid, and the footer. A customer comparing the two
 * should find the same receipt.
 *
 * **Noto Sans, embedded whole - and already cut to Latin.** Gĩkũyũ names
 * carry ũ and ĩ, which the PDF standard fonts cannot draw - the thermal
 * printer cannot either, and substitutes them; a PDF has no such excuse.
 *
 * pdf-lib's own subsetting (`subset: true`) was tried first and drew most
 * glyphs blank in a rendered receipt on 2026-10-01, while the text layer read
 * correctly - a known fault of its fontkit fork. So the fonts in
 * `assets/fonts` are subset ahead of time instead (Basic Latin, Latin-1, Latin
 * Extended A, B and Additional, punctuation and currency signs, with `kern`),
 * about 73 KB each, and embedded without further cutting. A receipt comes to
 * well under 200 KB.
 *
 * To rebuild them: `pyftsubset NotoSans-Regular.ttf --unicodes="U+0020-007E,
 * U+00A0-00FF,U+0100-024F,U+1E00-1EFF,U+2010-2027,U+2030-203A,U+2044,
 * U+20A0-20C0,U+2116,U+2122,U+2212" --layout-features=kern --no-hinting
 * --desubroutinize`, and the same for the bold. Licensed under the OFL
 * (`assets/fonts/OFL.txt`).
 */

const PAGE_WIDTH = 226; // 80 mm in points.
const MARGIN = 14;
const CONTENT_WIDTH = PAGE_WIDTH - MARGIN * 2;
const BODY_SIZE = 8.5;
const SMALL_SIZE = 7.5;
const HEADING_SIZE = 12;
const TOTAL_SIZE = 10;
const LINE_GAP = 3;
const LOGO_MAX_WIDTH = 96;
const LOGO_MAX_HEIGHT = 48;
const INK = rgb(0.1, 0.1, 0.1);
const MUTED = rgb(0.4, 0.4, 0.4);

const FONT_DIRECTORY = join(__dirname, "..", "..", "assets", "fonts");
let fontBytes: {regular: Uint8Array; bold: Uint8Array} | null = null;

function fonts(): {regular: Uint8Array; bold: Uint8Array} {
  fontBytes ??= {
    regular: readFileSync(join(FONT_DIRECTORY, "NotoSans-Regular.ttf")),
    bold: readFileSync(join(FONT_DIRECTORY, "NotoSans-Bold.ttf")),
  };
  return fontBytes;
}

/** Splits [text] into lines no wider than [width] at [size]. */
function wrap(text: string, font: PDFFont, size: number, width: number): string[] {
  const words = text.split(/\s+/).filter((word) => word.length > 0);
  const lines: string[] = [];
  let current = "";
  for (const word of words) {
    const candidate = current ? `${current} ${word}` : word;
    if (font.widthOfTextAtSize(candidate, size) <= width) {
      current = candidate;
      continue;
    }
    if (current) lines.push(current);
    // A single word wider than the column is broken rather than overflowed.
    let rest = word;
    while (font.widthOfTextAtSize(rest, size) > width && rest.length > 1) {
      let cut = rest.length - 1;
      while (cut > 1 && font.widthOfTextAtSize(rest.slice(0, cut), size) > width) cut--;
      lines.push(rest.slice(0, cut));
      rest = rest.slice(cut);
    }
    current = rest;
  }
  if (current) lines.push(current);
  return lines.length ? lines : [""];
}

/** One drawing instruction, laid out before the page's height is known. */
type Row =
  | {kind: "text"; text: string; font: "regular" | "bold"; size: number;
      align: "left" | "center"; muted?: boolean}
  | {kind: "pair"; left: string; right: string; font: "regular" | "bold"; size: number}
  | {kind: "rule"}
  | {kind: "gap"; height: number}
  | {kind: "logo"};

function rowHeight(row: Row): number {
  switch (row.kind) {
  case "text":
  case "pair":
    return row.size + LINE_GAP;
  case "rule":
    return 8;
  case "gap":
    return row.height;
  case "logo":
    return 0; // Measured once the image is known.
  }
}

async function fetchLogo(url: string | undefined): Promise<Uint8Array | null> {
  if (!url) return null;
  try {
    const response = await fetch(url, {signal: AbortSignal.timeout(5000)});
    if (!response.ok) return null;
    return new Uint8Array(await response.arrayBuffer());
  } catch {
    // A receipt without its logo is still the receipt.
    return null;
  }
}

async function embedLogo(
  document: PDFDocument,
  bytes: Uint8Array | null
): Promise<PDFImage | null> {
  if (!bytes || bytes.length < 4) return null;
  try {
    const isPng = bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e;
    const isJpeg = bytes[0] === 0xff && bytes[1] === 0xd8;
    if (isPng) return await document.embedPng(bytes);
    if (isJpeg) return await document.embedJpg(bytes);
  } catch {
    return null;
  }
  return null;
}

/**
 * Renders [content] as a PDF.
 *
 * [logo] overrides fetching the business's logo, so a test renders without a
 * network; pass `null` to draw none.
 */
export async function renderReceiptPdf(
  content: ReceiptContent,
  options: {logo?: Uint8Array | null} = {}
): Promise<Uint8Array> {
  const document = await PDFDocument.create();
  document.registerFontkit(fontkit);
  const bytes = fonts();
  const regular = await document.embedFont(bytes.regular, {subset: false});
  const bold = await document.embedFont(bytes.bold, {subset: false});
  const fontFor = (name: "regular" | "bold") => name === "bold" ? bold : regular;
  document.setTitle(`${RECEIPT_WORDS.receiptLabel} ${content.receiptNumber}`);
  document.setProducer("UzaPay");
  document.setCreator("UzaPay");

  const logo = await embedLogo(
    document,
    options.logo !== undefined ? options.logo : await fetchLogo(content.logoUrl)
  );

  const money = (minor: number) => formatReceiptMoney(content.currency, minor);
  const rows: Row[] = [];
  const centred = (text: string, font: "regular" | "bold", size: number, muted = false) => {
    for (const line of wrap(text, fontFor(font), size, CONTENT_WIDTH)) {
      rows.push({kind: "text", text: line, font, size, align: "center", muted});
    }
  };
  const pair = (left: string, right: string, font: "regular" | "bold" = "regular",
    size = BODY_SIZE) => rows.push({kind: "pair", left, right, font, size});

  if (logo) rows.push({kind: "logo"}, {kind: "gap", height: 6});
  centred(content.businessName, "bold", HEADING_SIZE);
  if (content.slogan) centred(content.slogan, "regular", SMALL_SIZE, true);
  rows.push({kind: "rule"});
  pair(RECEIPT_WORDS.receiptLabel, content.receiptNumber, "bold");
  pair(RECEIPT_WORDS.dateLabel, content.businessDate);
  if (content.servedBy) pair(RECEIPT_WORDS.servedByLabel, content.servedBy);
  if (content.customerName) pair(RECEIPT_WORDS.customerLabel, content.customerName);
  if (content.customerKraPin) pair(RECEIPT_WORDS.kraPinLabel, content.customerKraPin);
  rows.push({kind: "rule"});

  for (const line of content.lines) {
    const amount = money(line.lineTotalMinor);
    const nameWidth = CONTENT_WIDTH - regular.widthOfTextAtSize(amount, BODY_SIZE) - 6;
    const description = `${line.quantity} x ${line.name}`;
    const wrapped = wrap(description, regular, BODY_SIZE, Math.max(nameWidth, 40));
    wrapped.forEach((text, index) => {
      if (index === 0) {
        pair(text, amount);
      } else {
        rows.push({kind: "text", text, font: "regular", size: BODY_SIZE, align: "left"});
      }
    });
    const detail = [
      line.sku,
      line.quantity > 1 ? `@ ${money(line.unitPriceMinor)}` : undefined,
    ].filter((part): part is string => Boolean(part)).join("  ");
    if (detail) {
      rows.push({kind: "text", text: detail, font: "regular", size: SMALL_SIZE,
        align: "left", muted: true});
    }
  }
  rows.push({kind: "rule"});
  pair(RECEIPT_WORDS.subtotalLabel, money(content.subtotalMinor));
  if (content.discountMinor > 0) {
    pair(RECEIPT_WORDS.discountLabel, money(-content.discountMinor));
  }
  pair(RECEIPT_WORDS.totalLabel, money(content.totalMinor), "bold", TOTAL_SIZE);
  if (content.paidBy) pair(RECEIPT_WORDS.paidByLabel, content.paidBy);
  rows.push({kind: "rule"});
  centred(RECEIPT_WORDS.footer, "regular", SMALL_SIZE, true);

  const logoSize = logo ?
    logo.scaleToFit(LOGO_MAX_WIDTH, LOGO_MAX_HEIGHT) :
    {width: 0, height: 0};
  const height = MARGIN * 2 + rows.reduce(
    (sum, row) => sum + (row.kind === "logo" ? logoSize.height : rowHeight(row)),
    0
  );
  const page = document.addPage([PAGE_WIDTH, height]);
  let y = height - MARGIN;
  for (const row of rows) {
    y = drawRow(page, row, y, fontFor, logo, logoSize);
  }
  return document.save();
}

function drawRow(
  page: PDFPage,
  row: Row,
  top: number,
  fontFor: (name: "regular" | "bold") => PDFFont,
  logo: PDFImage | null,
  logoSize: {width: number; height: number}
): number {
  switch (row.kind) {
  case "logo": {
    if (!logo) return top;
    page.drawImage(logo, {
      x: (PAGE_WIDTH - logoSize.width) / 2,
      y: top - logoSize.height,
      width: logoSize.width,
      height: logoSize.height,
    });
    return top - logoSize.height;
  }
  case "gap":
    return top - row.height;
  case "rule": {
    const y = top - 4;
    page.drawLine({
      start: {x: MARGIN, y},
      end: {x: PAGE_WIDTH - MARGIN, y},
      thickness: 0.5,
      color: MUTED,
      dashArray: [2, 2],
    });
    return top - rowHeight(row);
  }
  case "text": {
    const font = fontFor(row.font);
    const width = font.widthOfTextAtSize(row.text, row.size);
    page.drawText(row.text, {
      x: row.align === "center" ? (PAGE_WIDTH - width) / 2 : MARGIN,
      y: top - row.size,
      size: row.size,
      font,
      color: row.muted ? MUTED : INK,
    });
    return top - rowHeight(row);
  }
  case "pair": {
    const font = fontFor(row.font);
    const rightWidth = font.widthOfTextAtSize(row.right, row.size);
    page.drawText(row.left, {x: MARGIN, y: top - row.size, size: row.size, font, color: INK});
    page.drawText(row.right, {
      x: PAGE_WIDTH - MARGIN - rightWidth,
      y: top - row.size,
      size: row.size,
      font,
      color: INK,
    });
    return top - rowHeight(row);
  }
  }
}
