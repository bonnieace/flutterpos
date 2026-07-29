export type EmailTemplate =
  | "password_reset"
  | "account_verification"
  | "platform_alert";

export interface ProviderEmailMessage {
  deliveryId: string;
  recipient: string;
  template: EmailTemplate;
  actionUrl: string;
  redactedContext?: {
    alertType: string;
    severity: string;
  };
}

export interface ProviderSendResult {
  provider: string;
  providerMessageId: string;
}

export interface EmailProvider {
  send(message: ProviderEmailMessage): Promise<ProviderSendResult>;
}

export class EmailProviderError extends Error {
  constructor(
    readonly safeCode: string,
    readonly retryable: boolean
  ) {
    super("The email provider did not accept the delivery.");
    this.name = "EmailProviderError";
  }
}

export interface PasswordResetIdentity {
  uid: string;
  email: string;
  disabled: boolean;
}

export interface PasswordResetIdentityGateway {
  findByEmail(normalizedEmail: string): Promise<PasswordResetIdentity | undefined>;
  createActionLink(normalizedEmail: string): Promise<string>;
}
