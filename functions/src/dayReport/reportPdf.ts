import {readFileSync} from "node:fs";
import {join} from "node:path";
import fontkit from "@pdf-lib/fontkit";
import {LineCapStyle, PDFDocument, PDFFont, PDFPage, rgb} from "pdf-lib";
import {
  CategoryTotal,
  DayReport,
  HOUR_MS,
  ShiftTotal,
  formatBusinessDate,
  formatDayTime,
  formatLongDate,
  formatMoney,
  formatQuantity,
  formatTime,
  formatWeekdayTime,
  nairobiDate,
  paymentLabel,
} from "./report";

/**
 * The daily trading report as an A4 PDF, drawn to the boards in
 * `docs/design/day-report/` - read its README for why each part is where it
 * is. Every measurement here is the boards' own, in pt.
 *
 * Page 1 answers "how did last night go, and is anything wrong": the total,
 * an open-shift warning, sales per hour with the shifts on the same time
 * axis, how it was paid, and what sold by category. The items follow from a
 * new page, in two columns.
 *
 * Noto Sans is embedded whole from `assets/fonts`, pre-cut to Latin - the same
 * files and for the same reason as UzaPay's receipt PDF: pdf-lib's own
 * subsetting draws glyphs blank. Its digits are all one width, so columns of
 * figures line up without OpenType features, which pdf-lib can't apply.
 */

/** Printed on every report. Thamani's own invoice prints the same words. */
export const BUSINESS_NAME = "Chilltent Lounge";
export const BUSINESS_TOWN = "Juja";

// ── Tokens (docs/design/day-report/README.md) ────────────────────────────────

function hex(value: string) {
  const n = parseInt(value.slice(1), 16);
  return rgb(((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255);
}

/** main's TColors. `brand` and `debt` are fills and strokes only, never text. */
const COLOR = {
  ink: hex("#232323"),
  ink2: hex("#4F4F4F"),
  muted: hex("#6C757D"),
  hairline: hex("#E0E0E0"),
  band: hex("#F6F6F6"),
  brand: hex("#4B68FF"),
  brandTint: hex("#B0C7FF"),
  brandWash: hex("#F3F5FF"),
  mpesa: hex("#388E3C"),
  debt: hex("#F57C00"),
  other: hex("#939393"),
  white: rgb(1, 1, 1),
};
type Color = typeof COLOR.ink;

interface Type {size: number; lh: number; tracking?: number}
const TYPE = {
  display: {size: 34, lh: 38},
  title: {size: 15, lh: 18},
  value: {size: 14, lh: 17},
  currency: {size: 14, lh: 17},
  section: {size: 9.5, lh: 12, tracking: 0.8},
  wordmark: {size: 10, lh: 12, tracking: 1.5},
  runningWordmark: {size: 8.5, lh: 11, tracking: 1.3},
  category: {size: 8.5, lh: 11, tracking: 0.5},
  categoryRow: {size: 8.5, lh: 11, tracking: 0.4},
  body: {size: 8.5, lh: 11},
  small: {size: 7.5, lh: 10},
  note: {size: 6.5, lh: 10},
  micro: {size: 6.5, lh: 8, tracking: 0.6},
} satisfies Record<string, Type>;

const PAGE_WIDTH = 595;
const PAGE_HEIGHT = 842;
const MARGIN = 40;
const RIGHT = PAGE_WIDTH - MARGIN;
const CONTENT_WIDTH = RIGHT - MARGIN;
/** The footer's rule; content stops this far above it. */
const FOOTER_RULE = 802.5;
const CONTENT_BOTTOM = FOOTER_RULE - 12;

/** Page 1's three columns: names, the shared time axis, figures. */
const PLOT_LEFT = MARGIN + 96;
const PLOT_WIDTH = 315;
const PLOT_RIGHT = PLOT_LEFT + PLOT_WIDTH;
const COUNT_END = PLOT_RIGHT + 36;
const KES_END = RIGHT;

const CHART_HEIGHT = 96;
const LANE_HEIGHT = 20;
const CATEGORY_ROW = 18;

/** Page 2's two columns. */
const ITEM_COLUMN = 245.5;
const ITEM_GAP = 24;
const ITEM_ROW = 15;
const CATEGORY_BAND = 20;

/** Noto Sans: ascent 1069, descent 293, per 1000. */
const ASCENT = 1.069;
const EXTENT = 1.362;

const FONT_DIRECTORY = join(__dirname, "..", "..", "assets", "fonts");
let fontBytes: {regular: Uint8Array; bold: Uint8Array} | null = null;

function fonts(): {regular: Uint8Array; bold: Uint8Array} {
  fontBytes ??= {
    regular: readFileSync(join(FONT_DIRECTORY, "NotoSans-Regular.ttf")),
    bold: readFileSync(join(FONT_DIRECTORY, "NotoSans-Bold.ttf")),
  };
  return fontBytes;
}

// ── Drawing primitives, measured from the top of the page ────────────────────

interface Ctx {
  doc: PDFDocument;
  regular: PDFFont;
  bold: PDFFont;
  page: PDFPage;
  /** The next free y, from the top of the page. */
  top: number;
  report: DayReport;
  generatedAt?: Date;
}

/** Where a line of [type] whose box starts at [top] puts its baseline. */
function baseline(top: number, type: Type): number {
  return top + (type.lh - EXTENT * type.size) / 2 + ASCENT * type.size;
}

function width(font: PDFFont, text: string, type: Type): number {
  const tracking = type.tracking ?? 0;
  return font.widthOfTextAtSize(text, type.size) + tracking * Math.max(0, [...text].length - 1);
}

/** [text] cut with an ellipsis to fit [max]. */
function fit(font: PDFFont, text: string, type: Type, max: number): string {
  if (width(font, text, type) <= max) return text;
  let cut = text.length;
  while (cut > 1 && width(font, `${text.slice(0, cut)}…`, type) > max) cut--;
  return `${text.slice(0, cut)}…`;
}

interface TextOptions {
  x: number;
  top: number;
  type: Type;
  font: PDFFont;
  color: Color;
  align?: "left" | "right" | "center";
  maxWidth?: number;
  /** Puts the baseline here instead of deriving it from [top]. */
  baselineAt?: number;
}

/** Draws one line and answers its width. */
function text(page: PDFPage, value: string, options: TextOptions): number {
  const {type, font, color} = options;
  const shown = options.maxWidth === undefined ? value :
    fit(font, value, type, options.maxWidth);
  const w = width(font, shown, type);
  let x = options.align === "right" ? options.x - w :
    options.align === "center" ? options.x - w / 2 : options.x;
  const y = PAGE_HEIGHT - (options.baselineAt ?? baseline(options.top, type));
  const tracking = type.tracking ?? 0;
  if (!tracking) {
    page.drawText(shown, {x, y, size: type.size, font, color});
    return w;
  }
  for (const character of shown) {
    page.drawText(character, {x, y, size: type.size, font, color});
    x += font.widthOfTextAtSize(character, type.size) + tracking;
  }
  return w;
}

/** A rectangle with each corner's own radius: top-left, top-right, bottom-right, bottom-left. */
function box(
  page: PDFPage,
  left: number,
  top: number,
  w: number,
  h: number,
  radius: number | [number, number, number, number],
  color: Color
): void {
  if (w <= 0 || h <= 0) return;
  const [tl, tr, br, bl] = (typeof radius === "number" ?
    [radius, radius, radius, radius] : radius).map((r) => Math.min(r, w / 2, h / 2));
  const k = 0.4477; // 1 - 0.5523, a quarter circle as a cubic.
  const path = `M ${tl} 0 H ${w - tr} C ${w - tr * k} 0 ${w} ${tr * k} ${w} ${tr} ` +
    `V ${h - br} C ${w} ${h - br * k} ${w - br * k} ${h} ${w - br} ${h} ` +
    `H ${bl} C ${bl * k} ${h} 0 ${h - bl * k} 0 ${h - bl} ` +
    `V ${tl} C 0 ${tl * k} ${tl * k} 0 ${tl} 0 Z`;
  page.drawSvgPath(path, {x: left, y: PAGE_HEIGHT - top, color});
}

function rule(
  page: PDFPage,
  from: number,
  to: number,
  top: number,
  thickness: number,
  color: Color,
  dashArray?: number[]
): void {
  const y = PAGE_HEIGHT - top - thickness / 2;
  page.drawLine({start: {x: from, y}, end: {x: to, y}, thickness, color, dashArray});
}

function wrap(font: PDFFont, value: string, type: Type, max: number): string[] {
  const lines: string[] = [];
  let current = "";
  for (const word of value.split(/\s+/).filter(Boolean)) {
    const candidate = current ? `${current} ${word}` : word;
    if (width(font, candidate, type) <= max || !current) {
      current = candidate;
    } else {
      lines.push(current);
      current = word;
    }
  }
  if (current) lines.push(current);
  return lines;
}

// ── Pages ────────────────────────────────────────────────────────────────────

function addPage(ctx: Ctx): void {
  ctx.page = ctx.doc.addPage([PAGE_WIDTH, PAGE_HEIGHT]);
  ctx.top = MARGIN;
}

/** Page 1's masthead: the business on the left, the date on the right. */
function masthead(ctx: Ctx): void {
  const {page, bold, regular} = ctx;
  text(page, BUSINESS_NAME.toUpperCase(), {x: MARGIN, top: 45, type: TYPE.wordmark,
    font: bold, color: COLOR.ink});
  text(page, BUSINESS_TOWN, {x: MARGIN, top: 59, type: TYPE.small, font: regular,
    color: COLOR.muted});
  text(page, "DAILY TRADING REPORT", {x: RIGHT, top: 40, type: TYPE.micro, font: bold,
    color: COLOR.muted, align: "right"});
  text(page, formatLongDate(ctx.report.businessDate), {x: RIGHT, top: 51, type: TYPE.title,
    font: bold, color: COLOR.ink, align: "right"});
  rule(page, MARGIN, RIGHT, 81, 0.75, COLOR.ink);
  ctx.top = 81.75;
}

/** Every later page's head: the same two facts on one line. */
function runningHead(ctx: Ctx): void {
  const {page, bold} = ctx;
  text(page, BUSINESS_NAME.toUpperCase(), {x: MARGIN, top: 40, type: TYPE.runningWordmark,
    font: bold, color: COLOR.ink});
  text(page, formatLongDate(ctx.report.businessDate), {x: RIGHT, top: 40, type: TYPE.body,
    font: bold, color: COLOR.ink, align: "right"});
  rule(page, MARGIN, RIGHT, 59, 0.75, COLOR.ink);
  ctx.top = 59.75;
}

function continuePage(ctx: Ctx): void {
  addPage(ctx);
  runningHead(ctx);
}

/** Starts a new page where [height] more would run into the footer. */
function ensure(ctx: Ctx, height: number): boolean {
  if (ctx.top + height <= CONTENT_BOTTOM) return false;
  continuePage(ctx);
  return true;
}

const SECTION_HEAD = 25.5;

function sectionHead(ctx: Ctx, title: string, note: string, gap = 20): {noteAt: [number, number]} {
  const {page, bold, regular} = ctx;
  const top = ctx.top + gap;
  text(page, title.toUpperCase(), {x: MARGIN, top, type: TYPE.section, font: bold,
    color: COLOR.ink});
  const line = baseline(top, TYPE.section);
  if (note) {
    text(page, note, {x: RIGHT, top, type: TYPE.small, font: regular, color: COLOR.muted,
      align: "right", baselineAt: line});
  }
  rule(page, MARGIN, RIGHT, top + 17, 0.5, COLOR.hairline);
  ctx.top = top + 17.5 + 8;
  return {noteAt: [top, line]};
}

function footers(ctx: Ctx): void {
  const pages = ctx.doc.getPages();
  const sent = ctx.generatedAt ? ` · sent ${formatDayTime(ctx.generatedAt)}` : "";
  const left = `${BUSINESS_NAME} · Daily trading report · ` +
    `${formatBusinessDate(ctx.report.businessDate)}${sent}`;
  pages.forEach((page, index) => {
    rule(page, MARGIN, RIGHT, FOOTER_RULE, 0.5, COLOR.hairline);
    text(page, left, {x: MARGIN, top: 808, type: TYPE.small, font: ctx.regular,
      color: COLOR.muted, maxWidth: CONTENT_WIDTH - 70});
    text(page, `Page ${index + 1} of ${pages.length}`, {x: RIGHT, top: 808, type: TYPE.small,
      font: ctx.regular, color: COLOR.muted, align: "right"});
  });
}

// ── Page 1 ───────────────────────────────────────────────────────────────────

function hero(ctx: Ctx): void {
  const {page, bold, report} = ctx;
  const top = ctx.top + 16;
  const height = 82;
  const quiet = report.saleCount === 0;
  box(page, MARGIN, top, CONTENT_WIDTH, height, 6, COLOR.brandWash);

  text(page, "TOTAL SALES", {x: MARGIN + 20, top: top + 16, type: TYPE.micro, font: bold,
    color: COLOR.muted});
  const line = baseline(top + 28, TYPE.display);
  const currency = text(page, "KES", {x: MARGIN + 20, top: 0, type: TYPE.currency, font: bold,
    color: COLOR.ink2, baselineAt: line});
  text(page, formatMoney(report.totalSales), {x: MARGIN + 20 + currency + 4, top: top + 28,
    type: TYPE.display, font: bold, color: quiet ? COLOR.ink2 : COLOR.ink});

  const stats: Array<[string, string]> = [
    ["SALES", String(report.saleCount)],
    ["AVERAGE SALE", quiet ? "–" : formatMoney(Math.round(report.totalSales / report.saleCount))],
    ["ITEMS SOLD", formatQuantity(report.itemsSold)],
  ];
  let end = RIGHT - 20;
  const statTop = top + 36;
  for (const [label, value] of [...stats].reverse()) {
    const content = Math.max(width(bold, label, TYPE.micro), width(bold, value, TYPE.value));
    const w = Math.max(64, 16.75 + content);
    const left = end - w;
    page.drawLine({start: {x: left + 0.375, y: PAGE_HEIGHT - statTop},
      end: {x: left + 0.375, y: PAGE_HEIGHT - statTop - 30}, thickness: 0.75,
      color: COLOR.brandTint});
    text(page, label, {x: left + 16.75, top: statTop, type: TYPE.micro, font: bold,
      color: COLOR.muted});
    text(page, value, {x: left + 16.75, top: statTop + 11, type: TYPE.value, font: bold,
      color: quiet ? COLOR.ink2 : COLOR.ink});
    end = left - 16;
  }
  ctx.top = top + height;
}

function joinNames(names: string[]): string {
  return names.length <= 1 ? names.join("") :
    `${names.slice(0, -1).join(", ")} and ${names[names.length - 1]}`;
}

/** "since 13:14", or "since Mon 22:10" for a shift begun before the date. */
function since(shift: ShiftTotal, businessDate: string): string {
  if (!shift.startTime) return "";
  return nairobiDate(shift.startTime) === businessDate ?
    ` since ${formatTime(shift.startTime)}` : ` since ${formatWeekdayTime(shift.startTime)}`;
}

/** Only when a shift was never closed. The one use of `debt` outside payments. */
function attention(ctx: Ctx): void {
  const {page, bold, regular, report} = ctx;
  const open = report.shifts.filter((shift) => shift.open);
  if (!open.length) return;
  const top = ctx.top + 12;
  const textX = MARGIN + 3 + 12 + 12 + 10;
  const textWidth = RIGHT - 0.75 - 12 - textX;
  const at = formatTime(ctx.generatedAt ?? new Date());
  const title = open.length === 1 ?
    `1 shift was still open at ${at}` : `${open.length} shifts were still open at ${at}`;
  const who = joinNames(open.map((shift) => `${shift.staffName}${since(shift, report.businessDate)}`));
  const detail = `${who}. Their sales so far are counted; anything they sell from now on is not.`;
  const lines = wrap(regular, detail, TYPE.small, textWidth);
  const height = 0.75 + 8 + 11 + 1 + 10 * lines.length + 8 + 0.75;

  box(page, MARGIN, top, CONTENT_WIDTH, height, 4, COLOR.debt);
  box(page, MARGIN + 3, top + 0.75, CONTENT_WIDTH - 3.75, height - 1.5, [1, 3.25, 3.25, 1],
    COLOR.white);

  // A triangle with an exclamation mark: the warning is in words too.
  const iconX = MARGIN + 3 + 12;
  const iconTop = top + 0.75 + 8 + 1;
  page.drawSvgPath("M 6 0.55 L 11.45 10.45 L 0.55 10.45 Z", {x: iconX,
    y: PAGE_HEIGHT - iconTop, borderColor: COLOR.debt, borderWidth: 1.1});
  page.drawLine({start: {x: iconX + 6, y: PAGE_HEIGHT - iconTop - 3.8},
    end: {x: iconX + 6, y: PAGE_HEIGHT - iconTop - 6.9}, thickness: 1.1, color: COLOR.ink,
    lineCap: LineCapStyle.Round});
  page.drawCircle({x: iconX + 6, y: PAGE_HEIGHT - iconTop - 8.75, size: 0.65,
    color: COLOR.ink});

  text(page, title, {x: textX, top: top + 8.75, type: TYPE.body, font: bold, color: COLOR.ink});
  lines.forEach((line, index) => text(page, line, {x: textX, top: top + 8.75 + 12 + index * 10,
    type: TYPE.small, font: regular, color: COLOR.ink2}));
  ctx.top = top + height;
}

/** 1, 2.5 or 5 x 10^n: the smallest step that three gridlines carry [max] under. */
function niceStep(max: number): number {
  const target = Math.max(max, 1) / 3;
  const power = Math.pow(10, Math.floor(Math.log10(target)));
  for (const multiple of [1, 2.5, 5, 10]) {
    if (multiple * power >= target) return multiple * power;
  }
  return 10 * power;
}

interface Axis {
  start: number;
  slots: number;
  amounts: number[];
  counts: number[];
  /** Sales stamped with this date but made after its cutoff. */
  late: {amount: number; count: number};
}

/** The till's own cutoff: a business date ends at 05:00 the next morning. */
const CUTOFF_HOUR = 5;

function cutoff(businessDate: string): number {
  const [year, month, day] = businessDate.split("-").map(Number);
  // Nairobi is UTC+3 all year.
  return Date.UTC(year, month - 1, day + 1, CUTOFF_HOUR - 3);
}

/**
 * The hours the chart covers: from the first sale's hour to the hour after the
 * last, reaching back for a shift that opened up to six hours earlier.
 *
 * It stops at the date's cutoff. A shift left open keeps stamping its sales
 * with the date it was opened on, so without the stop one unclosed shift
 * stretches the axis across the next morning.
 */
function timeAxis(report: DayReport): Axis | null {
  const end = cutoff(report.businessDate);
  const inDay = report.hourly.filter((hour) => hour.start.getTime() < end);
  const late = report.hourly.filter((hour) => hour.start.getTime() >= end)
    .reduce((sum, hour) => ({amount: sum.amount + hour.amount, count: sum.count + hour.count}),
      {amount: 0, count: 0});
  while (inDay.length && inDay[inDay.length - 1].count === 0) inDay.pop();
  if (!inDay.length) return null;
  const first = inDay[0].start.getTime();
  const last = inDay[inDay.length - 1].start.getTime();
  let start = first;
  for (const shift of report.shifts) {
    const opened = shift.startTime?.getTime();
    if (opened !== undefined && opened < start && opened >= first - 6 * HOUR_MS) {
      start = Math.floor(opened / HOUR_MS) * HOUR_MS;
    }
  }
  const slots = (last - start) / HOUR_MS + 1;
  const amounts = new Array<number>(slots).fill(0);
  const counts = new Array<number>(slots).fill(0);
  for (const hour of inDay) {
    const index = (hour.start.getTime() - start) / HOUR_MS;
    amounts[index] = hour.amount;
    counts[index] = hour.count;
  }
  return {start, slots, amounts, counts, late};
}

/** A time on the business date as `13:47`; on a later day, `Wed 13:47`. */
function onDate(value: Date, businessDate: string): string {
  return nairobiDate(value) === businessDate || value.getTime() < cutoff(businessDate) ?
    formatTime(value) : formatWeekdayTime(value);
}

function arrow(page: PDFPage, left: number, middle: number): void {
  page.drawLine({start: {x: left, y: PAGE_HEIGHT - middle}, end: {x: left + 4.5, y: PAGE_HEIGHT - middle},
    thickness: 0.8, color: COLOR.ink});
  page.drawSvgPath("M 0 0 L -2.6 -2 L -2.6 2 Z", {x: left + 6, y: PAGE_HEIGHT - middle,
    color: COLOR.ink});
}

/** Diagonal stripes over an open shift's span, kept inside it. */
function hatch(page: PDFPage, left: number, top: number, w: number, h: number): void {
  for (let offset = 3; offset < w + h; offset += 6) {
    // A line falling left at 45°, from the top edge at left + offset.
    let x1 = left + offset;
    let y1 = top;
    let x2 = left + offset - h;
    let y2 = top + h;
    if (x1 > left + w) {
      y1 += x1 - (left + w);
      x1 = left + w;
    }
    if (x2 < left) {
      y2 -= left - x2;
      x2 = left;
    }
    if (y2 <= y1) continue;
    page.drawLine({start: {x: x1, y: PAGE_HEIGHT - y1}, end: {x: x2, y: PAGE_HEIGHT - y2},
      thickness: 1.5, color: COLOR.white, opacity: 0.45});
  }
}

function tradingDay(ctx: Ctx): void {
  const {report, bold, regular} = ctx;
  if (!report.shifts.length && !report.hourly.length) return;
  const axis = timeAxis(report);
  const chart = axis ? CHART_HEIGHT + 12 : 0;
  ensure(ctx, 20 + SECTION_HEAD + chart + 14 + LANE_HEIGHT * Math.min(report.shifts.length, 4));
  sectionHead(ctx, "Trading day", axis ? "Sales per hour, and who was on shift" : "Who was on shift");
  const page = ctx.page;
  const top = ctx.top;
  const slot = axis ? PLOT_WIDTH / axis.slots : 0;
  const position = (time: number) => axis ?
    Math.min(PLOT_RIGHT, Math.max(PLOT_LEFT, PLOT_LEFT + (time - axis.start) / HOUR_MS * slot)) : 0;
  const axisEnd = axis ? axis.start + axis.slots * HOUR_MS : 0;

  if (axis) {
    const peak = axis.amounts.indexOf(Math.max(...axis.amounts));
    const step = niceStep(axis.amounts[peak]);
    const scale = step * 3;
    for (let line = 0; line <= 3; line++) {
      const y = top + CHART_HEIGHT - line * step / scale * CHART_HEIGHT;
      rule(page, PLOT_LEFT, PLOT_RIGHT, y, line ? 0.5 : 0.75, line ? COLOR.hairline : COLOR.ink2);
      const label = line ? formatMoney(line * step) : "0";
      text(page, label, {x: PLOT_LEFT - 8, top: y - TYPE.small.lh / 2, type: TYPE.small,
        font: regular, color: COLOR.muted, align: "right"});
    }
    const barWidth = Math.min(13, slot * 0.66);
    axis.amounts.forEach((amount, index) => {
      const h = amount / scale * CHART_HEIGHT;
      const x = PLOT_LEFT + index * slot + (slot - barWidth) / 2;
      box(page, x, top + CHART_HEIGHT - h, barWidth, h, [1.5, 1.5, 0, 0],
        index === peak ? COLOR.brand : COLOR.brandTint);
      if (index === peak) {
        text(page, formatMoney(amount), {x: x + barWidth / 2, top: top + CHART_HEIGHT - h - 2 - TYPE.small.lh,
          type: TYPE.small, font: bold, color: COLOR.ink, align: "center"});
      }
    });
    const every = axis.slots <= 18 ? 2 : axis.slots <= 27 ? 3 : 4;
    for (let index = 0; index <= axis.slots; index += every) {
      text(page, formatTime(new Date(axis.start + index * HOUR_MS)), {x: PLOT_LEFT + index * slot,
        top: top + CHART_HEIGHT + 3, type: TYPE.small, font: regular, color: COLOR.muted,
        align: "center"});
    }
    // The axis' own end, where the last label stops short of it with room.
    if (axis.slots % every !== 0 && (axis.slots % every) * slot >= 26) {
      text(page, formatTime(new Date(axisEnd)), {x: PLOT_RIGHT, top: top + CHART_HEIGHT + 3,
        type: TYPE.small, font: regular, color: COLOR.muted, align: "center"});
    }

    // Beside the chart: the busiest hour in words, so it never rests on colour.
    const side = PLOT_RIGHT + 16;
    const peakStart = axis.start + peak * HOUR_MS;
    text(page, "BUSIEST HOUR", {x: side, top, type: TYPE.micro, font: bold, color: COLOR.muted});
    text(page, `${formatTime(new Date(peakStart))} – ${formatTime(new Date(peakStart + HOUR_MS))}`,
      {x: side, top: top + 10, type: TYPE.body, font: bold, color: COLOR.ink});
    const count = axis.counts[peak];
    text(page, `KES ${formatMoney(axis.amounts[peak])} · ${count} sale${count === 1 ? "" : "s"}`,
      {x: side, top: top + 21, type: TYPE.small, font: regular, color: COLOR.muted});
    if (report.firstSaleAt && report.lastSaleAt) {
      text(page, "FIRST · LAST SALE", {x: side, top: top + 41, type: TYPE.micro, font: bold,
        color: COLOR.muted});
      text(page, `${onDate(report.firstSaleAt, report.businessDate)} · ` +
        onDate(report.lastSaleAt, report.businessDate),
      {x: side, top: top + 51, type: TYPE.body, font: regular, color: COLOR.ink});
    }
    if (axis.late.count) {
      text(page, `AFTER ${formatTime(new Date(cutoff(report.businessDate)))}`, {x: side,
        top: top + 72, type: TYPE.micro, font: bold, color: COLOR.muted});
      text(page, `KES ${formatMoney(axis.late.amount)} · ${axis.late.count} sale` +
        `${axis.late.count === 1 ? "" : "s"}`, {x: side, top: top + 82, type: TYPE.small,
        font: regular, color: COLOR.muted});
    }
  }
  ctx.top = top + chart;

  const laneHeads = () => {
    text(ctx.page, "SALES", {x: COUNT_END, top: ctx.top + 6, type: TYPE.micro, font: bold,
      color: COLOR.muted, align: "right"});
    text(ctx.page, "KES", {x: KES_END, top: ctx.top + 6, type: TYPE.micro, font: bold,
      color: COLOR.muted, align: "right"});
    ctx.top += 14;
  };
  laneHeads();

  for (const shift of report.shifts) {
    if (ensure(ctx, LANE_HEIGHT)) {
      sectionHead(ctx, "Trading day", "continued", 16);
      laneHeads();
    }
    const lane = ctx.top;
    const p = ctx.page;
    text(p, shift.staffName, {x: MARGIN, top: lane + 4.5, type: TYPE.body, font: bold,
      color: COLOR.ink, maxWidth: 96 - 8});
    text(p, String(shift.saleCount), {x: COUNT_END, top: lane + 4.5, type: TYPE.body,
      font: regular, color: COLOR.ink, align: "right"});
    text(p, formatMoney(shift.amount), {x: KES_END, top: lane + 4.5, type: TYPE.body, font: bold,
      color: COLOR.ink, align: "right"});

    if (!axis || !shift.startTime) {
      const words = !shift.startTime ?
        (shift.staffName.endsWith("(no shift)") ? "sold without a shift" : "time not recorded") :
        `${formatTime(shift.startTime)} – ${shift.open ? "still open" :
          shift.endTime ? formatTime(shift.endTime) : "?"}`;
      text(p, words, {x: PLOT_LEFT, top: lane + 5, type: TYPE.small, font: regular,
        color: COLOR.muted});
      ctx.top += LANE_HEIGHT;
      continue;
    }

    rule(p, PLOT_LEFT, PLOT_RIGHT, lane + 10, 0.5, COLOR.hairline, [2, 2]);
    const from = position(shift.startTime.getTime());
    const endTime = shift.endTime?.getTime();
    const beyond = !shift.open && endTime !== undefined && endTime > axisEnd;
    const to = shift.open || beyond || endTime === undefined ? PLOT_RIGHT : position(endTime);
    const spanTop = lane + 5;
    if (to > from) {
      box(p, from, spanTop, to - from, 10, shift.open ? [2, 0, 0, 2] : 2, COLOR.brandTint);
      if (shift.open) hatch(p, from + 2, spanTop, to - from - 2, 10);
      box(p, from, spanTop, 2, 10, [2, 0, 0, 2], COLOR.brand);
    }
    const note = shift.open ? "still open" :
      beyond && shift.endTime ? `closed ${onDate(shift.endTime, report.businessDate)}` : "";
    if (note) {
      const noteWidth = width(bold, note, TYPE.note) + (beyond ? 8 : 0);
      // Inside the span's right end, or before it where the span is too short.
      const right = to - from >= noteWidth + 8 ? to - 4 : from - 4;
      const textRight = beyond ? right - 8 : right;
      text(p, note, {x: textRight, top: spanTop, type: TYPE.note, font: bold, color: COLOR.ink,
        align: "right"});
      if (beyond) arrow(p, textRight + 1.5, spanTop + 5);
    }
    ctx.top += LANE_HEIGHT;
  }
}

/** Whole percentages that add to 100, by largest remainder. */
function percentages(amounts: number[]): number[] {
  const total = amounts.reduce((sum, amount) => sum + amount, 0);
  if (total <= 0) return amounts.map(() => 0);
  const exact = amounts.map((amount) => amount / total * 100);
  const floors = exact.map(Math.floor);
  let left = 100 - floors.reduce((sum, value) => sum + value, 0);
  const order = exact.map((value, index) => [value - floors[index], index])
    .sort((a, b) => b[0] - a[0]);
  for (const [, index] of order) {
    if (left <= 0) break;
    floors[index]++;
    left--;
  }
  return floors;
}

function paymentColor(method: string): Color {
  return method === "Cash" ? COLOR.brand : method === "Mpesa" ? COLOR.mpesa :
    method === "Debt" ? COLOR.debt : COLOR.other;
}

function payments(ctx: Ctx): void {
  const {report, bold, regular} = ctx;
  const methods = report.payments.filter((payment) => payment.amount > 0);
  if (!methods.length) return;
  const rows = Math.ceil(methods.length / 3);
  ensure(ctx, 20 + SECTION_HEAD + 12 + 8 + rows * 19.5);
  sectionHead(ctx, "How it was paid", "Share of the day's sales");
  const page = ctx.page;
  const top = ctx.top;

  const gap = 1.5;
  const available = CONTENT_WIDTH - gap * (methods.length - 1);
  const total = methods.reduce((sum, payment) => sum + payment.amount, 0);
  const widths = methods.map((payment) => Math.max(3, payment.amount / total * available));
  const excess = widths.reduce((sum, w) => sum + w, 0) - available;
  widths[widths.indexOf(Math.max(...widths))] -= excess;
  let x = MARGIN;
  methods.forEach((payment, index) => {
    const first = index === 0;
    const last = index === methods.length - 1;
    box(page, x, top, widths[index], 12, [first ? 6 : 0, last ? 6 : 0, last ? 6 : 0, first ? 6 : 0],
      paymentColor(payment.method));
    x += widths[index] + gap;
  });

  const shares = percentages(methods.map((payment) => payment.amount));
  const column = (CONTENT_WIDTH - 48) / 3;
  methods.forEach((payment, index) => {
    const left = MARGIN + (index % 3) * (column + 24);
    const rowTop = top + 20 + Math.floor(index / 3) * 19.5;
    box(page, left, rowTop + 5.5, 8, 8, 2, paymentColor(payment.method));
    const label = text(page, paymentLabel(payment.method), {x: left + 14, top: rowTop + 4,
      type: TYPE.body, font: bold, color: COLOR.ink});
    text(page, `${shares[index]}%`, {x: left + 14 + label + 6, top: 0, type: TYPE.small,
      font: regular, color: COLOR.muted, baselineAt: baseline(rowTop + 4, TYPE.body)});
    text(page, formatMoney(payment.amount), {x: left + column, top: rowTop + 4, type: TYPE.body,
      font: regular, color: COLOR.ink, align: "right"});
    rule(page, left, left + column, rowTop + 19, 0.5, COLOR.hairline);
  });
  ctx.top = top + 20 + rows * 19.5;
}

/** "What sold": one bar per category, scaled to the biggest. */
function whatSold(ctx: Ctx): {notePage: PDFPage; noteAt: [number, number]} | null {
  const {report, bold, regular} = ctx;
  if (!report.categories.length) return null;
  ensure(ctx, 20 + SECTION_HEAD + 10 + CATEGORY_ROW * Math.min(report.categories.length, 3));
  const head = sectionHead(ctx, "What sold", "");
  const notePage = ctx.page;
  const columnHeads = () => {
    text(ctx.page, "ITEMS", {x: COUNT_END, top: ctx.top + 2, type: TYPE.micro, font: bold,
      color: COLOR.muted, align: "right"});
    text(ctx.page, "KES", {x: KES_END, top: ctx.top + 2, type: TYPE.micro, font: bold,
      color: COLOR.muted, align: "right"});
    ctx.top += 10;
  };
  columnHeads();

  const largest = Math.max(...report.categories.map((category) => category.amount), 1);
  const shares = percentages(report.categories.map((category) => category.amount));
  report.categories.forEach((category: CategoryTotal, index) => {
    if (ensure(ctx, CATEGORY_ROW)) {
      sectionHead(ctx, "What sold", "continued", 16);
      columnHeads();
    }
    const row = ctx.top;
    const page = ctx.page;
    text(page, category.name, {x: MARGIN, top: row + 3.5, type: TYPE.categoryRow, font: bold,
      color: COLOR.ink, maxWidth: 96 - 8});
    const bar = Math.max(0, category.amount) / largest * (PLOT_WIDTH - 34);
    box(page, PLOT_LEFT, row + 5, bar, 8, [0, 2, 2, 0], COLOR.brandTint);
    text(page, `${shares[index]}%`, {x: PLOT_LEFT + bar + 6, top: row + 4, type: TYPE.small,
      font: regular, color: COLOR.muted});
    text(page, formatQuantity(category.quantity), {x: COUNT_END, top: row + 3.5, type: TYPE.body,
      font: regular, color: COLOR.ink, align: "right"});
    text(page, formatMoney(category.amount), {x: KES_END, top: row + 3.5, type: TYPE.body,
      font: bold, color: COLOR.ink, align: "right"});
    ctx.top += CATEGORY_ROW;
  });
  return {notePage, noteAt: head.noteAt};
}

/** A date with no sales: said in words, not left as a blank page. */
function nothingSold(ctx: Ctx): void {
  const {page, bold, regular, report} = ctx;
  const top = ctx.top + 20;
  const date = formatBusinessDate(report.businessDate).replace(/ \d{4}$/, "");
  const opened = report.shifts.length;
  const first = opened === 0 ?
    `No shift was opened and no sale was recorded for ${date}.` :
    `${opened} shift${opened === 1 ? " was" : "s were"} opened, but no sale was recorded for ${date}.`;
  const detail = `${first} If the bar was open, a till phone may have been offline: its sales ` +
    "appear in the app once it reconnects, but not in this report, which has already been sent.";
  const lines = wrap(regular, detail, TYPE.small, 360);
  rule(page, MARGIN, RIGHT, top, 0.5, COLOR.hairline);
  text(page, "Nothing was sold on this business date", {x: MARGIN, top: top + 14.5,
    type: TYPE.body, font: bold, color: COLOR.ink});
  lines.forEach((line, index) => text(page, line, {x: MARGIN, top: top + 27.5 + index * 10,
    type: TYPE.small, font: regular, color: COLOR.ink2}));
  const bottom = top + 27.5 + lines.length * 10 + 14;
  rule(page, MARGIN, RIGHT, bottom, 0.5, COLOR.hairline);
  ctx.top = bottom + 0.5;
}

// ── Items ────────────────────────────────────────────────────────────────────

/** Every item under its category: left column, then right, then a new page. */
function items(ctx: Ctx): void {
  const {report, bold, regular} = ctx;
  continuePage(ctx);
  const columns = [MARGIN, MARGIN + ITEM_COLUMN + ITEM_GAP];
  let column = 0;
  let y = 0;

  const startPage = (continued: boolean) => {
    sectionHead(ctx, "Items by category",
      continued ? "continued" : "Sizes after the name · price is per item", 16);
    const headTop = ctx.top - 8 + 10;
    for (const left of columns) {
      const right = left + ITEM_COLUMN - 6;
      text(ctx.page, "PRICE", {x: right - 52 - 30, top: headTop + 1, type: TYPE.micro, font: bold,
        color: COLOR.muted, align: "right"});
      text(ctx.page, "QTY", {x: right - 52, top: headTop + 1, type: TYPE.micro, font: bold,
        color: COLOR.muted, align: "right"});
      text(ctx.page, "KES", {x: right, top: headTop + 1, type: TYPE.micro, font: bold,
        color: COLOR.muted, align: "right"});
    }
    column = 0;
    y = headTop + 12;
  };
  const columnTop = () => ctx.top - 8 + 10 + 12;
  const nextColumn = () => {
    if (column === 0) {
      column = 1;
      y = columnTop();
    } else {
      continuePage(ctx);
      startPage(true);
    }
  };
  const band = (category: CategoryTotal, continued: boolean) => {
    const left = columns[column];
    const right = left + ITEM_COLUMN - 6;
    box(ctx.page, left, y, ITEM_COLUMN, CATEGORY_BAND, 3, COLOR.band);
    const name = text(ctx.page, category.name, {x: left + 6, top: y + 4.5, type: TYPE.category,
      font: bold, color: COLOR.ink, maxWidth: ITEM_COLUMN - 12 - 52 - 30 - (continued ? 50 : 0)});
    if (continued) {
      text(ctx.page, "continued", {x: left + 6 + name + 5, top: y + 5, type: TYPE.small,
        font: regular, color: COLOR.muted});
    }
    text(ctx.page, formatQuantity(category.quantity), {x: right - 52, top: y + 4.5,
      type: TYPE.body, font: regular, color: COLOR.ink, align: "right"});
    text(ctx.page, formatMoney(category.amount), {x: right, top: y + 4.5, type: TYPE.body,
      font: bold, color: COLOR.ink, align: "right"});
    y += CATEGORY_BAND;
  };

  startPage(false);
  for (const category of report.categories) {
    if (y + CATEGORY_BAND + ITEM_ROW > CONTENT_BOTTOM) nextColumn();
    band(category, false);
    category.items.forEach((item, index) => {
      if (y + ITEM_ROW > CONTENT_BOTTOM) {
        nextColumn();
        band(category, true);
      }
      const left = columns[column];
      const right = left + ITEM_COLUMN - 6;
      const priceRight = right - 52 - 30;
      const nameSpace = priceRight - 44 - (left + 6) - 4;
      const sizeWidth = item.size ? width(regular, ` ${item.size}`, TYPE.body) : 0;
      const shown = text(ctx.page, item.name, {x: left + 6, top: y + 2, type: TYPE.body,
        font: regular, color: COLOR.ink,
        maxWidth: sizeWidth < nameSpace / 2 ? nameSpace - sizeWidth : nameSpace});
      if (item.size && sizeWidth < nameSpace / 2) {
        text(ctx.page, ` ${item.size}`, {x: left + 6 + shown, top: y + 2, type: TYPE.body,
          font: regular, color: COLOR.muted});
      }
      if (item.quantity > 0) {
        text(ctx.page, formatMoney(Math.round(item.amount / item.quantity)), {x: priceRight,
          top: y + 2.5, type: TYPE.small, font: regular, color: COLOR.muted, align: "right"});
      }
      text(ctx.page, formatQuantity(item.quantity), {x: right - 52, top: y + 2, type: TYPE.body,
        font: regular, color: COLOR.ink, align: "right"});
      text(ctx.page, formatMoney(item.amount), {x: right, top: y + 2, type: TYPE.body,
        font: regular, color: COLOR.ink, align: "right"});
      const last = index === category.items.length - 1;
      if (!last && y + 2 * ITEM_ROW <= CONTENT_BOTTOM) {
        rule(ctx.page, left, left + ITEM_COLUMN, y + ITEM_ROW - 0.5, 0.5, COLOR.hairline);
      }
      y += ITEM_ROW;
    });
    y += 12;
  }
}

// ── The document ─────────────────────────────────────────────────────────────

export async function renderDayReportPdf(
  report: DayReport,
  options: {generatedAt?: Date} = {}
): Promise<Uint8Array> {
  const doc = await PDFDocument.create();
  doc.registerFontkit(fontkit);
  const bytes = fonts();
  const regular = await doc.embedFont(bytes.regular, {subset: false});
  const bold = await doc.embedFont(bytes.bold, {subset: false});
  doc.setTitle(`${BUSINESS_NAME} daily trading report ${report.businessDate}`);
  doc.setProducer(BUSINESS_NAME);

  const ctx = {doc, regular, bold, report, generatedAt: options.generatedAt, top: 0} as Ctx;
  addPage(ctx);
  masthead(ctx);
  hero(ctx);
  attention(ctx);
  if (report.saleCount === 0) {
    nothingSold(ctx);
  } else {
    tradingDay(ctx);
    payments(ctx);
    const sold = whatSold(ctx);
    const itemsPage = doc.getPageCount() + 1;
    if (sold) {
      text(sold.notePage, `By category · items on page ${itemsPage}`, {x: RIGHT, top: sold.noteAt[0],
        type: TYPE.small, font: regular, color: COLOR.muted, align: "right",
        baselineAt: sold.noteAt[1]});
      items(ctx);
    }
  }
  footers(ctx);
  return doc.save();
}
