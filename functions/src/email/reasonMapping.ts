export const BREVO_REASON_MAPPING_VERSION = "brevo-v1";

export type NormalizedEmailEventType =
  | "requested"
  | "delivered"
  | "opened"
  | "clicked"
  | "deferred"
  | "provider_error"
  | "soft_bounce"
  | "hard_bounce"
  | "invalid_recipient"
  | "blocked"
  | "spam_complaint"
  | "unsubscribed";

export type ProviderReasonClass =
  | "none"
  | "hard_bounce"
  | "invalid_recipient"
  | "spam_complaint"
  | "permanent_provider_block"
  | "temporary_mailbox"
  | "temporary_rate_limit"
  | "temporary_policy"
  | "temporary_provider"
  | "unknown_temporary";

export type SuppressionCategory =
  | "hard_bounce"
  | "invalid_recipient"
  | "spam_complaint"
  | "permanent_provider_block";

export interface DeliveryClassification {
  mappingVersion: typeof BREVO_REASON_MAPPING_VERSION;
  eventType: NormalizedEmailEventType;
  normalizedReasonCode: string;
  reasonClass: ProviderReasonClass;
  disposition: "success" | "informational" | "temporary_failure" | "permanent_failure";
  suppressionCategory?: SuppressionCategory;
}

const EVENT_ALIASES: Readonly<Record<string, NormalizedEmailEventType>> = {
  request: "requested",
  requested: "requested",
  delivered: "delivered",
  opened: "opened",
  unique_opened: "opened",
  click: "clicked",
  clicked: "clicked",
  deferred: "deferred",
  error: "provider_error",
  soft_bounce: "soft_bounce",
  hard_bounce: "hard_bounce",
  invalid_email: "invalid_recipient",
  invalid_recipient: "invalid_recipient",
  blocked: "blocked",
  spam: "spam_complaint",
  complaint: "spam_complaint",
  spam_complaint: "spam_complaint",
  unsubscribe: "unsubscribed",
  unsubscribed: "unsubscribed",
};

const REASON_ALIASES: Readonly<Record<string, string>> = {
  hard_bounce: "hard_bounce",
  prior_hard_bounce: "prior_hard_bounce",
  spam_complaint: "spam_complaint",
  prior_spam_complaint: "prior_spam_complaint",
  complaint: "spam_complaint",
  invalid: "invalid_recipient",
  invalid_email: "invalid_recipient",
  invalid_recipient: "invalid_recipient",
  recipient_not_found: "recipient_not_found",
  mailbox_does_not_exist: "mailbox_does_not_exist",
  unknown_user: "unknown_user",
  mailbox_full: "mailbox_full",
  quota_exceeded: "mailbox_full",
  greylisted: "greylisted",
  greylisting: "greylisted",
  rate_limit: "rate_limited",
  rate_limited: "rate_limited",
  timeout: "provider_timeout",
  provider_timeout: "provider_timeout",
  temporary_policy: "temporary_policy",
  reputation: "temporary_reputation",
  temporary_reputation: "temporary_reputation",
  connection_failure: "connection_failure",
};

const INVALID_RECIPIENT_REASONS = new Set([
  "invalid_recipient",
  "recipient_not_found",
  "mailbox_does_not_exist",
  "unknown_user",
]);
const COMPLAINT_REASONS = new Set(["spam_complaint", "prior_spam_complaint"]);
const HARD_BOUNCE_REASONS = new Set(["hard_bounce", "prior_hard_bounce"]);

function canonicalToken(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const token = value.trim().toLowerCase().replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
  return token || undefined;
}

export function normalizeBrevoEventType(value: unknown): NormalizedEmailEventType | undefined {
  const token = canonicalToken(value);
  return token ? EVENT_ALIASES[token] : undefined;
}

/** Returns a finite reason code. Arbitrary provider text is never retained. */
export function normalizeBrevoReasonCode(value: unknown): string {
  const token = canonicalToken(value);
  return token ? REASON_ALIASES[token] ?? "unknown" : "unknown";
}

function permanent(
  eventType: NormalizedEmailEventType,
  normalizedReasonCode: string,
  reasonClass: ProviderReasonClass,
  suppressionCategory: SuppressionCategory
): DeliveryClassification {
  return {
    mappingVersion: BREVO_REASON_MAPPING_VERSION,
    eventType,
    normalizedReasonCode,
    reasonClass,
    disposition: "permanent_failure",
    suppressionCategory,
  };
}

export function classifyBrevoEvent(
  rawEventType: unknown,
  rawReason: unknown
): DeliveryClassification | undefined {
  const eventType = normalizeBrevoEventType(rawEventType);
  if (!eventType) return undefined;
  const normalizedReasonCode = normalizeBrevoReasonCode(rawReason);

  if (eventType === "hard_bounce") {
    return permanent(eventType, normalizedReasonCode, "hard_bounce", "hard_bounce");
  }
  if (eventType === "invalid_recipient") {
    return permanent(
      eventType,
      normalizedReasonCode,
      "invalid_recipient",
      "invalid_recipient"
    );
  }
  if (eventType === "spam_complaint") {
    return permanent(
      eventType,
      normalizedReasonCode,
      "spam_complaint",
      "spam_complaint"
    );
  }
  if (eventType === "blocked") {
    if (COMPLAINT_REASONS.has(normalizedReasonCode)) {
      return permanent(
        eventType,
        normalizedReasonCode,
        "permanent_provider_block",
        "spam_complaint"
      );
    }
    if (HARD_BOUNCE_REASONS.has(normalizedReasonCode)) {
      return permanent(
        eventType,
        normalizedReasonCode,
        "permanent_provider_block",
        "hard_bounce"
      );
    }
    if (INVALID_RECIPIENT_REASONS.has(normalizedReasonCode)) {
      return permanent(
        eventType,
        normalizedReasonCode,
        "permanent_provider_block",
        "invalid_recipient"
      );
    }
  }

  if (eventType === "delivered") {
    return {
      mappingVersion: BREVO_REASON_MAPPING_VERSION,
      eventType,
      normalizedReasonCode,
      reasonClass: "none",
      disposition: "success",
    };
  }
  if (["requested", "opened", "clicked", "unsubscribed"].includes(eventType)) {
    return {
      mappingVersion: BREVO_REASON_MAPPING_VERSION,
      eventType,
      normalizedReasonCode,
      reasonClass: "none",
      disposition: "informational",
    };
  }

  let reasonClass: ProviderReasonClass = "unknown_temporary";
  if (normalizedReasonCode === "mailbox_full") reasonClass = "temporary_mailbox";
  if (normalizedReasonCode === "rate_limited") reasonClass = "temporary_rate_limit";
  if (["greylisted", "temporary_policy", "temporary_reputation"].includes(
    normalizedReasonCode
  )) reasonClass = "temporary_policy";
  if (["provider_timeout", "connection_failure"].includes(normalizedReasonCode)) {
    reasonClass = "temporary_provider";
  }
  return {
    mappingVersion: BREVO_REASON_MAPPING_VERSION,
    eventType,
    normalizedReasonCode,
    reasonClass,
    disposition: "temporary_failure",
  };
}
