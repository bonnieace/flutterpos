import {
  EmailProvider,
  EmailProviderError,
  ProviderEmailMessage,
  ProviderSendResult,
} from "./contracts";

export interface BrevoProviderConfiguration {
  apiKey: string;
  senderAddress: string;
  senderName: string;
}

type FetchLike = typeof fetch;

function requireProviderConfiguration(config: BrevoProviderConfiguration): void {
  if (
    Buffer.byteLength(config.apiKey, "utf8") < 16 ||
    !config.senderAddress.includes("@") ||
    !config.senderName.trim()
  ) {
    throw new EmailProviderError("provider_not_configured", false);
  }
}

function messageBody(
  message: ProviderEmailMessage,
  config: BrevoProviderConfiguration
): Record<string, unknown> {
  let subject: string;
  let textContent: string;
  let htmlContent: string;
  let tag: string;
  if (message.template === "password_reset") {
    subject = "Reset your ChillTent password";
    textContent = `Use this secure link to reset your password: ${message.actionUrl}`;
    htmlContent = "<p>Use the secure password-reset link sent with this message.</p>" +
      `<p><a href="${htmlEscape(message.actionUrl)}">Reset password</a></p>`;
    tag = "password-reset";
  } else if (message.template === "account_verification") {
    subject = "Verify your ChillTent account";
    textContent = `Use this secure link to verify your account: ${message.actionUrl}`;
    htmlContent = "<p>Use the secure verification link sent with this message.</p>" +
      `<p><a href="${htmlEscape(message.actionUrl)}">Verify account</a></p>`;
    tag = "account-verification";
  } else {
    const alertType = /^[a-z0-9_]{1,64}$/.test(
      message.redactedContext?.alertType ?? ""
    ) ? message.redactedContext?.alertType : "operator_action_required";
    const severity = message.redactedContext?.severity === "critical" ?
      "critical" : "attention";
    subject = "ChillTent platform operator action required";
    textContent = `A ${severity} platform alert (${alertType}) requires review. ` +
      `Open the operator dashboard: ${message.actionUrl}`;
    htmlContent = `<p>A ${htmlEscape(severity)} platform alert ` +
      `(${htmlEscape(alertType ?? "operator_action_required")}) requires review.</p>` +
      `<p><a href="${htmlEscape(message.actionUrl)}">Open operator dashboard</a></p>`;
    tag = "platform-alert";
  }
  return {
    sender: {
      email: config.senderAddress,
      name: config.senderName,
    },
    to: [{email: message.recipient}],
    subject,
    textContent,
    htmlContent,
    headers: {
      "Idempotency-Key": message.deliveryId,
      "X-Mailin-Track-Clicks": "0",
      "X-Mailin-Track-Opens": "0",
    },
    tags: [tag],
  };
}

function htmlEscape(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function retryableHttpStatus(status: number): boolean {
  return status === 408 || status === 409 || status === 425 ||
    status === 429 || status >= 500;
}

export class BrevoEmailProvider implements EmailProvider {
  constructor(
    private readonly config: BrevoProviderConfiguration,
    private readonly fetchImplementation: FetchLike = fetch
  ) {}

  async send(message: ProviderEmailMessage): Promise<ProviderSendResult> {
    requireProviderConfiguration(this.config);
    let response: Response;
    try {
      response = await this.fetchImplementation("https://api.brevo.com/v3/smtp/email", {
        method: "POST",
        headers: {
          accept: "application/json",
          "api-key": this.config.apiKey,
          "content-type": "application/json",
        },
        body: JSON.stringify(messageBody(message, this.config)),
      });
    } catch {
      throw new EmailProviderError("provider_transport_failure", true);
    }
    if (!response.ok) {
      throw new EmailProviderError(
        `provider_http_${response.status}`,
        retryableHttpStatus(response.status)
      );
    }

    let body: unknown;
    try {
      body = await response.json();
    } catch {
      throw new EmailProviderError("provider_invalid_response", true);
    }
    const providerMessageId = body && typeof body === "object" &&
      typeof (body as {messageId?: unknown}).messageId === "string" ?
      (body as {messageId: string}).messageId : "";
    if (!providerMessageId || providerMessageId.length > 256) {
      throw new EmailProviderError("provider_invalid_response", true);
    }
    return {provider: "brevo", providerMessageId};
  }
}
