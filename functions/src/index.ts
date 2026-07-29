import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { getFirestore, Query, DocumentData } from "firebase-admin/firestore";
admin.initializeApp();
// ── Request / response types ─────────────────────────────────────────────────

interface ComparisonRequest {
  previousStartDate: string;  // "yyyy-MM-dd", inclusive
  previousEndDate: string;    // "yyyy-MM-dd", inclusive
  soldBy?: string;            // staff name, or "All Staff" / omitted
  category?: string;          // category name, or "All Categories" / omitted
}

interface PeriodMetrics {
  sales: number;
  profit: number;
  transactions: number;
}

interface ComparisonResponse {
  previous: PeriodMetrics;
}

// ── Firestore document shapes ────────────────────────────────────────────────

interface SaleItem {
  productName?: string;
  name?: string;
  quantity?: number;
  price?: number;
}

interface SaleDocument {
  total?: number;
  totalAmount?: number;
  businessDate?: string;
  soldBy?: string;
  items?: SaleItem[];
}

interface AlcoholDocument {
  name?: string;
  buyingprice?: number;
  buyingPrice?: number;
  category?: string;
}

// ── Validation helper ────────────────────────────────────────────────────────

const DATE_REGEX = /^\d{4}-\d{2}-\d{2}$/;

function validateDates(start: string, end: string): void {
  if (!DATE_REGEX.test(start) || !DATE_REGEX.test(end)) {
    throw new HttpsError(
      "invalid-argument",
      "Dates must be in yyyy-MM-dd format."
    );
  }
  if (start > end) {
    throw new HttpsError(
      "invalid-argument",
      "previousStartDate must not be after previousEndDate."
    );
  }
}

// ── Cloud function ───────────────────────────────────────────────────────────

/**
 * getSalesComparison
 *
 * Computes previous-period sales, profit, and transaction count for the
 * Flutter Reports page metric-card percentage-change comparisons.
 *
 * Runs server-side so the heavy aggregation loop doesn't block the device.
 */
export const getSalesComparison = onCall(
  async (request: CallableRequest<ComparisonRequest>): Promise<ComparisonResponse> => {
    const {
      previousStartDate,
      previousEndDate,
      soldBy = "",
      category = "",
    } = request.data;

    // ── Validate ─────────────────────────────────────────────────────────────
    if (!previousStartDate || !previousEndDate) {
      throw new HttpsError(
        "invalid-argument",
        "previousStartDate and previousEndDate are required."
      );
    }

    validateDates(previousStartDate, previousEndDate);

    const db = getFirestore();

    // ── Build sales query ─────────────────────────────────────────────────────
    // businessDate is a "yyyy-MM-dd" string field — lexicographic comparison
    // works correctly for ISO dates, so no Timestamp conversion needed.
    let salesQuery: Query<DocumentData> = db
      .collection("alcoholsales")
      .where("businessDate", ">=", previousStartDate)
      .where("businessDate", "<=", previousEndDate);

    // Push soldBy to Firestore when possible to reduce transferred documents.
    const filterBySoldBy = soldBy !== "" && soldBy !== "All Staff";
    if (filterBySoldBy) {
      salesQuery = salesQuery.where("soldBy", "==", soldBy);
    }

    // ── Fetch sales + inventory concurrently ──────────────────────────────────
    const [salesSnapshot, alcoholSnapshot] = await Promise.all([
      salesQuery.get(),
      db.collection("alcohol").get(),
    ]);

    // ── Build lookup maps from the alcohol collection ─────────────────────────
    const buyingPrices = new Map<string, number>();   // lowercase name → buying price
    const productCategory = new Map<string, string>(); // lowercase name → category

    for (const doc of alcoholSnapshot.docs) {
      const d = doc.data() as AlcoholDocument;
      const name = (d.name ?? "").toLowerCase().trim();
      if (!name) continue;

      buyingPrices.set(name, Number(d.buyingprice ?? d.buyingPrice ?? 0));
      productCategory.set(name, d.category ?? "");
    }

    // ── Aggregate metrics ─────────────────────────────────────────────────────
    const filterByCategory = category !== "" && category !== "All Categories";

    let sales = 0;
    let cost = 0;
    let transactions = 0;

    for (const doc of salesSnapshot.docs) {
      const data = doc.data() as SaleDocument;
      const total = Number(data.total ?? data.totalAmount ?? 0);
      const items: SaleItem[] = Array.isArray(data.items) ? data.items : [];

      // Category filter — include the transaction only if ≥1 item matches.
      if (filterByCategory) {
        const hasCategory = items.some((item) => {
          const pName = (item.productName ?? item.name ?? "")
            .toString()
            .toLowerCase()
            .trim();
          return productCategory.get(pName) === category;
        });
        if (!hasCategory) continue;
      }

      sales += total;
      transactions++;

      for (const item of items) {
        const productName = (item.productName ?? item.name ?? "")
          .toString()
          .toLowerCase()
          .trim();
        const quantity = Number(item.quantity ?? 1);
        const buyingPrice = buyingPrices.get(productName) ?? 0;
        cost += buyingPrice * quantity;
      }
    }

    return {
      previous: {
        sales,
        profit: sales - cost,
        transactions,
      },
    };
  }
);
export const createStaffUser = onCall(async (request) => {
    // Ensure caller is authenticated
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "You must be logged in."
      );
    }

    const callerUid = request.auth.uid;

    // Check if caller is admin
    const callerDoc = await admin
      .firestore()
      .collection("staff")
      .doc(callerUid)
      .get();

    if (!callerDoc.exists) {
      throw new HttpsError(
        "permission-denied",
        "User record not found."
      );
    }

    const callerData = callerDoc.data();
    if (!callerData?.role || callerData.role.toLowerCase() !== "admin") {
      throw new HttpsError(
        "permission-denied",
        "Only admins can create staff users."
      );
    }

    // Extract incoming data
    const { email, password, name, phone, role, status } = request.data;

    // Validate required fields
    if (!email || !password || !name) {
      throw new HttpsError(
        "invalid-argument",
        "Name, email and password are required."
      );
    }

    // Validate email format
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email.trim())) {
      throw new HttpsError(
        "invalid-argument",
        "Invalid email address."
      );
    }

    // Validate password length
    if (password.length < 6) {
      throw new HttpsError(
        "invalid-argument",
        "Password must be at least 6 characters."
      );
    }

    // Validate role exists and is a string before normalizing
    if (!role || typeof role !== "string") {
      throw new HttpsError(
        "invalid-argument",
        "Role is required."
      );
    }

    const allowedRoles = ["Manager", "Cashier", "Admin"];
    const normalizedRole =
      role.substring(0, 1).toUpperCase() + role.substring(1).toLowerCase();

    if (!allowedRoles.includes(normalizedRole)) {
      throw new HttpsError(
        "invalid-argument",
        "Invalid role. Allowed roles are: Manager, Cashier."
      );
    }

    // Validate status if provided
    const allowedStatuses = ["Active", "Inactive"];
    const normalizedStatus = status || "Active";
    if (!allowedStatuses.includes(normalizedStatus)) {
      throw new HttpsError(
        "invalid-argument",
        "Invalid status. Allowed statuses are: Active, Inactive."
      );
    }

    // Create Firebase Auth user
    let userRecord: admin.auth.UserRecord;
    try {
      userRecord = await admin.auth().createUser({
        email: email.trim(),
        password: password,
        displayName: name.trim(),
      });
    } catch (authError: any) {
      console.error("Firebase Auth creation error:", authError);

      if (authError.code === "auth/email-already-exists") {
        throw new HttpsError(
          "already-exists",
          "An account already exists for this email."
        );
      }
      if (authError.code === "auth/invalid-email") {
        throw new HttpsError(
          "invalid-argument",
          "Invalid email address."
        );
      }

      throw new HttpsError(
        "internal",
        authError.message || "Failed to create authentication user."
      );
    }

    // Attempt Firestore write — rollback Auth user if it fails
    try {
      await admin
        .firestore()
        .collection("staff")
        .doc(userRecord.uid)
        .set({
          uid: userRecord.uid,
          name: name.trim(),
          email: email.trim(),
          phone: phone ? phone.trim() : "",
          role: normalizedRole,
          status: normalizedStatus,
          lastLogin: null,
          avatarInitials: getInitials(name),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    } catch (firestoreError: any) {
      console.error(
        "Firestore write failed, rolling back Auth user:",
        firestoreError
      );

      try {
        await admin.auth().deleteUser(userRecord.uid);
        console.log("Auth user rollback successful:", userRecord.uid);
      } catch (rollbackError: any) {
        console.error(
          "CRITICAL: Auth rollback failed. Orphaned UID:",
          userRecord.uid,
          rollbackError
        );

        try {
          await admin.firestore().collection("orphaned_auth_users").add({
            uid: userRecord.uid,
            email: email.trim(),
            reason: "Firestore write failed during createStaffUser",
            firestoreError: firestoreError.message,
            rollbackError: rollbackError.message,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        } catch (logError) {
          console.error(
            "CRITICAL: Failed to log orphaned user to Firestore:",
            logError
          );
        }
      }

      throw new HttpsError(
        "internal",
        "Failed to save user record. Please try again."
      );
    }

    return {
      success: true,
      uid: userRecord.uid,
      message: "Staff user created successfully",
    };
  }
);
export const toggleStaffStatus = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "You must be logged in.");
  }

  const callerUid = request.auth.uid;

  const callerDoc = await admin
    .firestore()
    .collection("staff")
    .doc(callerUid)
    .get();

  if (!callerDoc.exists) {
    throw new HttpsError("permission-denied", "User record not found.");
  }

  const callerData = callerDoc.data();
  if (!callerData?.role || callerData.role.toLowerCase() !== "admin") {
    throw new HttpsError(
      "permission-denied",
      "Only admins can change user status."
    );
  }

  const { uid } = request.data;

  if (!uid || typeof uid !== "string") {
    throw new HttpsError("invalid-argument", "User ID is required.");
  }

  if (uid === callerUid) {
    throw new HttpsError(
      "invalid-argument",
      "You cannot change your own status."
    );
  }

  const targetDoc = await admin
    .firestore()
    .collection("staff")
    .doc(uid)
    .get();

  if (!targetDoc.exists) {
    throw new HttpsError("not-found", "Staff user not found.");
  }

  const targetData = targetDoc.data();
  const currentStatus = targetData?.status;

  if (!["Active", "Inactive"].includes(currentStatus)) {
    throw new HttpsError("internal", "User has an invalid current status.");
  }

  const newStatus = currentStatus === "Active" ? "Inactive" : "Active";
  const isDisabled = newStatus === "Inactive";

  // Disable or enable in Firebase Auth
  await admin.auth().updateUser(uid, { disabled: isDisabled });

  // Update Firestore status
  await admin.firestore().collection("staff").doc(uid).update({
    status: newStatus,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {
    success: true,
    newStatus,
    message: `User ${isDisabled ? "deactivated" : "activated"} successfully`,
  };
});
// Helper function
function getInitials(name: string): string {
  if (!name) return "";
  const parts = name.trim().split(" ");
  if (parts.length === 1) {
    return parts[0][0].toUpperCase();
  }
  return parts[0][0].toUpperCase() + parts[1][0].toUpperCase();
}