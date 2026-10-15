import {writeFileSync} from "node:fs";
import {initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {loadDayReport, sendDayReportFor} from "../dayReport/functions";
import {previousBusinessDate, templateParameters} from "../dayReport/report";
import {renderDayReportPdf} from "../dayReport/reportPdf";

/**
 * Sends one business date's report by hand, from this machine, without the
 * scheduled function being deployed. Reads Firestore with the machine's
 * application-default credentials.
 *
 *   npm run send-day-report -- --to +254722218106 [--date 2026-10-13] [--dry-run out.pdf]
 *
 * Takes WHATSAPP_ACCESS_TOKEN and WHATSAPP_PHONE_NUMBER_ID from the
 * environment, so the token is never typed onto a command line. A dry run
 * renders the PDF and prints the template values, and sends nothing.
 *
 * A real send goes through the same once-per-date record the schedule uses,
 * so a date sent by hand is not sent again at 08:00.
 */

function argument(name: string): string | undefined {
  const index = process.argv.indexOf(name);
  return index === -1 ? undefined : process.argv[index + 1];
}

/** `0722218106` as `+254722218106`; a number with its country code as it is. */
export function kenyanE164(number: string): string {
  const digits = number.replace(/[^\d+]/g, "");
  if (digits.startsWith("+")) return digits;
  if (digits.startsWith("0")) return `+254${digits.slice(1)}`;
  return `+${digits}`;
}

async function main(): Promise<void> {
  const businessDate = argument("--date") ?? previousBusinessDate(new Date());
  if (!/^\d{4}-\d{2}-\d{2}$/.test(businessDate)) throw new Error("--date must be yyyy-MM-dd");
  initializeApp({projectId: process.env.GCLOUD_PROJECT ?? "thamani-23709"});
  const db = getFirestore();

  const dryRun = argument("--dry-run");
  if (dryRun) {
    const report = await loadDayReport(db, businessDate);
    writeFileSync(dryRun, await renderDayReportPdf(report, {generatedAt: new Date()}));
    console.log(`Wrote ${dryRun} for ${businessDate}`);
    templateParameters(report).forEach((value, index) => console.log(`{{${index + 1}}} ${value}`));
    return;
  }

  const to = argument("--to");
  const accessToken = process.env.WHATSAPP_ACCESS_TOKEN?.trim();
  const phoneNumberId = process.env.WHATSAPP_PHONE_NUMBER_ID?.trim();
  if (!to || !accessToken || !phoneNumberId) {
    throw new Error("--to, WHATSAPP_ACCESS_TOKEN and WHATSAPP_PHONE_NUMBER_ID are required.");
  }
  await sendDayReportFor(db, {
    accessToken,
    phoneNumberId,
    recipient: kenyanE164(to),
    graphVersion: process.env.WHATSAPP_GRAPH_VERSION?.trim() || "v23.0",
    templateName: process.env.DAY_REPORT_TEMPLATE?.trim() || "thamani_day_summary_v1",
    languageCode: process.env.DAY_REPORT_TEMPLATE_LANGUAGE?.trim() || "en",
  }, businessDate);
  const record = await db.collection("whatsappDayReports").doc(businessDate).get();
  console.log(JSON.stringify({businessDate, ...record.data()}, null, 2));
}

main().catch((error) => {
  console.error(String(error));
  process.exitCode = 1;
});
