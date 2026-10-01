import {createHash, createHmac, timingSafeEqual} from "node:crypto";
import type {WhatsappSendConfig} from "./config";

/**
 * A thin client for Meta's WhatsApp Business Cloud API.
 *
 * **Ported from carerota's `server/utils/whatsapp.ts`**, which already sends
 * from the same number; carerota itself is untouched. Two additions: a PDF is
 * uploaded first and named in the template's document header, and an error
 * says whether trying again could help.
 *
 * **Templates only, apart from the automatic reply.** A receipt is a message
 * the business starts, outside any 24-hour window the customer opened, and
 * Meta requires an approved template for that. Free text is used solely to
 * answer a message the customer sent, which is always inside the window that
 * message opened.
 */

export interface WhatsappTemplateMessage {
  to: string;
  templateName: string;
  languageCode: string;
  bodyParameters: string[];
  /** A document already uploaded with [uploadWhatsappMedia], for the header. */
  headerDocument?: {mediaId: string; filename: string};
}

export type WhatsappFetch = (url: string, options: {
  method: string;
  headers: Record<string, string>;
  body: string | FormData;
}) => Promise<{ok: boolean; status: number; json: () => Promise<unknown>}>;

const defaultFetch: WhatsappFetch = (url, options) =>
  fetch(url, options) as unknown as ReturnType<WhatsappFetch>;

/**
 * What a refused call says, and whether trying it again could change that.
 *
 * **Retryable is the network and Meta's own trouble** - a 5xx, a rate limit -
 * and nothing about the message. An unknown number, an unapproved template or
 * an expired token will be refused the same way every time, so a retry only
 * spends money and time.
 */
export class WhatsappSendError extends Error {
  constructor(
    message: string,
    readonly retryable: boolean,
    readonly code?: number
  ) {
    super(message);
  }
}

function graphUrl(config: WhatsappSendConfig, path: string): string {
  return `https://graph.facebook.com/${config.graphVersion}/${config.phoneNumberId}/${path}`;
}

async function refusal(
  response: {ok: boolean; status: number; json: () => Promise<unknown>},
  what: string
): Promise<WhatsappSendError> {
  const payload = await response.json().catch(() => ({})) as Record<string, unknown>;
  const error = (payload?.error ?? {}) as Record<string, unknown>;
  const message = typeof error.message === "string" ? error.message : `HTTP ${response.status}`;
  const code = typeof error.code === "number" ? error.code : undefined;
  // 429 and every 5xx are Meta's to recover from; 4xx is about the request.
  const retryable = response.status === 429 || response.status >= 500 ||
    code === 4 || code === 80007 || code === 130429 || code === 131016;
  return new WhatsappSendError(`${what}: ${message}`, retryable, code);
}

/** The request body for one template message. */
export function buildTemplatePayload(message: WhatsappTemplateMessage) {
  const components: Array<Record<string, unknown>> = [];
  if (message.headerDocument) {
    components.push({
      type: "header",
      parameters: [{
        type: "document",
        document: {
          id: message.headerDocument.mediaId,
          filename: message.headerDocument.filename,
        },
      }],
    });
  }
  if (message.bodyParameters.length) {
    components.push({
      type: "body",
      parameters: message.bodyParameters.map((text) => ({type: "text", text})),
    });
  }
  return {
    messaging_product: "whatsapp",
    recipient_type: "individual",
    to: message.to.replace(/^\+/, ""),
    type: "template",
    template: {
      name: message.templateName,
      language: {code: message.languageCode},
      ...(components.length ? {components} : {}),
    },
  };
}

/** Uploads one file and answers the media ID a message can name. */
export async function uploadWhatsappMedia(
  config: WhatsappSendConfig,
  file: {bytes: Uint8Array; mimeType: string; filename: string},
  fetchImpl: WhatsappFetch = defaultFetch
): Promise<string> {
  const form = new FormData();
  form.append("messaging_product", "whatsapp");
  form.append("type", file.mimeType);
  form.append(
    "file",
    // Copied so the part is backed by a plain `ArrayBuffer`, which is the
    // only buffer a `Blob` accepts.
    new Blob([new Uint8Array(file.bytes)], {type: file.mimeType}),
    file.filename
  );
  const response = await fetchImpl(graphUrl(config, "media"), {
    method: "POST",
    headers: {authorization: `Bearer ${config.accessToken}`},
    body: form,
  });
  if (!response.ok) throw await refusal(response, "WhatsApp media upload failed");
  const payload = await response.json().catch(() => ({})) as Record<string, unknown>;
  if (typeof payload.id !== "string" || !payload.id) {
    throw new WhatsappSendError("WhatsApp media upload returned no id.", true);
  }
  return payload.id;
}

/** Sends one template message and answers Meta's ID for it. */
export async function sendWhatsappTemplate(
  config: WhatsappSendConfig,
  message: WhatsappTemplateMessage,
  fetchImpl: WhatsappFetch = defaultFetch
): Promise<{providerMessageId: string}> {
  const response = await fetchImpl(graphUrl(config, "messages"), {
    method: "POST",
    headers: {
      "authorization": `Bearer ${config.accessToken}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(buildTemplatePayload(message)),
  });
  if (!response.ok) throw await refusal(response, "WhatsApp send failed");
  const payload = await response.json().catch(() => ({})) as Record<string, any>;
  const providerMessageId = payload?.messages?.[0]?.id;
  if (typeof providerMessageId !== "string" || !providerMessageId) {
    throw new WhatsappSendError("WhatsApp send returned no message id.", false);
  }
  return {providerMessageId};
}

/** Sends free text, only ever inside a window the customer opened. */
export async function sendWhatsappText(
  config: WhatsappSendConfig,
  to: string,
  body: string,
  fetchImpl: WhatsappFetch = defaultFetch
): Promise<void> {
  const response = await fetchImpl(graphUrl(config, "messages"), {
    method: "POST",
    headers: {
      "authorization": `Bearer ${config.accessToken}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      messaging_product: "whatsapp",
      recipient_type: "individual",
      to: to.replace(/^\+/, ""),
      type: "text",
      text: {preview_url: false, body},
    }),
  });
  if (!response.ok) throw await refusal(response, "WhatsApp reply failed");
}

/** Meta signs webhook bodies with HMAC-SHA256 of the App Secret. */
export function verifyWebhookSignature(
  rawBody: string | Buffer,
  signatureHeader: string | undefined,
  appSecret: string | undefined
): boolean {
  if (!appSecret || !signatureHeader?.startsWith("sha256=")) return false;
  const expected = createHmac("sha256", appSecret).update(rawBody).digest("hex");
  const provided = signatureHeader.slice("sha256=".length);
  const left = Buffer.from(provided, "utf8");
  const right = Buffer.from(expected, "utf8");
  return left.length === right.length && timingSafeEqual(left, right);
}

export interface WhatsappStatusUpdate {
  providerMessageId: string;
  status: "sent" | "delivered" | "read" | "failed";
  timestamp?: string;
  error?: string;
}

export interface WhatsappInboundMessage {
  from: string;
  messageId: string;
  type: string;
  text?: string;
}

/** The status updates and inbound messages in one webhook payload. */
export function parseWebhookPayload(payload: unknown): {
  statuses: WhatsappStatusUpdate[];
  inbound: WhatsappInboundMessage[];
} {
  const statuses: WhatsappStatusUpdate[] = [];
  const inbound: WhatsappInboundMessage[] = [];
  const entries = Array.isArray((payload as any)?.entry) ? (payload as any).entry : [];
  for (const entry of entries) {
    const changes = Array.isArray(entry?.changes) ? entry.changes : [];
    for (const change of changes) {
      const value = change?.value;
      if (change?.field !== "messages" || !value) continue;
      for (const status of Array.isArray(value.statuses) ? value.statuses : []) {
        const id = typeof status?.id === "string" ? status.id : "";
        const state = typeof status?.status === "string" ? status.status : "";
        if (!id || !["sent", "delivered", "read", "failed"].includes(state)) continue;
        statuses.push({
          providerMessageId: id,
          status: state as WhatsappStatusUpdate["status"],
          timestamp: typeof status?.timestamp === "string" ? status.timestamp : undefined,
          error: Array.isArray(status?.errors) && status.errors[0]?.message ?
            String(status.errors[0].message) : undefined,
        });
      }
      for (const message of Array.isArray(value.messages) ? value.messages : []) {
        const from = typeof message?.from === "string" ? message.from : "";
        const messageId = typeof message?.id === "string" ? message.id : "";
        if (!from || !messageId) continue;
        inbound.push({
          from,
          messageId,
          type: typeof message?.type === "string" ? message.type : "unknown",
          text: typeof message?.text?.body === "string" ? message.text.body : undefined,
        });
      }
    }
  }
  return {statuses, inbound};
}

/** E.164 with its plus, from what Meta sends (`254712345678`). */
export function e164FromWhatsapp(from: string): string | null {
  const digits = from.replace(/\D/g, "");
  return /^[1-9]\d{7,14}$/.test(digits) ? `+${digits}` : null;
}

/**
 * The number a delivery and a suppression are keyed by, without the number.
 *
 * **A digest, so the server's bookkeeping holds no phone number in the
 * clear.** These documents are server-only, and a digest is enough to answer
 * "has this number said STOP" without keeping a list of numbers that did.
 */
export function phoneHash(e164: string): string {
  return createHash("sha256").update(`uzapay-whatsapp-phone ${e164}`).digest("hex");
}

/** `+254•••678`: the dialling code's start and the last three digits. */
export function maskPhone(e164: string): string {
  return `${e164.slice(0, 4)}•••${e164.slice(-3)}`;
}
