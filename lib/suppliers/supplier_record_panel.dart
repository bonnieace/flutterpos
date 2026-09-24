/// One supplier: how to reach them, their standing, and - once deliveries
/// exist - what each delivery brought in.
library;

import 'package:flutter/material.dart';

import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../ui/buttons.dart';
import '../ui/card.dart';
import '../ui/scaffold.dart';
import '../ui/snackbar.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'supplier.dart';
import 'supplier_delivery_history.dart';
import 'supplier_delivery_panel.dart';
import 'supplier_directory_panel.dart';
import 'supplier_form.dart';

/// What the record route reads: the supplier, and the directory it sits in,
/// which a correction's duplicate-name check is made against.
final class TenantSupplierRecordView {
  const TenantSupplierRecordView({
    required this.supplier,
    required this.directory,
  });

  /// Null when this business holds no supplier by the ID the route was opened
  /// with.
  final TenantSupplier? supplier;
  final TenantSupplierDirectory directory;
}

/// One supplier's record, as a route.
final class TenantSupplierRecordScreen extends StatefulWidget {
  const TenantSupplierRecordScreen({
    super.key,
    required this.reader,
    required this.supplierId,
    this.writer,
    this.deliveries,
  });

  final TenantDataReader reader;
  final String supplierId;
  final TenantSupplierWriter? writer;

  /// What receiving a delivery needs. Null offers no *Receive delivery*; the
  /// history of deliveries is read either way.
  final TenantSupplierDeliveryServices? deliveries;

  @override
  State<TenantSupplierRecordScreen> createState() =>
      _TenantSupplierRecordScreenState();
}

final class _TenantSupplierRecordScreenState
    extends State<TenantSupplierRecordScreen> {
  int _generation = 0;
  int? _loadersFor;
  late TenantGuardedLoader<TenantSupplierRecordView> _loader;
  TenantGuardedLoader<TenantSupplierRecordView>? _loaderCached;

  void _composeLoaders() {
    if (_loadersFor == _generation) return;
    _loadersFor = _generation;
    TenantGuardedLoader<TenantSupplierRecordView> readWith(
      TenantDataReader reader,
    ) => (session) async {
      final directory = await TenantSupplierRepository(
        session: session,
        reader: reader,
      ).loadDirectory();
      return TenantSupplierRecordView(
        supplier: directory.byId(widget.supplierId),
        directory: directory,
      );
    };
    _loader = readWith(widget.reader);
    final cached = widget.reader.cached;
    _loaderCached = cached == null ? null : readWith(cached);
  }

  void _reload() => setState(() => _generation++);

  Future<void> _edit(TenantSession session, TenantSupplierRecordView view) async {
    final writer = widget.writer;
    final supplier = view.supplier;
    if (writer == null || supplier == null) return;
    final notice = await showSupplierFormSheet(
      context,
      session: session,
      repository: TenantSupplierRepository(session: session, reader: widget.reader),
      writer: writer,
      directory: view.directory,
      supplier: supplier,
    );
    if (!mounted || notice == null) return;
    showAppSnackBar(context, notice);
    _reload();
  }

  Future<void> _setActive(
    TenantSession session,
    TenantSupplier supplier, {
    required bool active,
  }) async {
    final writer = widget.writer;
    if (writer == null) return;
    final notice = await setSupplierStanding(
      context,
      session: session,
      reader: widget.reader,
      writer: writer,
      supplier: supplier,
      active: active,
    );
    if (!mounted || notice == null) return;
    showAppSnackBar(context, notice);
    _reload();
  }

  Future<void> _receive(TenantSupplier supplier) async {
    final deliveries = widget.deliveries;
    if (deliveries == null) return;
    final notice = await openReceiveDeliveryScreen(
      context,
      reader: widget.reader,
      services: deliveries,
      supplierWriter: widget.writer,
      supplierId: supplier.id,
    );
    if (!mounted || notice == null) return;
    showAppSnackBar(context, notice);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    _composeLoaders();
    return TenantRouteGuard<TenantSupplierRecordView>(
      allowedRoles: TenantSupplierRepository.allowedRoles,
      load: _loader,
      loadCached: _loaderCached,
      loading: const _RecordFrame(
        title: 'Supplier',
        child: LoadingState(message: 'Reading this supplier'),
      ),
      failure: (context, error) => const _RecordFrame(
        title: 'Supplier',
        child: ErrorState(
          key: ValueKey('supplier-record-failure'),
          badgeLabel: 'Not read',
          statement: 'This supplier could not be read.',
          stillTrue: 'Nothing has been recorded or changed.',
        ),
      ),
      builder: (context, session, view) {
        final supplier = view.supplier;
        if (supplier == null) {
          return const _RecordFrame(
            title: 'Supplier',
            child: EmptyState(
              key: ValueKey('supplier-record-missing'),
              title: 'This supplier is not in this business',
              hint: 'It may have been added on a device that has not synced '
                  'yet.',
              illustration: 'file-search.svg',
            ),
          );
        }
        return _RecordFrame(
          title: supplier.name,
          child: _RecordContents(
            supplier: supplier,
            primaryAction: widget.deliveries == null
                ? null
                : AppButton(
                    key: const ValueKey('supplier-record-receive'),
                    label: 'Receive delivery',
                    icon: Icons.local_shipping_outlined,
                    tier: AppButtonTier.primary,
                    expand: true,
                    onPressed: () => _receive(supplier),
                  ),
            // Keyed by the generation, so a delivery just received is read
            // back into the history rather than the section keeping its page.
            history: TenantSupplierDeliveryHistory(
              key: ValueKey('supplier-deliveries-$_generation'),
              reader: widget.reader,
              session: session,
              supplier: supplier,
            ),
            onEdit: widget.writer == null ? null : () => _edit(session, view),
            onSetActive: widget.writer == null
                ? null
                : (active) => _setActive(session, supplier, active: active),
          ),
        );
      },
    );
  }
}

final class _RecordFrame extends StatelessWidget {
  const _RecordFrame({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: title,
    subtitle: 'Supplier',
    contentWidth: AppContentWidth.records,
    body: child,
  );
}

final class _RecordContents extends StatelessWidget {
  const _RecordContents({
    required this.supplier,
    required this.primaryAction,
    required this.history,
    required this.onEdit,
    required this.onSetActive,
  });

  final TenantSupplier supplier;
  final Widget? primaryAction;
  final Widget? history;
  final VoidCallback? onEdit;
  final ValueChanged<bool>? onSetActive;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final inset = width < AppLayout.contract.mediumFloor
        ? tokens.spacing.s16
        : tokens.spacing.s24;
    final facts = <(String, String, IconData)>[
      if (supplier.phone case final phone?) ('Phone', phone, Icons.phone_outlined),
      if (supplier.email case final email?) ('Email', email, Icons.mail_outline),
      if (supplier.address case final address?)
        ('Address', address, Icons.place_outlined),
      if (supplier.taxReference case final reference?)
        ('Tax or business reference', reference, Icons.badge_outlined),
      if (supplier.notes case final notes?) ('Notes', notes, Icons.notes_outlined),
      (
        'Last delivery',
        supplierLastDeliveryLabel(supplier),
        Icons.local_shipping_outlined,
      ),
    ];
    return ListView(
      key: const ValueKey('supplier-record'),
      padding: EdgeInsets.all(inset),
      children: <Widget>[
        if (!supplier.active) ...<Widget>[
          const Callout(
            key: ValueKey('supplier-record-inactive'),
            status: AppStatus.neutral,
            title: 'Inactive',
            message:
                'Not offered when a delivery is received. Its deliveries stay '
                'on record, and it can be offered again below.',
          ),
          SizedBox(height: tokens.spacing.s16),
        ],
        if (primaryAction case final action? when supplier.active) ...<Widget>[
          action,
          SizedBox(height: tokens.spacing.s12),
        ],
        if (onEdit != null || onSetActive != null) ...<Widget>[
          Wrap(
            spacing: tokens.spacing.s8,
            runSpacing: tokens.spacing.s8,
            children: <Widget>[
              if (onEdit case final edit?)
                AppButton(
                  key: const ValueKey('supplier-record-edit'),
                  label: 'Edit',
                  icon: Icons.edit_outlined,
                  onPressed: edit,
                ),
              if (onSetActive case final setActive?)
                supplier.active
                    ? AppButton(
                        key: const ValueKey('supplier-record-inactive-action'),
                        label: 'Mark inactive',
                        icon: Icons.block_outlined,
                        tier: AppButtonTier.destructive,
                        onPressed: () => setActive(false),
                      )
                    : AppButton(
                        key: const ValueKey('supplier-record-reactivate'),
                        label: 'Reactivate',
                        icon: Icons.replay_outlined,
                        onPressed: () => setActive(true),
                      ),
            ],
          ),
          SizedBox(height: tokens.spacing.s16),
        ],
        const SectionHeading('How to reach them'),
        SizedBox(height: tokens.spacing.s8),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final (index, fact) in facts.indexed) ...<Widget>[
                if (index > 0) SizedBox(height: tokens.spacing.s12),
                _Fact(label: fact.$1, value: fact.$2, icon: fact.$3),
              ],
            ],
          ),
        ),
        if (history case final section?) ...<Widget>[
          SizedBox(height: tokens.spacing.s24),
          section,
        ],
      ],
    );
  }
}

/// One contact detail: a caption, and the value under it.
final class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: AppButton.iconSize, color: tokens.colors.text.tertiary),
        SizedBox(width: tokens.spacing.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: tokens.typography.caption.copyWith(
                  color: tokens.colors.text.tertiary,
                ),
              ),
              SizedBox(height: tokens.spacing.s4),
              SelectableText(
                value,
                style: tokens.typography.bodyMedium.copyWith(
                  color: tokens.colors.text.primary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
