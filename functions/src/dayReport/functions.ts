import {onSchedule} from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import {FieldValue, Firestore, Timestamp, getFirestore} from "firebase-admin/firestore";
import {DayReportSendConfig, WHATSAPP_ACCESS_TOKEN, dayReportSendConfig} from "./config";
import {
  DayReport,
  REPORT_TIME_ZONE,
  ShiftInput,
  buildDayReport,
  previousBusinessDate,
  reportFilename,
  templateParameters,
} from "./report";
import {renderDayReportPdf} from "./reportPdf";
import {WhatsappSendError, sendWhatsappTemplate, uploadWhatsappMedia} from "./whatsapp";

/** One document per business date, so a date is reported once. */
export const DAY_REPORTS_COLLECTION = "whatsappDayReports";

/** A run that claimed a date and vanished frees it after this long. */
const STALE_CLAIM_MS = 15 * 60 * 1000;

function asDate(value: unknown): Date | null {
  return value instanceof Timestamp ? value.toDate() : null;
}

/** Reads the date's sales, shifts and the product list. */
export async function loadDayReport(db: Firestore, businessDate: string): Promise<DayReport> {
  const [sales, shifts, products] = await Promise.all([
    db.collection("alcoholsales").where("businessDate", "==", businessDate).get(),
    db.collection("shifts").where("businessDate", "==", businessDate).get(),
    db.collection("alcohol").get(),
  ]);
  return buildDayReport({
    businessDate,
    sales: sales.docs.map((doc) => ({...doc.data(), dateAdded: asDate(doc.get("dateAdded"))})),
    shifts: shifts.docs.map((doc): ShiftInput => {
      const data = doc.data();
      return {
        id: doc.id,
        staffName: data.staffName,
        status: data.status,
        startTime: asDate(data.startTime),
        endTime: asDate(data.endTime),
      };
    }),
    products: products.docs.map((doc) => ({
      id: doc.id,
      name: doc.get("name"),
      category: doc.get("category"),
    })),
  });
}

/**
 * Claims [businessDate] for this run. False where it was sent already, or
 * another run is sending it now.
 */
async function claim(db: Firestore, businessDate: string): Promise<boolean> {
  const ref = db.collection(DAY_REPORTS_COLLECTION).doc(businessDate);
  return db.runTransaction(async (transaction) => {
    const existing = await transaction.get(ref);
    const status = existing.get("status");
    if (status === "sent") return false;
    const startedAt = asDate(existing.get("startedAt"));
    if (status === "sending" && startedAt &&
      Date.now() - startedAt.getTime() < STALE_CLAIM_MS) {
      return false;
    }
    transaction.set(ref, {
      status: "sending",
      startedAt: FieldValue.serverTimestamp(),
      attempts: FieldValue.increment(1),
    }, {merge: true});
    return true;
  });
}

/**
 * Builds and sends [businessDate]'s report. A refusal that a retry could fix
 * is thrown, so the scheduler tries again; any other is recorded and logged.
 */
export async function sendDayReportFor(
  db: Firestore,
  config: DayReportSendConfig,
  businessDate: string,
  now: Date = new Date()
): Promise<void> {
  if (!(await claim(db, businessDate))) {
    logger.info("dayReport.already_handled", {businessDate});
    return;
  }
  const ref = db.collection(DAY_REPORTS_COLLECTION).doc(businessDate);
  try {
    const report = await loadDayReport(db, businessDate);
    const pdf = await renderDayReportPdf(report, {generatedAt: now});
    const filename = reportFilename(businessDate);
    const mediaId = await uploadWhatsappMedia(config, {
      bytes: pdf,
      mimeType: "application/pdf",
      filename,
    });
    const {providerMessageId} = await sendWhatsappTemplate(config, {
      to: config.recipient,
      templateName: config.templateName,
      languageCode: config.languageCode,
      bodyParameters: templateParameters(report),
      headerDocument: {mediaId, filename},
    });
    await ref.set({
      status: "sent",
      sentAt: FieldValue.serverTimestamp(),
      providerMessageId,
      totalSales: report.totalSales,
      saleCount: report.saleCount,
      error: FieldValue.delete(),
    }, {merge: true});
    logger.info("dayReport.sent", {businessDate, providerMessageId});
  } catch (error) {
    const retryable = !(error instanceof WhatsappSendError) || error.retryable;
    await ref.set({
      status: "failed",
      failedAt: FieldValue.serverTimestamp(),
      error: String(error),
      retryable,
    }, {merge: true});
    logger.error("dayReport.failed", {businessDate, retryable, error: String(error)});
    if (retryable) throw error;
  }
}

/**
 * At 08:00 Nairobi time, sends the previous business date's report to the
 * configured number. The till closes a business date at 05:00, so by 08:00
 * every shift that is going to be closed normally has been.
 */
export const sendDailyWhatsappReport = onSchedule(
  {
    schedule: "0 8 * * *",
    timeZone: REPORT_TIME_ZONE,
    secrets: [WHATSAPP_ACCESS_TOKEN],
    retryCount: 3,
    timeoutSeconds: 120,
    memory: "512MiB",
  },
  async () => {
    const config = dayReportSendConfig();
    const businessDate = previousBusinessDate(new Date());
    if (!config) {
      logger.info("dayReport.skipped_not_configured", {businessDate});
      return;
    }
    await sendDayReportFor(getFirestore(), config, businessDate);
  }
);
