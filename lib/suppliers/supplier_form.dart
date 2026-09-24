/// Adding a supplier, or correcting one, as a sheet over the page it was opened
/// from.
///
/// A sheet rather than a route, for the reason recording an expense is one: a
/// supplier is a short errand with one answer, and pushing a screen takes a
/// person away from the list - or the delivery - they were in the middle of.
library;

import 'package:flutter/material.dart';

import '../tenancy/tenant_session.dart';
import '../ui/buttons.dart';
import '../ui/fields.dart';
import '../ui/sheet.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'supplier.dart';

/// Opens the supplier form, answering with the notice to show once it closes,
/// or null when it was cancelled.
///
/// [supplier] is the supplier being corrected; null adds a new one. [directory]
/// is the directory the form was opened over, so a name another supplier
/// already answers to is refused on the form. [onSaved] receives the queued
/// supplier's ID, which is how a delivery form picks a supplier it just added.
Future<AppNotice?> showSupplierFormSheet(
  BuildContext context, {
  required TenantSession session,
  required TenantSupplierRepository repository,
  required TenantSupplierWriter writer,
  required TenantSupplierDirectory directory,
  TenantSupplier? supplier,
  ValueChanged<String>? onSaved,
  String? requestIdOverride,
}) => showAppSheet<AppNotice>(
  context,
  builder: (sheetContext, scrollController) => _SupplierForm(
    session: session,
    repository: repository,
    writer: writer,
    directory: directory,
    supplier: supplier,
    onSaved: onSaved,
    requestIdOverride: requestIdOverride,
    scrollController: scrollController,
    onCompleted: (notice) => Navigator.of(sheetContext).pop(notice),
    onCancel: () => Navigator.of(sheetContext).pop(),
  ),
);

/// The sentence a refusal the form can name is reported in.
///
/// Each names the field and what it may hold, because a refusal that only says
/// "invalid" is one a person can do nothing about.
String supplierRefusalMessage(String code) => switch (code) {
  'invalid_supplier_name' =>
    'Enter the supplier\'s name, up to $maximumSupplierNameLength characters.',
  'invalid_supplier_phone' =>
    'A phone number may hold digits, spaces and + ( ) - . only, up to '
        '$maximumSupplierPhoneLength characters.',
  'invalid_supplier_email' => 'That email address is not one mail can reach.',
  'invalid_supplier_address' =>
    'An address may be up to $maximumSupplierAddressLength characters on one '
        'line.',
  'invalid_supplier_tax_reference' =>
    'A tax or business reference may be up to '
        '$maximumSupplierTaxReferenceLength characters.',
  'invalid_supplier_notes' =>
    'Notes may be up to $maximumSupplierNotesLength characters.',
  'duplicate_supplier_name' =>
    'This business already has a supplier with that name. Two suppliers with '
        'one name would split one supplier\'s deliveries in two.',
  'supplier_unchanged' => 'Nothing has been changed yet.',
  'supplier_forbidden' =>
    'Only an owner, administrator or manager may change suppliers.',
  _ => 'This supplier could not be saved as entered.',
};

final class _SupplierForm extends StatefulWidget {
  const _SupplierForm({
    required this.session,
    required this.repository,
    required this.writer,
    required this.directory,
    required this.supplier,
    required this.onSaved,
    required this.requestIdOverride,
    required this.scrollController,
    required this.onCompleted,
    required this.onCancel,
  });

  final TenantSession session;
  final TenantSupplierRepository repository;
  final TenantSupplierWriter writer;
  final TenantSupplierDirectory directory;
  final TenantSupplier? supplier;
  final ValueChanged<String>? onSaved;
  final String? requestIdOverride;
  final ScrollController scrollController;
  final ValueChanged<AppNotice> onCompleted;
  final VoidCallback onCancel;

  @override
  State<_SupplierForm> createState() => _SupplierFormState();
}

class _SupplierFormState extends State<_SupplierForm> {
  late final TenantSupplierDraft _initial = widget.supplier == null
      ? const TenantSupplierDraft(name: '')
      : TenantSupplierDraft.of(widget.supplier!);
  late final Map<TenantSupplierField, TextEditingController> _controllers =
      <TenantSupplierField, TextEditingController>{
        for (final field in TenantSupplierField.values)
          field: TextEditingController(text: _initial.raw(field)),
      };

  bool _busy = false;
  String? _error;

  /// One request per supplier being added, held until the add settles, so a
  /// second press names the same supplier rather than a second one.
  String? _requestId;

  bool get _editing => widget.supplier != null;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TenantSupplierDraft get _draft => TenantSupplierDraft(
    name: _controllers[TenantSupplierField.name]!.text,
    phone: _controllers[TenantSupplierField.phone]!.text,
    email: _controllers[TenantSupplierField.email]!.text,
    address: _controllers[TenantSupplierField.address]!.text,
    taxReference: _controllers[TenantSupplierField.taxReference]!.text,
    notes: _controllers[TenantSupplierField.notes]!.text,
  );

  bool get _canSubmit =>
      !_busy && _controllers[TenantSupplierField.name]!.text.trim().isNotEmpty;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final supplier = widget.supplier;
      final String supplierId;
      final String name;
      if (supplier == null) {
        final intent = widget.repository.buildCreateIntent(
          draft: _draft,
          directory: widget.directory,
          requestId: _requestId ??=
              widget.requestIdOverride ?? secureTenantSupplierRequestId(),
        );
        await widget.writer.createSupplier(intent);
        supplierId = intent.supplierId;
        name = intent.name;
      } else {
        final intent = widget.repository.buildUpdateIntent(
          supplier: supplier,
          draft: _draft,
          directory: widget.directory,
        );
        await widget.writer.updateSupplier(intent);
        supplierId = supplier.id;
        name = intent.name ?? supplier.name;
      }
      if (!mounted) return;
      widget.onSaved?.call(supplierId);
      widget.onCompleted(
        AppNotice.confirmed(
          _editing
              ? '$name saved. It is on its way to the server now; every other '
                    'device picks it up when it syncs.'
              : '$name added. It can be chosen for a delivery straight away, '
                    'and is on its way to the server now.',
        ),
      );
    } on TenantSupplierException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = supplierRefusalMessage(error.code);
      });
    } catch (_) {
      // Nothing durable could be written on this device - a full disk, an
      // unreadable box. Nothing was recorded anywhere, so the same entry may
      // simply be tried again.
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            'This supplier could not be saved on this device, so nothing was '
            'recorded. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    Widget field(
      TenantSupplierField field, {
      required String label,
      IconData? leading,
      int? maxLength,
      TextInputType? keyboardType,
      int maxLines = 1,
      String? helper,
    }) => Padding(
      padding: EdgeInsets.only(bottom: tokens.spacing.s12),
      child: AppTextField(
        key: ValueKey('supplier-form-${field.wireKey}'),
        label: label,
        controller: _controllers[field],
        enabled: !_busy,
        leading: leading,
        maxLength: maxLength,
        keyboardType: keyboardType,
        maxLines: maxLines,
        minLines: maxLines > 1 ? 2 : null,
        helper: helper,
        onChanged: (_) => setState(() {}),
      ),
    );
    return ListView(
      key: const ValueKey('supplier-form'),
      controller: widget.scrollController,
      padding: EdgeInsets.all(tokens.spacing.s24),
      children: <Widget>[
        Text(
          _editing ? 'Edit supplier' : 'Add supplier',
          style: tokens.typography.titleMedium.copyWith(
            color: tokens.colors.text.primary,
          ),
        ),
        SizedBox(height: tokens.spacing.s8),
        Text(
          'Only the name is needed. The rest is how to reach them when stock '
          'runs short.',
          style: tokens.typography.caption.copyWith(
            color: tokens.colors.text.tertiary,
          ),
        ),
        SizedBox(height: tokens.spacing.s24),
        field(
          TenantSupplierField.name,
          label: 'Name',
          maxLength: maximumSupplierNameLength,
        ),
        field(
          TenantSupplierField.phone,
          label: 'Phone (optional)',
          leading: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
          maxLength: maximumSupplierPhoneLength,
        ),
        field(
          TenantSupplierField.email,
          label: 'Email (optional)',
          leading: Icons.mail_outline,
          keyboardType: TextInputType.emailAddress,
        ),
        field(
          TenantSupplierField.address,
          label: 'Address (optional)',
          leading: Icons.place_outlined,
          maxLength: maximumSupplierAddressLength,
        ),
        field(
          TenantSupplierField.taxReference,
          label: 'Tax or business reference (optional)',
          maxLength: maximumSupplierTaxReferenceLength,
        ),
        field(
          TenantSupplierField.notes,
          label: 'Notes (optional)',
          maxLength: maximumSupplierNotesLength,
          maxLines: 4,
          helper: 'Delivery days, who to ask for, anything worth remembering.',
        ),
        if (_error case final message?) ...<Widget>[
          SizedBox(height: tokens.spacing.s8),
          Callout(
            key: const ValueKey('supplier-form-error'),
            status: AppStatus.problem,
            message: message,
          ),
        ],
        SizedBox(height: tokens.spacing.s32),
        AppButton(
          key: const ValueKey('supplier-form-submit'),
          label: _editing ? 'Save supplier' : 'Add supplier',
          tier: AppButtonTier.primary,
          loading: _busy,
          expand: true,
          onPressed: _canSubmit ? _submit : null,
        ),
        SizedBox(height: tokens.spacing.s12),
        AppButton(
          key: const ValueKey('supplier-form-cancel'),
          label: 'Cancel',
          expand: true,
          onPressed: _busy ? null : widget.onCancel,
        ),
      ],
    );
  }
}
