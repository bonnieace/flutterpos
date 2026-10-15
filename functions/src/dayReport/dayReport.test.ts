import {test} from "node:test";
import assert from "node:assert/strict";
import {PDFDocument} from "pdf-lib";
import {
  buildDayReport,
  formatBusinessDate,
  formatDateTime,
  formatShiftSpan,
  formatTime,
  previousBusinessDate,
  templateParameter,
  templateParameters,
} from "./report";
import {renderDayReportPdf} from "./reportPdf";
import {buildTemplatePayload} from "./whatsapp";
import {SAMPLE_BUSINESS_DATE, SAMPLE_PRODUCTS, SAMPLE_SALES, SAMPLE_SHIFTS} from "./sample";

const sample = () => buildDayReport({
  businessDate: SAMPLE_BUSINESS_DATE,
  sales: SAMPLE_SALES,
  shifts: SAMPLE_SHIFTS,
  products: SAMPLE_PRODUCTS,
});

test("totals the day, its payments and its shifts", () => {
  const report = sample();
  assert.equal(report.totalSales, 58060);
  assert.equal(report.saleCount, 6);
  assert.deepEqual(report.payments, [
    {method: "Cash", amount: 18160},
    {method: "Mpesa", amount: 39900},
  ]);
  assert.deepEqual(report.shifts.map((shift) => [shift.staffName, shift.saleCount, shift.amount]),
    [["John K.", 3, 18410], ["Mary W.", 3, 39650]]);
  assert.deepEqual(report.openShifts, []);
});

test("groups items under their category, biggest category and item first", () => {
  const report = sample();
  assert.deepEqual(report.categories.map((category) =>
    [category.name, category.quantity, category.amount]), [
    ["Beer", 120, 31200],
    ["Spirits", 37, 23650],
    ["Soft drinks", 48, 3210],
  ]);
  assert.deepEqual(report.categories[0].items.map((item) => [item.name, item.quantity]), [
    ["Tusker Lager 500ml", 62],
    ["White Cap 500ml", 34],
    ["Guinness 500ml", 24],
  ]);
});

test("finds a category by name where the item id is unknown, else Other", () => {
  const report = buildDayReport({
    businessDate: "2026-10-14",
    sales: [{totalAmount: 380, payment: "Cash", soldBy: "Ann", items: [
      {productName: "tusker lager 500ml", quantity: 1, price: 250, itemid: "gone"},
      {productName: "Samosa", quantity: 2, price: 65},
    ]}],
    shifts: [],
    products: SAMPLE_PRODUCTS,
  });
  assert.deepEqual(report.categories.map((category) => category.name), ["Beer", "Other"]);
  assert.deepEqual(report.shifts.map((shift) => shift.staffName), ["Ann (no shift)"]);
});

test("tells apart sizes that share a name", () => {
  const report = buildDayReport({
    businessDate: "2026-10-13",
    sales: [{totalAmount: 1650, payment: "Cash", items: [
      {productName: "Viceroy", sku: "375ml", quantity: 1, price: 950, itemid: "v375"},
      {productName: "Viceroy", sku: "250ml", quantity: 1, price: 700, itemid: "v250"},
      {productName: "Tusker Lager 500ml", sku: "500ml", quantity: 0, price: 250},
    ]}],
    shifts: [],
    products: [
      {id: "v375", name: "Viceroy", category: "BRANDY"},
      {id: "v250", name: "Viceroy", category: "BRANDY"},
    ],
  });
  assert.deepEqual(report.categories[0].items.map((item) => [item.name, item.size]),
    [["Viceroy", "250ml"], ["Viceroy", "375ml"]]);
  // A size already in the name is not repeated.
  assert.deepEqual([report.categories[1].items[0].name, report.categories[1].items[0].size],
    ["Tusker Lager 500ml", ""]);
});

test("a shift ending on a later day says which", () => {
  assert.equal(formatShiftSpan(new Date("2026-10-13T10:36:00Z"),
    new Date("2026-10-14T09:29:00Z"), false), "13:36 – Wed 12:29");
  assert.equal(formatShiftSpan(new Date("2026-10-13T13:02:00Z"),
    new Date("2026-10-13T20:48:00Z"), false), "16:02 – 23:48");
  assert.equal(formatShiftSpan(new Date("2026-10-13T10:14:00Z"), null, true),
    "13:14 – still open");
});

test("buckets sales by hour, empty hours included, and counts items", () => {
  const at = (time: string) => new Date(`2026-10-13T${time}:00+03:00`);
  const report = buildDayReport({
    businessDate: "2026-10-13",
    sales: [
      {totalAmount: 500, dateAdded: at("23:10"), items: [{productName: "A", quantity: 2, price: 250}]},
      {totalAmount: 300, dateAdded: at("23:50"), items: [{productName: "A", quantity: 1, price: 300}]},
      {totalAmount: 100, dateAdded: new Date("2026-10-14T01:05:00+03:00"),
        items: [{productName: "B", quantity: 1, price: 100}]},
      {totalAmount: 50, items: [{productName: "B", quantity: 1, price: 50}]},
    ],
    shifts: [],
    products: [],
  });
  assert.deepEqual(report.hourly.map((hour) => [formatTime(hour.start), hour.amount, hour.count]),
    [["23:00", 800, 2], ["00:00", 0, 0], ["01:00", 100, 1]]);
  assert.equal(report.itemsSold, 5);
  assert.equal(formatTime(report.firstSaleAt!), "23:10");
  assert.equal(formatTime(report.lastSaleAt!), "01:05");
});

test("flags a shift still open and lists one with no sales", () => {
  const report = buildDayReport({
    businessDate: "2026-10-14",
    sales: [],
    shifts: [{id: "s", staffName: "Peter O.", status: "open", startTime: null}],
    products: [],
  });
  assert.deepEqual(report.openShifts, ["Peter O."]);
  assert.equal(report.shifts[0].saleCount, 0);
  assert.equal(templateParameters(report)[5], "Peter O.");
});

test("reports yesterday in Nairobi, whatever the server's own zone", () => {
  // 08:00 Nairobi is 05:00 UTC on the same day.
  assert.equal(previousBusinessDate(new Date("2026-10-15T05:00:00Z")), "2026-10-14");
  // 00:30 Nairobi on the 1st is still 21:30 UTC on the 30th.
  assert.equal(previousBusinessDate(new Date("2026-09-30T21:30:00Z")), "2026-09-30");
  assert.equal(previousBusinessDate(new Date("2027-01-01T05:00:00Z")), "2026-12-31");
  assert.equal(formatBusinessDate("2026-10-14"), "Wed 14 Oct 2026");
  // 01:30 Nairobi on the 15th is 22:30 UTC on the 14th.
  assert.equal(formatDateTime(new Date("2026-10-14T22:30:00Z")), "Thu 15 Oct 2026 01:30");
});

test("template values carry no line breaks and are never empty", () => {
  assert.equal(templateParameter("a\nb\t c      d"), "a b c d");
  assert.equal(templateParameter("   "), "-");
  assert.equal(templateParameter("x".repeat(300)).length, 200);
  assert.deepEqual(templateParameters(sample()), [
    "Wed 14 Oct 2026",
    "2 (John K., Mary W.)",
    "58,060",
    "6",
    "Cash 18,160 · M-Pesa 39,900",
    "none",
  ]);
});

test("names the PDF in the template header", () => {
  const payload = buildTemplatePayload({
    to: "+254700000000",
    templateName: "thamani_day_summary_v1",
    languageCode: "en",
    bodyParameters: ["a"],
    headerDocument: {mediaId: "m1", filename: "Day-report-2026-10-14.pdf"},
  });
  assert.equal(payload.to, "254700000000");
  assert.deepEqual(payload.template.components?.[0], {
    type: "header",
    parameters: [{type: "document",
      document: {id: "m1", filename: "Day-report-2026-10-14.pdf"}}],
  });
});

test("renders a PDF, onto more pages when the items run long", async () => {
  const one = await renderDayReportPdf(sample());
  assert.equal(Buffer.from(one.slice(0, 5)).toString(), "%PDF-");
  const many = buildDayReport({
    businessDate: "2026-10-14",
    sales: [{totalAmount: 0, items: Array.from({length: 120}, (_, i) => ({
      productName: `Item ${i}`, quantity: 1, price: 0,
    }))}],
    shifts: [],
    products: [],
  });
  const pages = (await PDFDocument.load(await renderDayReportPdf(many))).getPageCount();
  assert.ok(pages >= 2, `expected several pages, got ${pages}`);
});
