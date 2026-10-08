/// *My businesses*: every business on the account, each drawn as the receipt
/// it prints, with *Add business* at the head of the list.
///
/// **Built 2026-10-08 from `docs/design/businesses/`.** Before it, an owner
/// with one business had no way to add a second from inside the app: the form
/// (`TenantRequestForm`) was hosted only by the business selector, and the
/// selector never shows when a business opens by itself. The home's *My
/// businesses* tile and the business name in its top bar both open this.
///
/// **A business is drawn as its receipt** because the receipt is the one thing
/// that is uniquely that business here: its logo, name and slogan over its own
/// figures. The rulings the design records - the open business's live day, any
/// other business's last counted day, the till named, the add sheet opening on
/// the open business's currency - are the developer's, made on 2026-10-08.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../checkout/checkout_draft.dart';
import '../inventory/product_image_provider.dart';
import '../observability/app_telemetry.dart';
import '../reporting/daily_metrics.dart';
import '../reporting/reporting_currency.dart';
import '../ui/buttons.dart';
import '../ui/press.dart';
import '../ui/scaffold.dart';
import '../ui/sheet.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'tenant_branding.dart';
import 'tenant_membership.dart';
import 'tenant_membership_labels.dart';
import 'tenant_repository.dart';
import 'tenant_request.dart';
import 'tenant_session.dart';
import 'tenant_routing_shell.dart' show tenantSwitchBlockerMessage;
import 'tenant_staff_names.dart';
import 'tenant_switch.dart';
import 'tenant_types.dart';

/// What the open business's receipt prints, handed over by the home so this
/// page states the home's own figures rather than reading them a second time.
final class TenantOpenBusinessReceipt {
  const TenantOpenBusinessReceipt({
    required this.name,
    this.slogan,
    this.logoUrl,
    this.today,
    this.sales,
    this.currencyCode,
    this.openShiftStaffIds,
  });

  final String name;
  final String? slogan;
  final Uri? logoUrl;

  /// Today's takings, already formatted, or null where this member is not
  /// shown them. An em dash where the day has nothing counted yet.
  final String? today;

  /// Today's sale count, already formatted, or null alongside [today].
  final String? sales;

  /// The open business's currency, which the add sheet opens on.
  final String? currencyCode;

  /// Who holds a shift that is still open today. Null where this member may
  /// not read every cashier's shifts, which leaves the till line off.
  final List<String>? openShiftStaffIds;
}

/// The page itself.
final class TenantBusinessesScreen extends StatefulWidget {
  const TenantBusinessesScreen({
    super.key,
    required this.uid,
    required this.membership,
    required this.readMemberships,
    required this.reader,
    required this.openReceipt,
    this.onEditDetails,
    this.onSwitchTenant,
    this.accountEmail,
    this.requestIdentity,
    this.requestTenantCallable,
    this.tenantRequestIdFactory,
    this.onRefreshMemberships,
    this.clock,
  });

  final String uid;

  /// The business that is open.
  final TenantMembership membership;

  /// Every membership on the account, as the shell currently holds them.
  ///
  /// **A function, not a list**, because a business added here reaches the
  /// shell through a bootstrap refresh after this route was pushed, and the
  /// route has to read the shell's answer rather than the one it was built
  /// with.
  final List<TenantMembership> Function() readMemberships;

  final TenantDataReader reader;
  final TenantOpenBusinessReceipt openReceipt;

  /// Opens Business details for the open business. Null hides the action.
  final VoidCallback? onEditDetails;

  final Future<TenantSwitchResult> Function(TenantMembership membership)?
  onSwitchTenant;

  final String? accountEmail;

  /// Who would be asking for a new business. Null leaves *Add business* off
  /// the page.
  final TenantRequestIdentity? requestIdentity;

  /// How the request is sent. Null is the Firebase callable, built on the tap
  /// that needs it rather than with the page.
  final RequestTenantCallable? requestTenantCallable;
  final TenantRequestIdFactory? tenantRequestIdFactory;

  /// Asks the shell to re-read the account's memberships, so a business just
  /// added becomes one this page can switch to.
  final Future<void> Function()? onRefreshMemberships;

  final DateTime Function()? clock;

  @override
  State<TenantBusinessesScreen> createState() => _TenantBusinessesScreenState();
}

final class _TenantBusinessesScreenState extends State<TenantBusinessesScreen> {
  /// One read per business per visit, kept so a rebuild does not repeat it.
  final Map<String, Future<_OtherReceipt>> _others =
      <String, Future<_OtherReceipt>>{};

  /// Businesses added on this visit that the shell has not reported yet.
  final List<TenantRequestResult> _added = <TenantRequestResult>[];

  Future<String?>? _till;
  String? _switchingTenantId;
  TenantSwitchBlocker? _blocker;

  @override
  void initState() {
    super.initState();
    _till = _readTill();
  }

  /// Names whoever has a till open in the open business.
  ///
  /// **One name, or a count.** Two tills open is a fact about the shop, and a
  /// list of names on a receipt line is not one; a single till is a person,
  /// and naming them is what the developer asked for on 2026-10-08.
  Future<String?> _readTill() async {
    final ids = widget.openReceipt.openShiftStaffIds;
    if (ids == null) return null;
    final open = <String>{...ids};
    if (open.isEmpty) return 'Closed';
    if (open.length > 1) return '${open.length} tills open';
    final session = TenantSession.fromMembership(
      uid: widget.uid,
      membership: widget.membership,
    );
    final names = await _quiet(
      () => TenantStaffNameResolver(
        session: session,
        reader: widget.reader,
      ).resolve(open),
    );
    final name = names?[open.single];
    return name == null || name.trim().isEmpty ? 'Open' : 'Open · $name';
  }

  Future<_OtherReceipt> _readOther(TenantMembership membership) {
    return _others.putIfAbsent(membership.tenantId, () async {
      final session = TenantSession.fromMembership(
        uid: widget.uid,
        membership: membership,
      );
      final branding = _quiet(
        () => TenantBrandingRepository(
          session: session,
          reader: widget.reader,
        ).load(),
      );
      // The same gate the home puts on its own takings: `daily_metrics` is
      // owner, administrator and manager, and a cashier there would spend a
      // read only to be refused.
      final mayReadRevenue = session.canAccess(
        allowedRoles: TenantDailyMetricsRepository.allowedRoles,
      );
      final now = (widget.clock ?? DateTime.now)().toUtc();
      // **Yesterday, which reconciliation has normally counted overnight.**
      // Only the open business has live totals; reading today here would
      // nearly always find nothing published yet.
      final businessDate = checkoutBusinessDate(
        now.subtract(const Duration(days: 1)),
      );
      final metrics = mayReadRevenue
          ? _quiet(
              () => TenantDailyMetricsRepository(
                session: session,
                reader: widget.reader,
              ).readDay(businessDate),
            )
          : Future<TenantDailyMetrics?>.value();
      final currency = mayReadRevenue
          ? _quiet(
              () => TenantReportingCurrency.read(
                session: session,
                reader: widget.reader,
              ),
            )
          : Future<TenantReportingCurrency?>.value();
      return _OtherReceipt(
        branding: await branding,
        businessDate: mayReadRevenue ? businessDate : null,
        metrics: await metrics,
        currency: await currency,
      );
    });
  }

  static Future<T?> _quiet<T>(Future<T> Function() read) async {
    try {
      return await read();
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'tenancy.businesses_read',
      );
      return null;
    }
  }

  Future<void> _switchTo(TenantMembership target) async {
    final onSwitch = widget.onSwitchTenant;
    if (onSwitch == null || _switchingTenantId != null) return;
    setState(() {
      _switchingTenantId = target.tenantId;
      _blocker = null;
    });
    final navigator = Navigator.of(context);
    final result = await onSwitch(target);
    if (!mounted) return;
    if (result.switched) {
      // The home under this route now belongs to another business; going
      // back to it is the switch finishing.
      navigator.popUntil((route) => route.isFirst);
      return;
    }
    setState(() {
      _switchingTenantId = null;
      _blocker = result.blocker;
    });
  }

  Future<void> _addBusiness() async {
    final identity = widget.requestIdentity;
    if (identity == null) return;
    final callable =
        widget.requestTenantCallable ?? FirebaseRequestTenantCallable();
    final result = await showAddBusinessSheet(
      context,
      identity: identity,
      callable: callable,
      requestIdFactory: widget.tenantRequestIdFactory,
      initialCurrency: widget.openReceipt.currencyCode,
    );
    if (result == null || !mounted) return;
    setState(() => _added.add(result));
    final refresh = widget.onRefreshMemberships;
    if (refresh == null) return;
    try {
      await refresh();
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'tenancy.businesses_refresh',
      );
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final inset = AppScaffold.horizontalInset(tokens.spacing);
    final memberships = widget.readMemberships();
    final known = <String>{for (final m in memberships) m.tenantId};
    _added.removeWhere((result) => known.contains(result.tenantId));
    final others = <TenantMembership>[
      for (final m in memberships)
        if (m.tenantId != widget.membership.tenantId) m,
    ];
    final count = 1 + others.length + _added.length;
    final identity = widget.requestIdentity;
    final mayAdd = identity != null && identity.canRequestTenant;
    final addRefusal = identity == null
        ? null
        : identity.canRequestTenant
        ? null
        : !identity.emailVerified
        ? 'Verify your email to add a business.'
        : 'This account cannot add a business.';

    return AppScaffold(
      title: 'My businesses',
      contentWidth: AppContentWidth.reading,
      body: ListView(
        key: const ValueKey('my-businesses-list'),
        padding: EdgeInsets.fromLTRB(
          inset,
          tokens.spacing.s8,
          inset,
          tokens.spacing.s24,
        ),
        children: <Widget>[
          _Header(
            count: count,
            accountEmail: widget.accountEmail,
            onAdd: mayAdd ? _addBusiness : null,
            showAdd: identity != null,
            refusal: addRefusal,
          ),
          SizedBox(height: tokens.spacing.s8),
          if (_blocker case final blocker?) ...<Widget>[
            Callout(
              key: const ValueKey('my-businesses-switch-blocker'),
              status: AppStatus.problem,
              message: tenantSwitchBlockerMessage(blocker),
            ),
            SizedBox(height: tokens.spacing.s16),
          ],
          BusinessReceipt(
            key: ValueKey('receipt-${widget.membership.tenantId}'),
            name: widget.openReceipt.name,
            slogan: widget.openReceipt.slogan,
            logoUrl: widget.openReceipt.logoUrl,
            stamp: 'OPEN NOW',
            figures: <BusinessReceiptLine>[
              if (widget.openReceipt.today case final today?)
                BusinessReceiptLine.total('Today', today),
              if (widget.openReceipt.sales case final sales?)
                BusinessReceiptLine('Sales', sales),
            ],
            tillLine: _till,
            role: widget.membership.role,
            action: widget.onEditDetails == null ? null : 'Edit details',
            actionDetail: 'Name, slogan and logo on this receipt',
            onPressed: widget.onEditDetails,
            semanticLabel:
                '${widget.openReceipt.name}, open now. Edit its details.',
          ),
          for (final result in _added) ...<Widget>[
            SizedBox(height: tokens.spacing.s16),
            BusinessReceipt(
              key: ValueKey('receipt-${result.tenantId}'),
              name: result.name,
              figures: const <BusinessReceiptLine>[],
              role: TenantRole.owner,
              action: 'Setting up',
              semanticLabel: '${result.name}, being set up.',
            ),
          ],
          for (final other in others) ...<Widget>[
            SizedBox(height: tokens.spacing.s16),
            _OtherBusinessReceipt(
              key: ValueKey('receipt-${other.tenantId}'),
              membership: other,
              read: other.canAccess() ? _readOther(other) : null,
              switching: _switchingTenantId == other.tenantId,
              onSwitch:
                  other.canAccess() &&
                      widget.onSwitchTenant != null &&
                      _switchingTenantId == null
                  ? () => _switchTo(other)
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}

/// The list's own header: how many businesses, on which account, and the one
/// way to add to them.
///
/// **At the head of the list, not pinned under it**, at the developer's
/// direction on 2026-10-08: the action sits with the collection it adds to.
final class _Header extends StatelessWidget {
  const _Header({
    required this.count,
    required this.accountEmail,
    required this.onAdd,
    required this.showAdd,
    required this.refusal,
  });

  final int count;
  final String? accountEmail;
  final VoidCallback? onAdd;
  final bool showAdd;
  final String? refusal;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final type = tokens.typography;
    final text = tokens.colors.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: tokens.spacing.s4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      count == 1 ? '1 business' : '$count businesses',
                      style: type.titleMedium.copyWith(color: text.primary),
                    ),
                    if (accountEmail case final email?)
                      Text(
                        'On $email',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: type.caption.copyWith(color: text.tertiary),
                      ),
                  ],
                ),
              ),
            ),
            if (showAdd)
              AppButton(
                key: const ValueKey('add-business'),
                label: 'Add business',
                icon: Icons.add_business_outlined,
                tier: AppButtonTier.secondary,
                onPressed: onAdd,
              ),
          ],
        ),
        if (refusal case final sentence?)
          Padding(
            padding: EdgeInsets.only(
              left: tokens.spacing.s4,
              top: tokens.spacing.s4,
            ),
            child: Text(
              sentence,
              key: const ValueKey('add-business-refusal'),
              style: type.caption.copyWith(color: text.secondary),
            ),
          ),
      ],
    );
  }
}

/// What a business that is not open adds to its receipt once read.
final class _OtherReceipt {
  const _OtherReceipt({
    required this.branding,
    required this.businessDate,
    required this.metrics,
    required this.currency,
  });

  final TenantBranding? branding;

  /// The day the figures are for, or null where this member is not shown
  /// takings in that business.
  final String? businessDate;
  final TenantDailyMetrics? metrics;
  final TenantReportingCurrency? currency;
}

/// A business that is not open: its receipt once read, its name and your role
/// while it is being read or where it cannot be.
final class _OtherBusinessReceipt extends StatelessWidget {
  const _OtherBusinessReceipt({
    super.key,
    required this.membership,
    required this.read,
    required this.switching,
    required this.onSwitch,
  });

  final TenantMembership membership;

  /// Null for a business this member cannot open - suspended, archived, an
  /// invitation not yet accepted - which prints its standing instead.
  final Future<_OtherReceipt>? read;
  final bool switching;
  final VoidCallback? onSwitch;

  @override
  Widget build(BuildContext context) {
    final pending = read;
    if (pending == null) {
      final standing = _standing(membership);
      return BusinessReceipt(
        name: membership.tenantName,
        figures: <BusinessReceiptLine>[BusinessReceiptLine('Status', standing)],
        role: membership.role,
        action: null,
        semanticLabel: '${membership.tenantName}, $standing. Cannot be opened.',
      );
    }
    return FutureBuilder<_OtherReceipt>(
      future: pending,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final branding = data?.branding;
        final date = data?.businessDate;
        final metrics = data?.metrics;
        final currency = data?.currency ?? TenantReportingCurrency.unknown;
        return BusinessReceipt(
          name: branding?.companyName ?? membership.tenantName,
          slogan: branding?.slogan,
          logoUrl: branding?.logoUrl,
          figures: <BusinessReceiptLine>[
            // **The date is printed, never "yesterday".** This is the last
            // day reconciliation counted, and a receipt says which day it is
            // for. An em dash where nothing was published, as the home does.
            if (date != null)
              BusinessReceiptLine.total(
                _receiptDate(date),
                metrics == null ? '—' : currency.format(metrics.netSales),
              ),
            if (date != null)
              BusinessReceiptLine(
                'Sales',
                metrics == null ? '—' : '${metrics.netTransactions}',
              ),
          ],
          role: membership.role,
          action: switching ? 'Switching…' : 'Switch to this shop',
          onPressed: onSwitch,
          semanticLabel:
              '${membership.tenantName}. ${tenantRoleLabel(membership.role)} '
              'there. Switch to it.',
        );
      },
    );
  }

  static String _standing(TenantMembership membership) =>
      switch (membership.tenantStatus) {
        TenantStatus.suspended => 'Suspended',
        TenantStatus.archived => 'Archived',
        TenantStatus.active => switch (membership.membershipStatus) {
          MembershipStatus.pending => 'Invited',
          MembershipStatus.inactive => 'Deactivated',
          MembershipStatus.active => 'Unavailable',
        },
      };
}

/// `2026-10-07` as a receipt prints it: `7 OCT`.
String _receiptDate(String businessDate) {
  final parsed = DateTime.tryParse(businessDate);
  if (parsed == null) return businessDate;
  const months = <String>[
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];
  return '${parsed.day} ${months[parsed.month - 1]}';
}

/// One line under a receipt's rule.
final class BusinessReceiptLine {
  const BusinessReceiptLine(this.label, this.value) : isTotal = false;

  /// The headline line: its value set at [AppTypeRoles.numericCompact].
  const BusinessReceiptLine.total(this.label, this.value) : isTotal = true;

  final String label;
  final String value;
  final bool isTotal;
}

/// A business, drawn as the receipt it prints.
///
/// **Paper, in the report roles.** `AppTokens.colors.report` is the ground a
/// generated document sits on, which is what a receipt is; the screen's own
/// surfaces would make it a card wearing a receipt's clothes.
///
/// **The torn edge is the spacing scale:** teeth [AppSpacing.s8] deep and
/// [AppSpacing.s16] apart.
final class BusinessReceipt extends StatelessWidget {
  const BusinessReceipt({
    super.key,
    required this.name,
    required this.figures,
    required this.role,
    required this.semanticLabel,
    this.slogan,
    this.logoUrl,
    this.stamp,
    this.tillLine,
    this.action,
    this.actionDetail,
    this.onPressed,
    this.masthead = false,
  });

  final String name;
  final String? slogan;
  final Uri? logoUrl;

  /// A word stamped across the top corner, as a receipt is stamped *PAID*.
  final String? stamp;
  final List<BusinessReceiptLine> figures;

  /// Who has the till, resolved after the receipt is drawn. Null leaves the
  /// line off; a future that resolves to null does too.
  final Future<String?>? tillLine;
  final TenantRole? role;

  /// What tapping the receipt does, printed as its footer. Null prints none.
  final String? action;
  final String? actionDetail;
  final VoidCallback? onPressed;
  final String semanticLabel;

  /// Drawn edge to edge as a sheet's masthead: square top corners, a larger
  /// name, and room above for the sheet's handle and close control.
  final bool masthead;

  /// The stamp's tilt, which is what makes it read as stamped rather than
  /// printed. Named here rather than tokenised for the reason
  /// `AppSheetMasthead.handleScrimOpacity` gives: `design.md` states no angle.
  static const double stampTilt = 8 * math.pi / 180;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final paper = tokens.colors.report;
    final type = tokens.typography;
    final caption = type.monoCaption.copyWith(color: paper.mutedInk);
    final strong = type.monoCaption.copyWith(color: paper.ink);
    final rule = Text(
      // **A printed rule, typed.** A thermal receipt draws its rules in dashes
      // of the same face as everything else on it.
      '-' * 96,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.clip,
      style: type.monoCaption.copyWith(color: paper.rule),
    );
    Widget line(String label, String value) => Padding(
      padding: EdgeInsets.only(top: tokens.spacing.s4),
      child: Row(
        children: <Widget>[
          Text(label, style: caption),
          SizedBox(width: tokens.spacing.s12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: strong,
            ),
          ),
        ],
      ),
    );

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (logoUrl case final url?) ...<Widget>[
          Center(
            child: SizedBox.square(
              dimension: tokens.spacing.s40,
              child: Image(
                image: TenantCachedNetworkImage(
                  url,
                  cache: TenantImageCacheScope.of(context),
                ),
                fit: BoxFit.contain,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
          SizedBox(height: tokens.spacing.s4),
        ],
        // Clear of the stamp where there is no logo to push the name down.
        if (stamp != null && logoUrl == null)
          SizedBox(height: tokens.spacing.s24),
        Text(
          name.toUpperCase(),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: (masthead ? type.numericCompact : type.numericBody).copyWith(
            color: paper.ink,
          ),
        ),
        if (slogan case final words? when words.trim().isNotEmpty)
          Text(words, textAlign: TextAlign.center, style: caption),
        SizedBox(height: tokens.spacing.s8),
        rule,
        SizedBox(height: tokens.spacing.s8),
        for (final figure in figures)
          if (figure.isTotal)
            Padding(
              padding: EdgeInsets.only(bottom: tokens.spacing.s4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Text(figure.label.toUpperCase(), style: caption),
                  SizedBox(width: tokens.spacing.s12),
                  Expanded(
                    child: Text(
                      figure.value,
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type.numericCompact.copyWith(color: paper.ink),
                    ),
                  ),
                ],
              ),
            )
          else
            line(figure.label, figure.value),
        if (tillLine case final till?)
          FutureBuilder<String?>(
            future: till,
            builder: (context, snapshot) {
              final value = snapshot.data;
              if (value == null) return const SizedBox.shrink();
              return line('Till', value);
            },
          ),
        if (role case final member?) line('You', tenantRoleLabel(member)),
        if (action case final words?) ...<Widget>[
          SizedBox(height: tokens.spacing.s8),
          rule,
          SizedBox(height: tokens.spacing.s8),
          Text(
            onPressed == null
                ? words.toUpperCase()
                : '${words.toUpperCase()} ›',
            textAlign: TextAlign.center,
            style: strong,
          ),
          if (actionDetail case final detail?)
            Text(detail, textAlign: TextAlign.center, style: caption),
        ],
      ],
    );

    final sheet = ClipPath(
      clipper: _TornEdge(
        depth: tokens.spacing.s8,
        pitch: tokens.spacing.s16,
        radius: masthead ? 0 : tokens.radius.md,
      ),
      child: ColoredBox(
        color: paper.paper,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            tokens.spacing.s20,
            masthead
                ? tokens.spacing.s48 + tokens.spacing.s8
                : tokens.spacing.s20,
            tokens.spacing.s20,
            tokens.spacing.s24 + tokens.spacing.s8,
          ),
          // **As a masthead the paper is the sheet's whole top**, torn at its
          // bottom edge, and what it prints shrinks to fit rather than being
          // cut off on a short screen.
          child: masthead
              ? SizedBox.expand(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width:
                          MediaQuery.sizeOf(context).width -
                          tokens.spacing.s20 * 2,
                      child: body,
                    ),
                  ),
                )
              : body,
        ),
      ),
    );

    final stamped = stamp == null
        ? sheet
        : Stack(
            children: <Widget>[
              sheet,
              Positioned(
                top: tokens.spacing.s16,
                right: tokens.spacing.s16,
                child: _Stamp(stamp!),
              ),
            ],
          );

    final press = onPressed;
    if (press == null) {
      return Semantics(
        container: true,
        label: semanticLabel,
        excludeSemantics: true,
        child: stamped,
      );
    }
    return PressSurface(
      onPressed: press,
      borderRadius: BorderRadius.circular(tokens.radius.md),
      semanticLabel: semanticLabel,
      excludeSemantics: true,
      fillWidth: true,
      child: stamped,
    );
  }
}

/// The *OPEN NOW* stamp: a word, a tick and a ruled box, tilted.
///
/// **The word is in ink, not the stamp's green.** Paper green is 3.1:1 on
/// white, which clears §9 for the box and the tick - graphics - and not for
/// twelve-point text. The status is the word; the green is the stamp.
final class _Stamp extends StatelessWidget {
  const _Stamp(this.word);

  final String word;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final paper = tokens.colors.report;
    final style = tokens.typography.monoCaption.copyWith(color: paper.ink);
    return Transform.rotate(
      angle: BusinessReceipt.stampTilt,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: paper.barEmphasis),
          borderRadius: BorderRadius.circular(tokens.radius.sm),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: tokens.spacing.s8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.check, size: style.fontSize, color: paper.barEmphasis),
              SizedBox(width: tokens.spacing.s4),
              Text(word, style: style),
            ],
          ),
        ),
      ),
    );
  }
}

/// A rectangle whose top corners are rounded and whose bottom edge is torn.
final class _TornEdge extends CustomClipper<Path> {
  const _TornEdge({
    required this.depth,
    required this.pitch,
    required this.radius,
  });

  final double depth;
  final double pitch;
  final double radius;

  @override
  Path getClip(Size size) {
    final bottom = size.height - depth;
    final path = Path()
      ..moveTo(0, radius)
      ..quadraticBezierTo(0, 0, radius, 0)
      ..lineTo(size.width - radius, 0)
      ..quadraticBezierTo(size.width, 0, size.width, radius)
      ..lineTo(size.width, bottom);
    // Teeth from right to left, centred so both ends meet the edge evenly.
    final teeth = math.max(1, (size.width / pitch).round());
    final step = size.width / teeth;
    for (var index = teeth; index > 0; index--) {
      final right = step * index;
      path
        ..lineTo(right - step / 2, size.height)
        ..lineTo(right - step, bottom);
    }
    return path..close();
  }

  @override
  bool shouldReclip(_TornEdge oldClipper) =>
      oldClipper.depth != depth ||
      oldClipper.pitch != pitch ||
      oldClipper.radius != radius;
}

/// Opens the *Add business* sheet and returns what was added, or null.
///
/// **The receipt is the sheet's masthead**, as the photo is on the product
/// photo sheet, at the developer's direction on 2026-10-08: edge to edge under
/// the rounded corners, the handle and close laid over it, no heading. It
/// prints the name as it is typed.
Future<TenantRequestResult?> showAddBusinessSheet(
  BuildContext context, {
  required TenantRequestIdentity identity,
  required RequestTenantCallable callable,
  TenantRequestIdFactory? requestIdFactory,
  String? initialCurrency,
}) async {
  final draft = ValueNotifier<({String name, String currency})>((
    name: '',
    currency: initialCurrency ?? tenantRequestCurrencies.first,
  ));
  try {
    return await showAppSheet<TenantRequestResult>(
      context,
      dismissible: false,
      mastheadFraction: AppSheetMasthead.receiptFraction,
      masthead: (context) =>
          ValueListenableBuilder<({String name, String currency})>(
            valueListenable: draft,
            builder: (context, value, _) {
              final name = value.name.trim();
              return BusinessReceipt(
                key: const ValueKey('add-business-preview'),
                masthead: true,
                name: name.isEmpty ? 'Your business' : name,
                figures: <BusinessReceiptLine>[
                  BusinessReceiptLine.total(
                    'Today',
                    '${value.currency.trim().toUpperCase()} 0',
                  ),
                  const BusinessReceiptLine('Sales', '0'),
                  const BusinessReceiptLine('Till', 'Closed'),
                ],
                role: TenantRole.owner,
                semanticLabel: name.isEmpty
                    ? 'The receipt this business will print.'
                    : 'The receipt $name will print.',
              );
            },
          ),
      builder: (sheetContext, controller) {
        final tokens = AppTokens.componentOf(sheetContext);
        return ListView(
          controller: controller,
          padding: EdgeInsets.fromLTRB(
            tokens.spacing.s20,
            tokens.spacing.s16,
            tokens.spacing.s20,
            tokens.spacing.s16,
          ),
          children: <Widget>[
            TenantRequestForm(
              key: const ValueKey('add-business-form'),
              identity: identity,
              callable: callable,
              requestIdFactory: requestIdFactory,
              heading: null,
              description: null,
              submitLabel: 'Add business',
              initialCurrency: initialCurrency,
              expandActions: true,
              onDraftChanged: (name, currency) =>
                  draft.value = (name: name, currency: currency),
              onCancel: () => Navigator.of(sheetContext).pop(),
              onSuccess: (result) => Navigator.of(sheetContext).pop(result),
            ),
          ],
        );
      },
    );
  } finally {
    // After the route's exit, so the masthead is not listening to a disposed
    // notifier while the sheet slides away.
    WidgetsBinding.instance.addPostFrameCallback((_) => draft.dispose());
  }
}
