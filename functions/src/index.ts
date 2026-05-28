import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
admin.initializeApp();

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