/// Adding a customer, or correcting one, as a sheet over the page it was opened
/// from - the Customers screen, or the till.
///
/// A sheet rather than a route, for the reason a supplier's form is one: a
/// customer is a short errand, and at the till the person it is about is
/// standing at the counter waiting for it to finish.
library;

import 'package:flutter/material.dart';
import 'package:uzapay_pos/observability/app_telemetry.dart';


import '../tenancy/phone_number.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_session.dart';
import '../ui/buttons.dart';
import '../ui/fields.dart';
import '../ui/sheet.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'customer.dart';

/// What the form answers with once it closes.
final class CustomerFormOutcome {
  const CustomerFormOutcome({required this.notice, this.customer});

  final AppNotice notice;

  /// The customer as they now stand on this device - the one just added, or
  /// the one already holding the number when the person chose them instead.
  /// Null after a correction, which the page it came from reads back.
  final TenantCustomer? customer;
}

/// Opens the customer form, answering with what happened, or null when it was
/// cancelled.
///
/// [customer] is the customer being corrected; null adds a new one. [atTill]
/// asks for what a counter needs - name, number, consent, KRA PIN - and, when
/// the number already belongs to somebody, offers to choose them instead.
Future<CustomerFormOutcome?> showCustomerFormSheet(
  BuildContext context, {
  required TenantSession session,
  required TenantDocumentReader reader,
  required TenantCustomerWriter writer,
  TenantCustomer? customer,
  DialCode? dialCode,
  bool atTill = false,
  String? requestIdOverride,
}) => showAppSheet<CustomerFormOutcome>(
  context,
  builder: (sheetContext, scrollController) => _CustomerForm(
    session: session,
    reader: reader,
    writer: writer,
    customer: customer,
    dialCode: dialCode ?? defaultDialCode,
    atTill: atTill,
    requestIdOverride: requestIdOverride,
    scrollController: scrollController,
    onCompleted: (outcome) => Navigator.of(sheetContext).pop(outcome),
    onCancel: () => Navigator.of(sheetContext).pop(),
  ),
);

/// The dialling code a business's customers most likely have, from the
/// currency it sells in.
///
/// **A starting point, never a rule.** A Kenyan shop sells in shillings and
/// its customers' numbers start +254, so that is what the form opens on; a
/// visitor's number is one tap on the selector away.
DialCode dialCodeForCurrency(String? currency) {
  final code = switch (currency) {
    'KES' => '+254',
    'TZS' => '+255',
    'UGX' => '+256',
    'RWF' => '+250',
    'BIF' => '+257',
    'CDF' => '+243',
    'ZMW' => '+260',
    'MWK' => '+265',
    'MZN' => '+258',
    'ZAR' => '+27',
    'ETB' => '+251',
    'SOS' => '+252',
    'GBP' => '+44',
    'INR' => '+91',
    'CNY' => '+86',
    'AED' => '+971',
    _ => null,
  };
  return dialCodes.firstWhere(
    (candidate) => candidate.code == code,
    orElse: () => defaultDialCode,
  );
}

/// The sentence a refusal the form can name is reported in.
String customerRefusalMessage(String code) => switch (code) {
  'invalid_customer_name' =>
    'Enter the customer\'s name, up to $maximumCustomerNameLength characters.',
  'invalid_customer_phone' => 'That does not look like a mobile number.',
  'invalid_customer_email' => 'That email address is not one mail can reach.',
  'invalid_customer_kra_pin' =>
    'A KRA PIN is a letter, nine digits and a letter, such as A012345678Z.',
  'invalid_customer_notes' =>
    'Notes may be up to $maximumCustomerNotesLength characters.',
  'consent_needs_phone' =>
    'Add their number first: WhatsApp receipts go to a phone number.',
  'consent_needs_email' =>
    'Add their email first: email receipts go to an email address.',
  'invalid_customer_credit_limit' =>
    'A credit limit is a whole amount, zero or more.',
  'customer_unchanged' => 'Nothing has been changed yet.',
  'customer_forbidden' =>
    'Only an owner, administrator or manager may change a customer.',
  _ => 'This customer could not be saved as entered.',
};

final class _CustomerForm extends StatefulWidget {
  const _CustomerForm({
    required this.session,
    required this.reader,
    required this.writer,
    required this.customer,
    required this.dialCode,
    required this.atTill,
    required this.requestIdOverride,
    required this.scrollController,
    required this.onCompleted,
    required this.onCancel,
  });

  final TenantSession session;
  final TenantDocumentReader reader;
  final TenantCustomerWriter writer;
  final TenantCustomer? customer;
  final DialCode dialCode;
  final bool atTill;
  final String? requestIdOverride;
  final ScrollController scrollController;
  final ValueChanged<CustomerFormOutcome> onCompleted;
  final VoidCallback onCancel;

  @override
  State<_CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends State<_CustomerForm> {
  late final TenantCustomer? _editing = widget.customer;
  late final ({DialCode dialCode, String localNumber})? _stored = splitE164(
    _editing?.phone,
  );
  late DialCode _dialCode = _stored?.dialCode ?? widget.dialCode;
  late final TextEditingController _name = TextEditingController(
    text: _editing?.name ?? '',
  );
  late final TextEditingController _phone = TextEditingController(
    text: _stored?.localNumber ?? '',
  );
  late final TextEditingController _email = TextEditingController(
    text: _editing?.email ?? '',
  );
  late final TextEditingController _kraPin = TextEditingController(
    text: _editing?.kraPin ?? '',
  );
  late final TextEditingController _notes = TextEditingController(
    text: _editing?.notes ?? '',
  );
  late bool _optedIn = _editing?.whatsappOptIn ?? false;
  late bool _emailOptedIn = _editing?.emailOptIn ?? false;
  late bool _creditAllowed = !(_editing?.creditBlocked ?? false);

  /// Whether this form offers the credit switch: away from the till, to the
  /// people who may decide whether the shop lends its money.
  bool get _offersCredit =>
      !widget.atTill &&
      TenantCustomerRepository.canManageInSession(widget.session);

  bool _busy = false;
  String? _error;
  String? _phoneError;

  /// The customer already holding the number typed, offered at the till.
  TenantCustomer? _holder;

  /// One request per customer being added, held until the add settles, so a
  /// second press names the same customer rather than a second one.
  String? _requestId;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _kraPin.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _hasNumber => _phone.text.trim().isNotEmpty;

  bool get _hasEmail => _email.text.trim().isNotEmpty;

  bool get _canSubmit => !_busy && _name.text.trim().isNotEmpty;

  /// The number in E.164, '' for none, or null when what was typed is not a
  /// number - in which case the field already says why.
  String? _composedPhone() {
    if (!_hasNumber) return '';
    final defect = phoneNumberDefect(
      dialCode: _dialCode,
      localNumber: _phone.text,
    );
    if (defect != null) {
      setState(() => _phoneError = defect);
      return null;
    }
    return normalizeE164(dialCode: _dialCode, localNumber: _phone.text);
  }

  TenantCustomerDraft _draft(String phone) => TenantCustomerDraft(
    name: _name.text,
    phone: phone,
    email: _email.text,
    kraPin: _kraPin.text,
    notes: _notes.text,
    whatsappOptIn: phone.isNotEmpty && _optedIn,
    emailOptIn: _hasEmail && _emailOptedIn,
    // A limit set before limits were withdrawn is carried, never changed.
    creditLimitMinor: _editing?.creditLimitMinor,
    // Untouched where the form does not offer it: a cashier editing nothing
    // about credit changes nothing about credit.
    creditAllowed: _offersCredit
        ? _creditAllowed
        : !(_editing?.creditBlocked ?? false),
  );

  TenantCustomerRepository _repository(TenantDocumentReader reader) =>
      TenantCustomerRepository(session: widget.session, reader: reader);

  /// The customer this device can see already holding [phone], or null.
  ///
  /// **Asked of this device's copy**, so a cashier with no signal is answered
  /// at once; the server checks every customer again when the add reaches it.
  /// A lookup that cannot be made is not a reason to stop somebody adding a
  /// customer, so a failure answers null.
  Future<TenantCustomer?> _holderOf(String phone) async {
    try {
      return await _repository(
        widget.reader.cached ?? widget.reader,
      ).holderOfPhone(phone, exceptId: _editing?.id);
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'customers.phone_lookup',
      );
      return null;
    }
  }

  Future<void> _submit() async {
    final phone = _composedPhone();
    if (phone == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _holder = null;
    });
    final telemetry = AppTelemetry.current;
    final operation = telemetry.start(
      _editing == null ? 'customers.create' : 'customers.update',
      screen: widget.atTill ? 'checkout' : 'customers',
      context: {'customer_id': _editing?.id},
    );
    try {
      final draft = _draft(phone);
      if (phone.isNotEmpty && phone != _editing?.phone) {
        final holder = await _holderOf(phone);
        if (!mounted) return;
        if (holder != null) {
          setState(() {
            _busy = false;
            _holder = holder;
            _error =
                'This number already belongs to ${holder.name}. One number '
                'reaches one person, so it can be on one customer.';
          });
          return;
        }
      }
      final editing = _editing;
      if (editing == null) {
        final intent = _repository(widget.reader).buildCreateIntent(
          draft: draft,
          requestId: _requestId ??=
              widget.requestIdOverride ?? secureTenantCustomerRequestId(),
        );
        await telemetry.trace(
          operation,
          'save_customer',
          () => widget.writer.createCustomer(intent),
        );
        telemetry.recordStep(operation, 'saved_locally');
        if (!mounted) return;
        widget.onCompleted(
          CustomerFormOutcome(
            notice: AppNotice.confirmed(
              widget.atTill
                  ? '${intent.name} added, and chosen for this sale.'
                  : '${intent.name} added. They can be chosen at the till '
                        'straight away, and are on their way to the server '
                        'now.',
            ),
            customer: TenantCustomer.fromDocument(
              path: intent.path,
              data: intent.documentData(),
            ),
          ),
        );
      } else {
        final intent = _repository(
          widget.reader,
        ).buildUpdateIntent(customer: editing, draft: draft);
        await telemetry.trace(
          operation,
          'save_customer',
          () => widget.writer.updateCustomer(intent),
        );
        telemetry.recordStep(operation, 'saved_locally');
        if (!mounted) return;
        final name = intent.changes[TenantCustomerField.name] ?? editing.name;
        widget.onCompleted(
          CustomerFormOutcome(
            notice: AppNotice.confirmed(
              '$name saved. It is on its way to the server now; every other '
              'device picks it up when it syncs.',
            ),
          ),
        );
      }
    } on TenantCustomerException catch (error, stackTrace) {
      AppTelemetry.captureHandled(error, stackTrace, operation: operation);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = customerRefusalMessage(error.code);
      });
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(error, stackTrace, operation: operation);
      // Nothing durable could be written on this device - a full disk, an
      // unreadable box. Nothing was recorded anywhere, so the same entry may
      // simply be tried again.
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            'This customer could not be saved on this device, so nothing was '
            'recorded. Try again.';
      });
    }
  }

  void _chooseHolder() {
    final holder = _holder;
    if (holder == null) return;
    widget.onCompleted(
      CustomerFormOutcome(
        notice: AppNotice.confirmed('${holder.name} chosen for this sale.'),
        customer: holder,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final adding = _editing == null;
    final title = adding ? 'Add customer' : 'Edit customer';
    return ListView(
      key: const ValueKey('customer-form'),
      controller: widget.scrollController,
      padding: EdgeInsets.all(tokens.spacing.s24),
      children: <Widget>[
        Text(
          title,
          style: tokens.typography.titleMedium.copyWith(
            color: tokens.colors.text.primary,
          ),
        ),
        SizedBox(height: tokens.spacing.s8),
        Text(
          'Only the name is needed. A number lets their receipt go to them on '
          'WhatsApp, if they agree.',
          style: tokens.typography.caption.copyWith(
            color: tokens.colors.text.tertiary,
          ),
        ),
        SizedBox(height: tokens.spacing.s24),
        AppTextField(
          key: const ValueKey('customer-form-name'),
          controller: _name,
          enabled: !_busy,
          label: 'Name',
          leading: Icons.person_outline,
          maxLength: maximumCustomerNameLength,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
        ),
        SizedBox(height: tokens.spacing.s12),
        AppPhoneField(
          key: const ValueKey('customer-form-phone'),
          label: 'Phone (optional)',
          error: _phoneError,
          enabled: !_busy,
          code: _dialCode.code,
          codes: <AppSelectItem<String>>[
            for (final code in dialCodes)
              AppSelectItem<String>(
                key: ValueKey('customer-form-dial-${code.digits}'),
                value: code.code,
                label: '${code.country} (${code.code})',
              ),
          ],
          onCodeChanged: (value) => setState(() {
            _dialCode = dialCodes.firstWhere(
              (candidate) => candidate.code == value,
              orElse: () => _dialCode,
            );
            _phoneError = null;
          }),
          controller: _phone,
          onChanged: (_) => setState(() {
            _phoneError = null;
            _holder = null;
          }),
        ),
        // **Only once there is a number to agree for.** A tick with nothing to
        // send to would record consent to nothing.
        if (_hasNumber) ...<Widget>[
          SizedBox(height: tokens.spacing.s4),
          CheckboxListTile(
            key: const ValueKey('customer-form-whatsapp-consent'),
            value: _optedIn,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Agreed to get receipts on WhatsApp'),
            subtitle: const Text(
              'Ask them first. They can say no, and can stop receipts at any '
              'time by replying STOP.',
            ),
            onChanged: _busy
                ? null
                : (value) => setState(() => _optedIn = value ?? false),
          ),
        ],
        SizedBox(height: tokens.spacing.s12),
        AppTextField(
          key: const ValueKey('customer-form-kraPin'),
          controller: _kraPin,
          enabled: !_busy,
          label: 'KRA PIN (optional)',
          leading: Icons.badge_outlined,
          placeholder: 'A012345678Z',
          helper: 'Printed on their receipts, for a business buyer.',
          maxLength: 11,
          textCapitalization: TextCapitalization.characters,
        ),
        if (!widget.atTill) ...<Widget>[
          SizedBox(height: tokens.spacing.s12),
          AppTextField(
            key: const ValueKey('customer-form-email'),
            controller: _email,
            enabled: !_busy,
            label: 'Email (optional)',
            leading: Icons.mail_outline,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => setState(() {}),
          ),
          // Only once there is an address to agree for, as with WhatsApp.
          if (_hasEmail) ...<Widget>[
            SizedBox(height: tokens.spacing.s4),
            CheckboxListTile(
              key: const ValueKey('customer-form-email-consent'),
              value: _emailOptedIn,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Agreed to get receipts by email'),
              subtitle: const Text(
                'Ask them first. Every receipt has a link to stop them.',
              ),
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _emailOptedIn = value ?? false),
            ),
          ],
          SizedBox(height: tokens.spacing.s12),
          AppTextField(
            key: const ValueKey('customer-form-notes'),
            controller: _notes,
            enabled: !_busy,
            label: 'Notes (optional)',
            maxLength: maximumCustomerNotesLength,
            maxLines: 4,
            minLines: 2,
            helper: 'What they usually buy, how they like to be reached.',
          ),
        ],
        if (_offersCredit) ...<Widget>[
          SizedBox(height: tokens.spacing.s4),
          CheckboxListTile(
            key: const ValueKey('customer-form-credit-allowed'),
            value: _creditAllowed,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Can buy on credit'),
            subtitle: Text(
              _creditAllowed
                  ? 'The till can put their sales on their account.'
                  : 'The till will not put their sales on credit.',
            ),
            onChanged: _busy
                ? null
                : (value) => setState(() => _creditAllowed = value ?? true),
          ),
        ],
        if (_error case final message?) ...<Widget>[
          SizedBox(height: tokens.spacing.s12),
          Callout(
            key: const ValueKey('customer-form-error'),
            status: AppStatus.problem,
            message: message,
          ),
        ],
        if (_holder case final holder? when widget.atTill) ...<Widget>[
          SizedBox(height: tokens.spacing.s12),
          AppButton(
            key: const ValueKey('customer-form-choose-existing'),
            label: 'Choose ${holder.name}',
            icon: Icons.how_to_reg_outlined,
            expand: true,
            onPressed: _chooseHolder,
          ),
        ],
        SizedBox(height: tokens.spacing.s32),
        AppButton(
          key: const ValueKey('customer-form-submit'),
          label: adding ? 'Add customer' : 'Save customer',
          tier: AppButtonTier.secondary,
          loading: _busy,
          expand: true,
          onPressed: _canSubmit ? _submit : null,
        ),
        SizedBox(height: tokens.spacing.s12),
        AppButton(
          key: const ValueKey('customer-form-cancel'),
          label: 'Cancel',
          expand: true,
          onPressed: _busy ? null : widget.onCancel,
        ),
      ],
    );
  }
}
