/// The words six tenancy surfaces say a role and a standing in.
///
/// The staff directory, the business selector, the branding panel, the invited
/// person's own acceptance screen and the two role choosers all render the same
/// three enums - so the wording lives here rather than in any of them, on the
/// rule the stock and reconciliation sweeps established: a shared wording module
/// is worth reaching for the moment two surfaces render one document.
///
/// **Opened by `design.md` §11 step 11 on 2026-08-15**, and the defect it closes
/// is §8 rule 1 rather than a drift between the six. Every one of them was
/// painting a `wireValue` - `admin`, `active`, `sent` - which is the *system's*
/// name for a thing, on a screen a shopkeeper reads. They agreed with each other
/// perfectly and were all wrong in the same way.
///
/// **Nothing here is invented.** `administrator` is the word this app's own
/// refusal sentences already use - "Only an owner, administrator, or manager may
/// change the catalog" - and `Deactivated` is the past tense of the action that
/// produces it, which is §8 rule 4. Where a wire value had no existing prose to
/// read a word off, the word states what is true rather than translating the
/// token: an invitation whose delivery has not run yet reads `Not sent yet`, not
/// `Pending`.
library;

import 'tenant_staff_directory.dart';
import 'tenant_types.dart';

/// What a person holding this role is called.
///
/// Sentence case per §8 rule 7, and a noun rather than a permission: a directory
/// row states what somebody *is*, and what they may do is stated by whether an
/// action is offered to them at all.
String tenantRoleLabel(TenantRole role) => switch (role) {
  TenantRole.owner => 'Owner',
  TenantRole.admin => 'Administrator',
  TenantRole.manager => 'Manager',
  TenantRole.cashier => 'Cashier',
};

/// Where this person stands with the business.
///
/// `pending` is read as **Invited** rather than translated as "Pending", because
/// pending is a fact about a record and invited is a fact about a person. The
/// invitation's own progress is a separate attribute beside it, and stating both
/// as "pending" is how one word came to mean two things on one row.
String membershipStatusLabel(MembershipStatus status) => switch (status) {
  MembershipStatus.pending => 'Invited',
  MembershipStatus.active => 'Active',
  // The past tense of the action that produces it - the row's own control says
  // `Deactivate` - which is §8 rule 4's verb persisting into the result.
  MembershipStatus.inactive => 'Deactivated',
};

/// The standing announced to a screen reader, which owes a noun for the figure.
///
/// §9 requires the badge carry a label; a bare `Invited` announced on its own
/// says nothing about what was invited, so the sentence names the record.
String membershipStatusSemanticLabel(MembershipStatus status) =>
    'Membership: ${membershipStatusLabel(status)}';

/// How far this person's invitation has got.
///
/// Two of the five state what has **not** happened, which is §8 rule 2 - state
/// what is true, then what it means - rather than a status word that leaves a
/// person guessing whether an email is on its way.
String staffInvitationStatusLabel(TenantStaffInvitationStatus status) =>
    switch (status) {
      TenantStaffInvitationStatus.pending => 'Not sent yet',
      TenantStaffInvitationStatus.sent => 'Sent',
      TenantStaffInvitationStatus.accepted => 'Accepted',
      TenantStaffInvitationStatus.cancelled => 'Cancelled',
      TenantStaffInvitationStatus.expired => 'Expired',
    };
