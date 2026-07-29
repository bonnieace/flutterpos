import {HttpsError} from "firebase-functions/v2/https";
import {SuppressionCategory} from "./reasonMapping";

export interface SuppressionForReview {
  category: SuppressionCategory;
  status: "active" | "cleared";
}

export function assertSuppressionClearAllowed(
  records: readonly SuppressionForReview[],
  confirmation: string | undefined,
  evidenceReference: string | undefined
): void {
  const active = records.filter((record) => record.status === "active");
  if (active.some((record) => record.category === "spam_complaint")) {
    if (
      confirmation !== "clear_spam_complaint" ||
      !evidenceReference ||
      evidenceReference.trim().length < 8
    ) {
      throw new HttpsError(
        "failed-precondition",
        "Complaint suppression requires explicit complaint confirmation and evidence."
      );
    }
    return;
  }
  if (active.length > 0 && ![
    "address_corrected",
    "address_independently_verified",
  ].includes(confirmation ?? "")) {
    throw new HttpsError(
      "failed-precondition",
      "Clearing requires confirmation that the address was corrected or verified."
    );
  }
}
