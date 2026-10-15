import {writeFileSync} from "node:fs";
import {buildDayReport, templateParameters} from "../dayReport/report";
import {renderDayReportPdf} from "../dayReport/reportPdf";
import {
  SAMPLE_BUSINESS_DATE,
  SAMPLE_PRODUCTS,
  SAMPLE_SALES,
  SAMPLE_SHIFTS,
} from "../dayReport/sample";

/**
 * Renders the made-up day in `dayReport/sample.ts` to a PDF, and prints the
 * template values it would send - the sample document and values Meta asks
 * for when the template is submitted.
 *
 *   npm run sample-day-report -- out.pdf
 */
async function main(): Promise<void> {
  const path = process.argv[2] ?? "sample-day-report.pdf";
  const report = buildDayReport({
    businessDate: SAMPLE_BUSINESS_DATE,
    sales: SAMPLE_SALES,
    shifts: SAMPLE_SHIFTS,
    products: SAMPLE_PRODUCTS,
  });
  writeFileSync(path, await renderDayReportPdf(report, {
    generatedAt: new Date("2026-10-15T08:00:00+03:00"),
  }));
  console.log(`Wrote ${path}`);
  templateParameters(report).forEach((value, index) => console.log(`{{${index + 1}}} ${value}`));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
