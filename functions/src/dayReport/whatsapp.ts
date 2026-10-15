/**
 * A thin client for Meta's WhatsApp Business Cloud API.
 *
 * Copied from UzaPay's `functions/src/whatsapp/client.ts` (multitenant app),
 * keeping only the template send and the media upload a document header needs.
 */

export interface WhatsappConfig {
  accessToken: string;
  phoneNumberId: string;
  graphVersion: string;
}

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
 * Retryable is the network and Meta's own trouble - a 5xx, a rate limit. An
 * unknown number, an unapproved template or an expired token is refused the
 * same way every time.
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

function graphUrl(config: WhatsappConfig, path: string): string {
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
  config: WhatsappConfig,
  file: {bytes: Uint8Array; mimeType: string; filename: string},
  fetchImpl: WhatsappFetch = defaultFetch
): Promise<string> {
  const form = new FormData();
  form.append("messaging_product", "whatsapp");
  form.append("type", file.mimeType);
  form.append(
    "file",
    // Copied so the part is backed by a plain `ArrayBuffer`, the only buffer
    // a `Blob` accepts.
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
  config: WhatsappConfig,
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
