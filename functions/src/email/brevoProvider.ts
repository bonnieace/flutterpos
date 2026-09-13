import {
  EmailProvider,
  EmailProviderError,
  ProviderEmailMessage,
  ProviderSendResult,
} from "./contracts";
import {
  accountVerificationEmail,
  passwordResetEmail,
  platformAlertEmail,
  RenderedEmail,
} from "./templates";

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

/**
 * Picks the template and, for an alert, sanitises the two fields it is allowed
 * to print.
 *
 * The alert type is re-validated here rather than trusted from the caller:
 * anything that is not a short snake_case token is replaced with the generic
 * one, so a value that reached this far by another route cannot become markup
 * or leak a phrase somebody wrote elsewhere.
 */
function renderTemplate(message: ProviderEmailMessage): RenderedEmail {
  if (message.template === "password_reset") {
    return passwordResetEmail(message.actionUrl);
  }
  if (message.template === "account_verification") {
    return accountVerificationEmail(message.actionUrl);
  }
  const alertType = /^[a-z0-9_]{1,64}$/.test(
    message.redactedContext?.alertType ?? ""
  ) ? message.redactedContext?.alertType : undefined;
  const severity = message.redactedContext?.severity === "critical" ?
    "critical" : "attention";
  return platformAlertEmail(
    message.actionUrl,
    severity,
    alertType ?? "operator_action_required"
  );
}

function providerTag(message: ProviderEmailMessage): string {
  if (message.template === "password_reset") return "password-reset";
  if (message.template === "account_verification") return "account-verification";
  return "platform-alert";
}

function messageBody(
  message: ProviderEmailMessage,
  config: BrevoProviderConfiguration
): Record<string, unknown> {
  const rendered = renderTemplate(message);
  return {
    sender: {
      email: config.senderAddress,
      name: config.senderName,
    },
    to: [{email: message.recipient}],
    subject: rendered.subject,
    textContent: rendered.text,
    htmlContent: rendered.html,
    headers: {
      "Idempotency-Key": message.deliveryId,
      "X-Mailin-Track-Clicks": "0",
      "X-Mailin-Track-Opens": "0",
    },
    tags: [providerTag(message)],
  };
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
