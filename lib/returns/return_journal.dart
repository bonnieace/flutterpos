import 'package:flutter/material.dart';

import '../tenancy/tenant_staff_names.dart';
import '../ui/buttons.dart';
import '../ui/scaffold.dart';
import '../ui/tokens.dart';
import 'return_history.dart';

/// The old till's *View Return*, rebuilt on the token layer.
///
/// **A journal page, not a record row.** The pre-multitenancy app read a return
/// as a short piece of writing: an eyebrow label over each fact, the reason set
/// centred and large behind a quotation glyph, one figure given a whole line of
/// its own, then the particulars in two columns under a hairline. The migrated
/// app rendered the same return as five `RecordAttribute` rows - the same
/// information and none of the emphasis, so a person could not tell at a glance
/// whether they were looking at a routine return or an odd one.
///
/// **Two things from the old screen deliberately did not come across.**
///
/// - *Fraud risk.* `lib/services/fraud_detection_service.dart` is 556 lines
///   that nothing imports - `test/dev/reachable_lib_test.dart` names it - and
///   it reads the whole `returns` collection to score one row. Drawing a risk
///   band here would be depicting a capability the product does not have, which
///   `DESIGN_RULES.md` forbids, and reading a collection would be a repository
///   call in a visual change, which hard rule 1 forbids.
/// - *Time between sale and return.* The old screen's second figure. A
///   [TenantReturn] carries the sale's **id** and not its instant, so that
///   figure would cost a document read per return. [TenantReturn.returnedUnits]
///   is the figure this screen can state from what it was handed.
///
/// **The serif is not reproduced.** The old screen asked for `fontFamily:
/// 'Serif'` and the token layer registers two families, neither of which is
/// one. Rather than hardcode a third face into a widget, the pull quote takes
/// the display role the scale already has. Adding a serif to `AppTokens` is a
/// token decision and is recorded as a question rather than taken here.
final class TenantReturnJournalScreen extends StatelessWidget {
  const TenantReturnJournalScreen({
    super.key,
    required this.record,
    this.staffNames = const <String, String>{},
    this.productNames = const <String, String>{},
    this.receipt,
    this.selfUid,
    this.onVerify,
  });

  final TenantReturn record;

  /// Canonical staff names, for the two people this page names.
  final Map<String, String> staffNames;

  /// What the **sale** called each returned product, by product ID.
  ///
  /// The caller resolves these because it has already read the sale. A return
  /// recorded before returns carried a product name has none of its own, and
  /// *RETURNED INVENTORY* listing document IDs was the defect the product owner
  /// reported on this page.
  final Map<String, String> productNames;

  /// The sale's receipt, as the sales list prints it. Null where the calling
  /// surface could not read the sale, in which case the ID is all there is.
  final String? receipt;

  final String? selfUid;

  /// Offered only where the calling surface has already decided this session
  /// may verify. This screen draws the affordance; it never decides the right
  /// to it.
  final VoidCallback? onVerify;

  @override
  Widget build(BuildContext context) => AppScaffold(
    contentWidth: AppContentWidth.reading,
    title: 'View return',
    // The receipt a person can match against the paper in their hand, and the
    // document ID only when there is nothing better.
    subtitle: receipt == null ? 'Sale ${record.saleId}' : 'Receipt $receipt',
    body: _ReturnJournal(
      record: record,
      staffNames: staffNames,
      productNames: productNames,
      receipt: receipt,
      selfUid: selfUid,
      onVerify: onVerify,
    ),
  );
}

final class _ReturnJournal extends StatelessWidget {
  const _ReturnJournal({
    required this.record,
    required this.staffNames,
    required this.productNames,
    required this.receipt,
    required this.selfUid,
    required this.onVerify,
  });

  final TenantReturn record;
  final Map<String, String> staffNames;
  final Map<String, String> productNames;
  final String? receipt;
  final String? selfUid;
  final VoidCallback? onVerify;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final wide = AppLayout.contract.isAtLeast(
      MediaQuery.sizeOf(context).width,
      AppBreakpoint.medium,
    );
    return SingleChildScrollView(
      key: const ValueKey('return-journal'),
      padding: EdgeInsets.all(tokens.spacing.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Masthead(record: record, receipt: receipt, tokens: tokens),
          SizedBox(height: tokens.spacing.s32),
          _PullQuote(reason: record.reason, tokens: tokens),
          SizedBox(height: tokens.spacing.s32),
          _Figure(
            eyebrow: 'UNITS RETURNED',
            value:
                '${record.returnedUnits} '
                '${record.returnedUnits == 1 ? 'unit' : 'units'}',
            valueKey: const ValueKey('return-journal-units'),
            tokens: tokens,
          ),
          SizedBox(height: tokens.spacing.s32),
          // The old screen's two columns, and its own answer for a narrow
          // window: the same two blocks, one under the other.
          if (wide)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: _returned(tokens)),
                  SizedBox(width: tokens.spacing.s32),
                  Expanded(child: _people(tokens)),
                ],
              ),
            )
          else ...<Widget>[
            _returned(tokens),
            SizedBox(height: tokens.spacing.s24),
            _people(tokens),
          ],
          SizedBox(height: tokens.spacing.s32),
          Divider(height: 1, color: tokens.colors.surface.borderSubtle),
          SizedBox(height: tokens.spacing.s24),
          _Verification(record: record, onVerify: onVerify, tokens: tokens),
        ],
      ),
    );
  }

  Widget _returned(AppTokens tokens) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      _Eyebrow('RETURNED INVENTORY', tokens: tokens),
      SizedBox(height: tokens.spacing.s8),
      for (final line in record.lines)
        Padding(
          padding: EdgeInsets.symmetric(vertical: tokens.spacing.s8),
          child: Row(
            key: ValueKey('return-journal-line-${line.productId}'),
            children: <Widget>[
              Icon(
                Icons.inventory_2_outlined,
                size: tokens.typography.bodyLarge.fontSize,
                color: tokens.colors.action.primary.container,
              ),
              SizedBox(width: tokens.spacing.s8),
              Expanded(
                child: Text(
                  line.productName ??
                      productNames[line.productId] ??
                      line.productId,
                  style: tokens.typography.bodyLarge.copyWith(
                    color: tokens.colors.text.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(width: tokens.spacing.s8),
              Text(
                'Qty ${line.quantity}',
                style: tokens.typography.caption.copyWith(
                  color: tokens.colors.text.tertiary,
                ),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _people(AppTokens tokens) {
    final verification = record.verification;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _Eyebrow('RECORDED BY', tokens: tokens),
        SizedBox(height: tokens.spacing.s8),
        _Person(
          name: _label(record.createdBy),
          icon: Icons.person_outline,
          nameKey: const ValueKey('return-journal-recorded-by'),
          tokens: tokens,
        ),
        SizedBox(height: tokens.spacing.s20),
        _Eyebrow('VERIFIED BY', tokens: tokens),
        SizedBox(height: tokens.spacing.s8),
        if (verification == null)
          Text(
            'Nobody yet',
            key: const ValueKey('return-journal-verified-by'),
            style: tokens.typography.bodyLarge.copyWith(
              color: tokens.colors.text.tertiary,
            ),
          )
        else
          _Person(
            name: _label(verification.verifiedBy),
            icon: Icons.verified_outlined,
            nameKey: const ValueKey('return-journal-verified-by'),
            detail: _instant(verification.verifiedAt),
            tokens: tokens,
          ),
      ],
    );
  }

  String _label(String uid) =>
      tenantStaffLabel(uid, names: staffNames, selfUid: selfUid);
}

/// The sale this return came off, and where it stands.
final class _Masthead extends StatelessWidget {
  const _Masthead({
    required this.record,
    required this.receipt,
    required this.tokens,
  });

  final TenantReturn record;

  /// The sale's receipt. **The document ID is the fallback, not the
  /// headline**: `co-1788637383703-3358bf…` is not something anybody can match
  /// against the paper in their hand, and it was what this block printed until
  /// 2026-09-06.
  final String? receipt;

  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    final status = record.isVerified
        ? tokens.colors.status.ok
        : tokens.colors.status.attention;
    final recordedAt = record.recordedAt;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _Eyebrow('SALE', tokens: tokens),
              Text(
                receipt ?? record.saleId,
                key: const ValueKey('return-journal-sale'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens.typography.mono.copyWith(
                  color: tokens.colors.text.secondary,
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: tokens.spacing.s16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // **The word, not only the colour.** §9 refuses a status carried by
            // hue alone, and the old screen's VERIFIED/UNVERIFIED pair is
            // already the word this needs.
            Text(
              record.isVerified ? 'VERIFIED' : 'UNVERIFIED',
              key: const ValueKey('return-journal-status'),
              style: tokens.typography.labelEyebrow.copyWith(
                color: status.fg,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              recordedAt == null
                  ? 'Awaiting server time'
                  : _instant(recordedAt),
              key: const ValueKey('return-journal-recorded'),
              style: tokens.typography.caption.copyWith(
                color: tokens.colors.text.tertiary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The reason, set as the page's one piece of writing.
final class _PullQuote extends StatelessWidget {
  const _PullQuote({required this.reason, required this.tokens});

  final String reason;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    final wide = AppLayout.contract.isAtLeast(
      MediaQuery.sizeOf(context).width,
      AppBreakpoint.medium,
    );
    final quote = wide
        ? tokens.typography.display
        : tokens.typography.displayCompact;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Eyebrow('REASON FOR RETURN', tokens: tokens, centred: true),
        SizedBox(height: tokens.spacing.s12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.format_quote,
              // The glyph is set from the type it opens, so the two move
              // together at either width rather than by two separate numbers.
              size: quote.fontSize,
              color: tokens.colors.action.primary.container,
            ),
            SizedBox(width: tokens.spacing.s8),
            Expanded(
              child: Text(
                reason,
                key: const ValueKey('return-journal-reason'),
                textAlign: TextAlign.center,
                style: quote.copyWith(color: tokens.colors.text.primary),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One figure given a line of its own.
final class _Figure extends StatelessWidget {
  const _Figure({
    required this.eyebrow,
    required this.value,
    required this.valueKey,
    required this.tokens,
  });

  final String eyebrow;
  final String value;
  final Key valueKey;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      _Eyebrow(eyebrow, tokens: tokens, centred: true),
      SizedBox(height: tokens.spacing.s8),
      Text(
        value,
        key: valueKey,
        textAlign: TextAlign.center,
        style: tokens.typography.numericHero.copyWith(
          color: tokens.colors.text.primary,
        ),
      ),
    ],
  );
}

/// The old screen's small-caps label over every fact.
final class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text, {required this.tokens, this.centred = false});

  final String text;
  final AppTokens tokens;
  final bool centred;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: centred ? TextAlign.center : TextAlign.start,
    style: tokens.typography.labelEyebrow.copyWith(
      color: tokens.colors.text.tertiary,
    ),
  );
}

/// A named person, as the old screen drew one.
final class _Person extends StatelessWidget {
  const _Person({
    required this.name,
    required this.icon,
    required this.nameKey,
    required this.tokens,
    this.detail,
  });

  final String name;
  final IconData icon;
  final Key nameKey;
  final AppTokens tokens;
  final String? detail;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Icon(
        icon,
        size: tokens.typography.bodyLarge.fontSize,
        color: tokens.colors.action.primary.container,
      ),
      SizedBox(width: tokens.spacing.s8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              name,
              key: nameKey,
              style: tokens.typography.bodyLarge.copyWith(
                color: tokens.colors.text.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (detail case final line?)
              Text(
                line,
                style: tokens.typography.caption.copyWith(
                  color: tokens.colors.text.tertiary,
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

/// The foot of the page: what the old screen put under its divider.
final class _Verification extends StatelessWidget {
  const _Verification({
    required this.record,
    required this.onVerify,
    required this.tokens,
  });

  final TenantReturn record;
  final VoidCallback? onVerify;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    if (record.isVerified) {
      return Column(
        children: <Widget>[
          Icon(
            Icons.verified,
            size: tokens.typography.numericHero.fontSize,
            color: tokens.colors.status.ok.fg,
          ),
          SizedBox(height: tokens.spacing.s8),
          Text(
            'AUDIT VERIFIED',
            key: const ValueKey('return-journal-verified'),
            style: tokens.typography.labelEyebrow.copyWith(
              color: tokens.colors.text.secondary,
            ),
          ),
        ],
      );
    }
    if (onVerify case final verify?) {
      return Column(
        children: <Widget>[
          AppButton(
            key: const ValueKey('return-journal-verify'),
            label: 'Verify and restore',
            icon: Icons.verified_outlined,
            onPressed: verify,
          ),
          SizedBox(height: tokens.spacing.s8),
          Text(
            'THIS RESTORES THE STOCK',
            style: tokens.typography.labelEyebrow.copyWith(
              color: tokens.colors.text.tertiary,
            ),
          ),
        ],
      );
    }
    return Column(
      children: <Widget>[
        Icon(
          Icons.hourglass_empty,
          size: tokens.typography.numericHero.fontSize,
          color: tokens.colors.status.attention.fg,
        ),
        SizedBox(height: tokens.spacing.s8),
        Text(
          'AWAITING VERIFICATION',
          key: const ValueKey('return-journal-awaiting'),
          style: tokens.typography.labelEyebrow.copyWith(
            color: tokens.colors.text.secondary,
          ),
        ),
      ],
    );
  }
}

String _instant(DateTime value) {
  final local = value.toLocal();
  String pad(int part) => part.toString().padLeft(2, '0');
  return '${local.year}-${pad(local.month)}-${pad(local.day)} '
      '${pad(local.hour)}:${pad(local.minute)}';
}
