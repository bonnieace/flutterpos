import {
  AccountType,
  RootUserRecord,
} from "../core/model";
import {
  FieldValue,
  Firestore,
  Transaction,
} from "firebase-admin/firestore";

export type IdentityTransition = NonNullable<RootUserRecord["identityTransition"]>;

export type IdentityTransitionErrorCode =
  | "root-user-not-found"
  | "root-user-inactive"
  | "unexpected-account-type"
  | "identity-transition-conflict"
  | "identity-transition-not-held";

export class IdentityTransitionError extends Error {
  constructor(
    readonly code: IdentityTransitionErrorCode,
    message: string
  ) {
    super(message);
    this.name = "IdentityTransitionError";
  }
}

export interface TransactionAuditMerge {
  documentPath: string;
  data: Record<string, unknown>;
}

export interface AcquireIdentityTransitionOptions {
  targetUid: string;
  transition: IdentityTransition;
  expectedAccountType: AccountType;
  resumableAccountTypes?: readonly AccountType[];
  audit?: TransactionAuditMerge;
}

export interface AcquiredIdentityTransition {
  user: RootUserRecord;
  resumed: boolean;
}

export interface MutateHeldIdentityTransitionOptions {
  targetUid: string;
  expectedTransition: IdentityTransition;
  expectedAccountTypes?: readonly AccountType[];
  rootUpdates?: Record<string, unknown>;
  audit?: TransactionAuditMerge;
}

function mergeAudit(
  db: Firestore,
  transaction: Transaction,
  audit: TransactionAuditMerge | undefined
): void {
  if (!audit) return;
  transaction.set(db.doc(audit.documentPath), audit.data, {merge: true});
}

function activeRootUser(
  exists: boolean,
  data: RootUserRecord | undefined,
  targetUid: string
): RootUserRecord {
  if (!exists || !data) {
    throw new IdentityTransitionError(
      "root-user-not-found",
      `Root user ${targetUid} does not exist.`
    );
  }
  if (data.globalStatus !== "active") {
    throw new IdentityTransitionError(
      "root-user-inactive",
      `Root user ${targetUid} is not active.`
    );
  }
  return data;
}

function assertExpectedAccountType(
  user: RootUserRecord,
  expectedAccountTypes: readonly AccountType[] | undefined,
  targetUid: string
): void {
  if (expectedAccountTypes && (
    !user.accountType || !expectedAccountTypes.includes(user.accountType)
  )) {
    throw new IdentityTransitionError(
      "unexpected-account-type",
      `Root user ${targetUid} has an unexpected account type.`
    );
  }
}

/**
 * Acquires a root-level identity lock. Re-entering the same transition is
 * allowed only for explicitly listed account types so an interrupted saga can
 * resume without weakening the initial-state guard.
 */
export async function acquireIdentityTransition(
  db: Firestore,
  options: AcquireIdentityTransitionOptions
): Promise<AcquiredIdentityTransition> {
  const userRef = db.collection("users").doc(options.targetUid);

  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(userRef);
    const user = activeRootUser(
      snapshot.exists,
      snapshot.exists ? snapshot.data() as RootUserRecord : undefined,
      options.targetUid
    );

    if (user.identityTransition === options.transition) {
      assertExpectedAccountType(
        user,
        options.resumableAccountTypes ?? [options.expectedAccountType],
        options.targetUid
      );
      mergeAudit(db, transaction, options.audit);
      return {user, resumed: true};
    }

    if (user.identityTransition) {
      throw new IdentityTransitionError(
        "identity-transition-conflict",
        `Root user ${options.targetUid} already has an identity transition.`
      );
    }
    assertExpectedAccountType(user, [options.expectedAccountType], options.targetUid);

    transaction.update(userRef, {
      identityTransition: options.transition,
      updatedAt: FieldValue.serverTimestamp(),
    });
    mergeAudit(db, transaction, options.audit);
    return {user, resumed: false};
  });
}

/** Updates a root record only while the caller's expected transition is held. */
export async function updateRootDuringIdentityTransition(
  db: Firestore,
  options: MutateHeldIdentityTransitionOptions
): Promise<RootUserRecord> {
  const userRef = db.collection("users").doc(options.targetUid);

  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(userRef);
    const user = activeRootUser(
      snapshot.exists,
      snapshot.exists ? snapshot.data() as RootUserRecord : undefined,
      options.targetUid
    );
    if (user.identityTransition !== options.expectedTransition) {
      throw new IdentityTransitionError(
        "identity-transition-not-held",
        `Root user ${options.targetUid} no longer holds the expected transition.`
      );
    }
    assertExpectedAccountType(user, options.expectedAccountTypes, options.targetUid);

    transaction.update(userRef, {
      ...(options.rootUpdates ?? {}),
      updatedAt: FieldValue.serverTimestamp(),
    });
    mergeAudit(db, transaction, options.audit);
    return user;
  });
}

/**
 * Clears a transition transactionally after verifying the active root, exact
 * transition value, and (when supplied) account type. The optional audit merge
 * commits atomically with the clear.
 */
export async function clearIdentityTransition(
  db: Firestore,
  options: MutateHeldIdentityTransitionOptions
): Promise<RootUserRecord> {
  const userRef = db.collection("users").doc(options.targetUid);

  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(userRef);
    const user = activeRootUser(
      snapshot.exists,
      snapshot.exists ? snapshot.data() as RootUserRecord : undefined,
      options.targetUid
    );
    if (user.identityTransition !== options.expectedTransition) {
      throw new IdentityTransitionError(
        "identity-transition-not-held",
        `Root user ${options.targetUid} no longer holds the expected transition.`
      );
    }
    assertExpectedAccountType(user, options.expectedAccountTypes, options.targetUid);

    transaction.update(userRef, {
      ...(options.rootUpdates ?? {}),
      identityTransition: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    mergeAudit(db, transaction, options.audit);
    return user;
  });
}
