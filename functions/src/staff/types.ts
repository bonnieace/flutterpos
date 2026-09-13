import {
  CanonicalStaffRecord,
  RootUserRecord,
  TenantRecord,
} from "../core/model";

export interface StoredStaffRecord extends CanonicalStaffRecord {
  createdAt?: unknown;
  joinedAt?: unknown;
  updatedAt?: unknown;
}

export interface StoredTenantRecord extends TenantRecord {
  updatedAt?: unknown;
}

export interface StoredInvitationRecord {
  createdAt?: unknown;
  uid?: unknown;
  tenantId?: unknown;
  invitationVersion?: unknown;
  invitationTokenHash?: unknown;
  invitationTokenKeyVersion?: unknown;
  invitationIssuedAt?: unknown;
  invitationExpiresAt?: unknown;
  invitationTokenUsedAt?: unknown;
  invitationStatus?: unknown;
  invitedEmail?: unknown;
  invitedBy?: unknown;
  latestDeliveryId?: unknown;
  credentialBootstrapRequired?: unknown;

  /**
   * Retired 2026-09-08, still read.
   *
   * It gated tokenless acceptance and decided the email's wording; it now does
   * neither, and `credentialBootstrapRequired` above does the second. Invitations
   * written before the change carry only this, so delivery falls back to it.
   */
  visibleAcceptanceAllowed?: unknown;
  identityOwnedByInvitation?: unknown;
  identityProvisioningOperationId?: unknown;
}

export interface StoredMirrorRecord {
  mirrorVersion?: unknown;
  createdAt?: unknown;
  joinedAt?: unknown;
  [key: string]: unknown;
}

export interface TargetIdentitySnapshot {
  root: RootUserRecord;
  hasPlatformClaim: boolean;
}

export interface DeliveryMetadata {
  deliveryId: string;
  status: "pending_enqueue";
}
