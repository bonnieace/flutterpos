/// What a newly approved business still has to do before it can sell.
///
/// **The silence this replaces.** A business that has just been created has no
/// published currency, and the till refuses every sale with
/// `configurationUnavailable` until it does. Nothing on the home said so. The
/// owner of a brand-new shop tapped *Register*, got a refusal naming a
/// configuration they had never heard of, and had no way to learn that the
/// answer was two taps away under *Settings*.
///
/// **Two steps, and they are the two that actually stop a sale.** Currency,
/// because the till will not price anything without it, and at least one
/// product, because there is nothing to ring up. Business details and the
/// printer matter and are *not* here: neither blocks a sale, both are one tap
/// away in *Settings*, and a checklist that lists everything is a checklist
/// nobody finishes.
///
/// **It costs no Firestore read, which is the constraint it was built under.**
/// Both facts are already in the encrypted catalog cache this device keeps for
/// the till - `CheckoutCatalogCacheRefresher` writes it on every session open -
/// so the home asks Hive rather than the network. A landing route that issued
/// two more reads to draw a card that is usually absent would have been a worse
/// trade than the silence.
library;

import 'package:flutter/material.dart';

import '../checkout/checkout_catalog_cache.dart';
import '../ui/buttons.dart';
import '../ui/tokens.dart';
import 'tenant_session.dart';
import 'tenant_types.dart';

/// One thing a business has not done yet.
enum TenantSetupStep {
  /// No currency is published, so the till cannot price a sale at all.
  currency,

  /// The catalog is empty, so there is nothing to sell.
  products,
}

/// How far a business has got.
final class TenantSetupState {
  const TenantSetupState({
    required this.hasCurrency,
    required this.hasProducts,
  });

  /// Nothing is known yet - the cache has not been written for this session.
  ///
  /// Treated as "neither done", because that is what a business this device has
  /// never successfully refreshed looks like, and it is the safe way round: the
  /// card appears and points at the two screens that fix it.
  const TenantSetupState.unknown() : hasCurrency = false, hasProducts = false;

  final bool hasCurrency;
  final bool hasProducts;

  bool get isComplete => hasCurrency && hasProducts;

  /// The outstanding steps, in the order they have to be done: a product priced
  /// in no currency is not a thing this app can store.
  List<TenantSetupStep> get outstanding => <TenantSetupStep>[
    if (!hasCurrency) TenantSetupStep.currency,
    if (!hasProducts) TenantSetupStep.products,
  ];
}

/// Reads how far a business has got, from what this device already holds.
final class TenantSetupChecklist {
  const TenantSetupChecklist({required CheckoutCatalogSource cache})
    : _cache = cache;

  final CheckoutCatalogSource _cache;

  /// Only an owner or an administrator is shown this.
  ///
  /// A cashier can fix neither step, and a card telling somebody to go and
  /// publish a currency they have no permission to publish is worse than no
  /// card.
  static const List<TenantRole> allowedRoles = <TenantRole>[
    TenantRole.owner,
    TenantRole.admin,
  ];

  static bool showsInSession(TenantSession session) =>
      session.canAccess(allowedRoles: allowedRoles);

  Future<TenantSetupState> read(TenantSession session) async {
    final snapshot = await _cache.read(
      uid: session.uid,
      tenantId: session.tenantId,
    );
    if (snapshot == null) return const TenantSetupState.unknown();
    return TenantSetupState(
      // The refresher only writes a snapshot once it has a configuration to
      // write, so the currency being present *is* the snapshot existing. Read
      // explicitly anyway rather than inferred, so a later refresher that
      // caches more eagerly does not silently make this lie.
      hasCurrency: snapshot.configuration.currency.trim().isNotEmpty,
      hasProducts: snapshot.products.isNotEmpty,
    );
  }
}

/// What each outstanding step is called, and what it unblocks.
String tenantSetupStepLabel(TenantSetupStep step) => switch (step) {
  TenantSetupStep.currency => 'Choose the currency this shop trades in',
  TenantSetupStep.products => 'Add something to sell',
};

String tenantSetupStepDetail(TenantSetupStep step) => switch (step) {
  TenantSetupStep.currency =>
    'Until this is set the register cannot price a sale, and it will refuse every '
        'one.',
  TenantSetupStep.products =>
    'The catalog is empty, so there is nothing to ring up yet.',
};

/// The card that says what is still outstanding, and opens the screen that
/// fixes each thing.
///
/// **Absent once complete, and absent while it does not know.** It appears for
/// exactly as long as it has something to say, which is what stops it becoming
/// the banner everybody scrolls past.
final class TenantSetupChecklistCard extends StatelessWidget {
  const TenantSetupChecklistCard({
    super.key,
    required this.state,
    this.onOpenCurrency,
    this.onOpenProducts,
  });

  final TenantSetupState state;
  final VoidCallback? onOpenCurrency;
  final VoidCallback? onOpenProducts;

  VoidCallback? _actionFor(TenantSetupStep step) => switch (step) {
    TenantSetupStep.currency => onOpenCurrency,
    TenantSetupStep.products => onOpenProducts,
  };

  @override
  Widget build(BuildContext context) {
    final outstanding = state.outstanding;
    if (outstanding.isEmpty) return const SizedBox.shrink();
    final tokens = AppTokens.componentOf(context);

    return Padding(
      padding: EdgeInsets.only(bottom: tokens.spacing.s16),
      child: Container(
        padding: EdgeInsets.all(tokens.spacing.s16),
        decoration: BoxDecoration(
          color: tokens.colors.surface.raised,
          borderRadius: BorderRadius.circular(tokens.radius.lg),
          border: Border.all(color: tokens.colors.surface.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Semantics(
              header: true,
              child: Text(
                'Before this shop can sell',
                key: const ValueKey('setup-checklist-heading'),
                style: tokens.typography.titleMedium.copyWith(
                  color: tokens.colors.text.primary,
                ),
              ),
            ),
            for (final step in outstanding) ...<Widget>[
              SizedBox(height: tokens.spacing.s16),
              _SetupRow(step: step, onPressed: _actionFor(step)),
            ],
          ],
        ),
      ),
    );
  }
}

final class _SetupRow extends StatelessWidget {
  const _SetupRow({required this.step, required this.onPressed});

  final TenantSetupStep step;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          tenantSetupStepLabel(step),
          key: ValueKey('setup-step-${step.name}'),
          style: tokens.typography.bodyMedium.copyWith(
            color: tokens.colors.text.primary,
          ),
        ),
        SizedBox(height: tokens.spacing.s4),
        Text(
          tenantSetupStepDetail(step),
          style: tokens.typography.caption.copyWith(
            color: tokens.colors.text.secondary,
          ),
        ),
        if (onPressed != null) ...<Widget>[
          SizedBox(height: tokens.spacing.s8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton(
              key: ValueKey('setup-open-${step.name}'),
              label: switch (step) {
                TenantSetupStep.currency => 'Open settings',
                TenantSetupStep.products => 'Open inventory',
              },
              tier: AppButtonTier.secondary,
              onPressed: onPressed,
            ),
          ),
        ],
      ],
    );
  }
}
