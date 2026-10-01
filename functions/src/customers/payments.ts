import {FieldValue, getFirestore} from "firebase-admin/firestore";
import type {Firestore, Transaction} from "firebase-admin/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {requireTenantMember} from "../core/authorization";
import {runIdempotentFirestoreTransaction} from "../core/idempotency";
import {
  requireDocumentId,
  requireObject,
  requireRequestId,
} from "../core/validation";
import {CUSTOMER_CREATE_ROLES} from "../operations/customers";
import {CUSTOMER_ID_SHAPE} from "./customerId";
import {balanceFields, isMoneyTender, MoneyTender, storedBalance} from "./credit";

/**
 * A customer paying back what they owe.
 *
 * **Taken by whoever is at the till, into their own drawer.** Any cashier may
 * take a repayment, and the money is part of what their shift should hold at
 * close: the payment names the shift, the shift must be the caller's own, and
 * the payment's business date is the shift's - read here from the shift
 * document, never from the device - so reconciliation adds it to the right
 * drawer on the right day.
 *
 * **A closed shift is accepted**, as a sale's is. A till takes the money with
 * no signal, closes its shift, and reaches the server an hour later; refusing
 * the payment then would leave money in a drawer and a debt on the customer
 * for the same shillings.
 *
 * **Overpaying is allowed and says so.** A customer who pays more than the
 * till knew they owed - two tills, one offline - is ahead, and their balance
 * goes below zero: the shop owes them, which is the truth, and their next
 * credit sale uses it up.
 *
 * **Once per payment ID.** The device names the payment, and a replay of the
 * same request answers off the stored result.
 */

export const CUSTOMER_PAYMENT_ROLES = CUSTOMER_CREATE_ROLES;

/** A single repayment may not exceed a hundred million of the major unit. */
export const MAXIMUM_CUSTOMER_PAYMENT_MINOR = 10_000_000_000;

const PAYMENT_ID_SHAPE = /^cp_[0-9a-f]{40}$/;

interface CustomerPaymentRequest {
  tenantId?: unknown;
  paymentId?: unknown;
  customerId?: unknown;
  amountMinor?: unknown;
  tender?: unknown;
  shiftId?: unknown;
}

export interface CustomerPaymentResponse {
  paymentId: string;
  customerId: string;
  balanceAfterMinor: number;
}

export interface CustomerPaymentInput {
  tenantId: string;
  paymentId: string;
  customerId: string;
  amountMinor: number;
  tender: MoneyTender;
  shiftId: string;
}

/** Reads one request, or refuses it naming what is wrong. */
export function readCustomerPaymentRequest(value: unknown): CustomerPaymentInput {
  const data = requireObject(value) as CustomerPaymentRequest;
  const tenantId = requireDocumentId(data.tenantId, "tenantId");
  const paymentId = requireRequestId(data.paymentId);
  if (!PAYMENT_ID_SHAPE.test(paymentId)) {
    throw new HttpsError("invalid-argument", "paymentId has an invalid format.");
  }
  const customerId = requireDocumentId(data.customerId, "customerId");
  if (!CUSTOMER_ID_SHAPE.test(customerId)) {
    throw new HttpsError("invalid-argument", "customerId has an invalid format.");
  }
  const amount = data.amountMinor;
  if (
    !Number.isSafeInteger(amount) ||
    (amount as number) <= 0 ||
    (amount as number) > MAXIMUM_CUSTOMER_PAYMENT_MINOR
  ) {
    throw new HttpsError(
      "invalid-argument",
      "amountMinor must be a whole number of minor units above zero."
    );
  }
  if (!isMoneyTender(data.tender)) {
    throw new HttpsError("invalid-argument", "tender must be cash, mpesa or card.");
  }
  const shiftId = requireDocumentId(data.shiftId, "shiftId");
  return {
    tenantId,
    paymentId,
    customerId,
    amountMinor: amount as number,
    tender: data.tender,
    shiftId,
  };
}

/** Records one repayment inside the caller's transaction. */
export async function applyCustomerPayment(
  db: Firestore,
  transaction: Transaction,
  input: CustomerPaymentInput,
  actorUid: string
): Promise<CustomerPaymentResponse> {
  const tenantRef = db.collection("tenants").doc(input.tenantId);
  const customerRef = tenantRef.collection("customers").doc(input.customerId);
  const shiftRef = tenantRef.collection("shifts").doc(input.shiftId);
  const paymentRef = tenantRef.collection("customer_payments").doc(input.paymentId);
  const [customer, shift, existing] = await transaction.getAll(
    customerRef,
    shiftRef,
    paymentRef
  );
  if (existing.exists) {
    throw new HttpsError("already-exists", "This payment was already recorded.");
  }
  if (!customer.exists) {
    throw new HttpsError("not-found", "The customer does not exist in this business.");
  }
  if (!shift.exists || shift.get("staffId") !== actorUid) {
    throw new HttpsError(
      "failed-precondition",
      "A payment is taken into your own shift. Open a shift and take it again."
    );
  }
  const businessDate = shift.get("businessDate");
  if (typeof businessDate !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(businessDate)) {
    throw new HttpsError("failed-precondition", "The shift has no business date.");
  }

  const before = storedBalance(customer);
  const after = before - input.amountMinor;
  const customerName = customer.get("name");
  transaction.create(paymentRef, {
    tenantId: input.tenantId,
    paymentId: input.paymentId,
    customerId: input.customerId,
    customerName: typeof customerName === "string" ? customerName : null,
    amountMinor: input.amountMinor,
    tender: input.tender,
    shiftId: input.shiftId,
    businessDate,
    recordedBy: actorUid,
    balanceBeforeMinor: before,
    balanceAfterMinor: after,
    createdAt: FieldValue.serverTimestamp(),
  });
  transaction.create(customerRef.collection("activity").doc(`payment-${input.paymentId}`), {
    kind: "payment",
    tenantId: input.tenantId,
    customerId: input.customerId,
    paymentId: input.paymentId,
    amountMinor: input.amountMinor,
    tender: input.tender,
    shiftId: input.shiftId,
    recordedBy: actorUid,
    credit: true,
    balanceChangeMinor: -input.amountMinor,
    balanceAfterMinor: after,
    createdAt: FieldValue.serverTimestamp(),
  });
  transaction.update(customerRef, {
    ...balanceFields(before, -input.amountMinor, FieldValue.serverTimestamp()),
    lastPaymentAt: FieldValue.serverTimestamp(),
  });
  return {
    paymentId: input.paymentId,
    customerId: input.customerId,
    balanceAfterMinor: after,
  };
}

/** Records a repayment. See the file comment. */
export const recordCustomerPayment = onCall<
  CustomerPaymentRequest,
  Promise<CustomerPaymentResponse>
>(async (
  request: CallableRequest<CustomerPaymentRequest>
): Promise<CustomerPaymentResponse> => {
  const input = readCustomerPaymentRequest(request.data);
  const db = getFirestore();
  const actor = await requireTenantMember(db, request, input.tenantId, CUSTOMER_PAYMENT_ROLES);
  return runIdempotentFirestoreTransaction(db, {
    actorUid: actor.uid,
    operation: "recordCustomerPayment",
    tenantId: input.tenantId,
    requestId: input.paymentId,
    input,
  }, async (transaction) => {
    const current = await requireTenantMember(
      db,
      request,
      input.tenantId,
      CUSTOMER_PAYMENT_ROLES,
      transaction
    );
    return applyCustomerPayment(db, transaction, input, current.uid);
  });
});
