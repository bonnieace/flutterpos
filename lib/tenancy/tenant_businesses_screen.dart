/// *My businesses*: every business on the account, each drawn as a
/// [BusinessCard], with *Add business* at the head of the list.
///
/// **Redrawn 2026-10-13** in the house style: the white receipt stood out on
/// every surface around it. The data, the order and the actions are the
/// receipt's; from [AppLayoutTokens.mediumFloor] the cards sit in columns.
///
/// **Built 2026-10-08 from `docs/design/businesses/`.** Before it, an owner
/// with one business had no way to add a second from inside the app: the form
/// (`TenantRequestForm`) was hosted only by the business selector, and the
/// selector never shows when a business opens by itself. The home's *My
/// businesses* tile and the business name in its top bar both open this.
///
/// **A business is shown through its own brand** - the logo, name and slogan
/// its receipt prints - over its own figures. The rulings the design records -
/// the open business's live day, any
/// other business's last counted day, the till named, the add sheet opening on
/// the open business's currency - are the developer's, made on 2026-10-08.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../checkout/checkout_draft.dart';
import '../observability/app_telemetry.dart';
import '../reporting/daily_metrics.dart';
import '../reporting/reporting_currency.dart';
import '../shift/abandoned_shift.dart';
import '../shift/tenant_shift.dart';
import '../ui/buttons.dart';
import '../ui/scaffold.dart';
import '../ui/sheet.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'tenant_branding.dart';
import 'tenant_business_card.dart';
import 'tenant_membership.dart';
import 'tenant_membership_labels.dart';
import 'tenant_paths.dart';
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
  ///
  /// **Every open shift, whatever day it was opened on.** A till opened last
  /// night and still running is open now, and a query for today's shifts
  /// would call it closed - which is what the first build did.
  Future<String?> _readTill() async {
    final session = TenantSession.fromMembership(
      uid: widget.uid,
      membership: widget.membership,
    );
    if (!_OpenTills.mayRead(session)) return null;
    final ids = await _quiet(
      () => _OpenTills(
        session: session,
        reader: widget.reader,
      ).staffIds(widget.reader),
    );
    if (ids == null) return null;
    final open = <String>{...ids};
    if (open.isEmpty) return 'Closed';
    if (open.length > 1) return '${open.length} tills open';
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
      contentWidth: AppContentWidth.records,
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
          SizedBox(height: tokens.spacing.s16),
          if (_blocker case final blocker?) ...<Widget>[
            Callout(
              key: const ValueKey('my-businesses-switch-blocker'),
              status: AppStatus.problem,
              message: tenantSwitchBlockerMessage(blocker),
            ),
            SizedBox(height: tokens.spacing.s16),
          ],
          BusinessCardGrid(
            children: <Widget>[
              BusinessCard(
                key: ValueKey('business-${widget.membership.tenantId}'),
                name: widget.openReceipt.name,
                slogan: widget.openReceipt.slogan,
                logoUrl: widget.openReceipt.logoUrl,
                here: true,
                status: const BusinessCardStatus(
                  status: AppStatus.ok,
                  icon: Icons.check_circle,
                  word: 'Open now',
                  detail: 'you’re in it',
                ),
                figure: switch (widget.openReceipt.today) {
                  final today? => BusinessCardFigure(
                    label: 'Today',
                    value: today,
                    hero: true,
                  ),
                  null => null,
                },
                facts: <BusinessCardFact>[
                  if (widget.openReceipt.sales case final sales?)
                    BusinessCardFact('Sales', sales, numeric: true),
                  if (_till case final till?)
                    BusinessCardFact.later('Till', till),
                  BusinessCardFact(
                    'You',
                    tenantRoleLabel(widget.membership.role),
                  ),
                ],
                action: widget.onEditDetails == null
                    ? null
                    : const BusinessCardAction(
                        icon: Icons.receipt_long_outlined,
                        label: 'Edit details',
                        detail: 'Name, slogan and logo on its receipt',
                      ),
                onPressed: widget.onEditDetails,
                semanticLabel:
                    '${widget.openReceipt.name}, open now. Edit its details.',
              ),
              for (final result in _added)
                BusinessCard(
                  key: ValueKey('business-${result.tenantId}'),
                  name: result.name,
                  status: const BusinessCardStatus(
                    status: AppStatus.info,
                    icon: Icons.hourglass_top,
                    word: 'Setting up',
                  ),
                  facts: <BusinessCardFact>[
                    BusinessCardFact('You', tenantRoleLabel(TenantRole.owner)),
                  ],
                  semanticLabel: '${result.name}, being set up.',
                ),
              for (final other in others)
                _OtherBusinessCard(
                  key: ValueKey('business-${other.tenantId}'),
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
          ),
        ],
      ),
    );
  }
}

/// Who holds a shift that is open in a business now.
///
/// **The query `TenantAbandonedShiftRepository` already makes** - every shift
/// whose status is open - and the same roles, which are the ones the rules
/// let read another cashier's shift.
final class _OpenTills extends TenantReadRepository {
  _OpenTills({required super.session, required super.reader});

  static bool mayRead(TenantSession session) =>
      TenantAbandonedShiftRepository.isVisibleTo(session);

  Future<List<String>> staffIds(TenantCollectionReader collectionReader) async {
    final page = await readCollectionPage(
      TenantCollection.shifts,
      collectionReader: collectionReader,
      pageSize: 10,
      equalityFilters: <String, Object?>{
        'status': TenantShiftStatus.open.wireValue,
      },
    );
    return <String>[
      for (final item in page.items)
        if (_staffOf(item) case final staff?) staff,
    ];
  }

  String? _staffOf(TenantQueryDocumentSnapshot item) {
    try {
      final shift = TenantShift.fromDocument(path: item.path, data: item.data);
      return shift.tenantId == session.tenantId ? shift.staffId : null;
    } on TenantShiftException {
      return null;
    }
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
final class _OtherBusinessCard extends StatelessWidget {
  const _OtherBusinessCard({
    super.key,
    required this.membership,
    required this.read,
    required this.switching,
    required this.onSwitch,
  });

  final TenantMembership membership;

  /// Null for a business this member cannot open - suspended, archived, an
  /// invitation not yet accepted - which shows its standing instead.
  final Future<_OtherReceipt>? read;
  final bool switching;
  final VoidCallback? onSwitch;

  @override
  Widget build(BuildContext context) {
    final you = BusinessCardFact('You', tenantRoleLabel(membership.role));
    final pending = read;
    if (pending == null) {
      final standing = businessCardStanding(membership);
      return BusinessCard(
        name: membership.tenantName,
        still: true,
        status: standing,
        facts: <BusinessCardFact>[you],
        semanticLabel:
            '${membership.tenantName}, ${standing.word}. Cannot be opened.',
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
        return BusinessCard(
          name: branding?.companyName ?? membership.tenantName,
          slogan: branding?.slogan,
          logoUrl: branding?.logoUrl,
          // **The date is named, never "yesterday".** This is the last day
          // reconciliation counted, and the card says which day it is for.
          // An em dash where nothing was published, as the home does.
          figure: date == null
              ? null
              : BusinessCardFigure(
                  label: 'Last counted · ${_cardDate(date)}',
                  value: metrics == null
                      ? '—'
                      : currency.format(metrics.netSales),
                ),
          facts: <BusinessCardFact>[
            if (date != null)
              BusinessCardFact(
                'Sales',
                metrics == null ? '—' : '${metrics.netTransactions}',
                numeric: true,
              ),
            you,
          ],
          action: BusinessCardAction(
            icon: Icons.swap_horiz,
            label: switching ? 'Switching…' : 'Switch to this shop',
            busy: switching,
          ),
          onPressed: onSwitch,
          semanticLabel:
              '${membership.tenantName}. ${tenantRoleLabel(membership.role)} '
              'there. Switch to it.',
        );
      },
    );
  }
}

/// `2026-10-07` as the card names it: `7 Oct`.
String _cardDate(String businessDate) {
  final parsed = DateTime.tryParse(businessDate);
  if (parsed == null) return businessDate;
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${parsed.day} ${months[parsed.month - 1]}';
}

/// Opens the *Add business* sheet and returns what was added, or null.
///
/// **The new business's card is the sheet's masthead**, as the photo is on
/// the product photo sheet: edge to edge under the rounded corners, the handle
/// and close laid over it, no heading. It was a printed receipt until
/// 2026-10-13; it is now the card the business will get on *My businesses*,
/// on the sunken surface so it reads as a preview, with the name as it is
/// typed.
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
              return _AddBusinessMasthead(
                card: BusinessCard(
                  key: const ValueKey('add-business-preview'),
                  name: name.isEmpty ? 'Your business' : name,
                  namePlaceholder: name.isEmpty,
                  figure: BusinessCardFigure(
                    label: 'Today',
                    value: '${value.currency.trim().toUpperCase()} 0',
                    hero: true,
                  ),
                  facts: <BusinessCardFact>[
                    const BusinessCardFact('Sales', '0', numeric: true),
                    const BusinessCardFact('Till', 'Closed'),
                    BusinessCardFact('You', tenantRoleLabel(TenantRole.owner)),
                  ],
                  semanticLabel: name.isEmpty
                      ? 'How this business will show on My businesses.'
                      : 'How $name will show on My businesses.',
                ),
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

/// The add sheet's masthead: the preview card on the sunken surface, with
/// room above for the sheet's handle and close control and a caption saying
/// what the card is.
///
/// **It shrinks to fit rather than clipping** on a short screen, at the
/// sheet's own width - a sheet is narrower than the screen on a tablet.
final class _AddBusinessMasthead extends StatelessWidget {
  const _AddBusinessMasthead({required this.card});

  final Widget card;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final space = tokens.spacing;
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        card,
        Padding(
          padding: EdgeInsets.fromLTRB(space.s4, space.s12, space.s4, 0),
          child: Text(
            'How it will show on this page.',
            style: tokens.typography.caption.copyWith(
              color: colors.text.tertiary,
            ),
          ),
        ),
      ],
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.sunken,
        border: Border(bottom: BorderSide(color: colors.surface.borderSubtle)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          space.s16,
          space.s48,
          space.s16,
          space.s20,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topCenter,
              child: SizedBox(width: constraints.maxWidth, child: body),
            ),
          ),
        ),
      ),
    );
  }
}
