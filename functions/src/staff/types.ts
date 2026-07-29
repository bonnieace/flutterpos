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
