import 'dart:convert';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import '../ui/fields.dart';
import '../ui/scaffold.dart';
import '../ui/snackbar.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'tenant_bootstrap.dart';
import 'tenant_id.dart';
import 'tenant_types.dart';

typedef TenantRequestIdFactory = String Function();
typedef TenantRequestCurrentCheck = bool Function();

abstract interface class RequestTenantCallable {
  Future<Object?> call(Map<String, Object?> payload);
}

final class TenantRequestCallableException implements Exception {
  const TenantRequestCallableException(this.code);

  final String code;
}

final class FirebaseRequestTenantCallable implements RequestTenantCallable {
  FirebaseRequestTenantCallable({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    try {
      final result = await _functions
          .httpsCallable('requestTenant')
          .call<Object?>(payload);
      return result.data;
    } on FirebaseFunctionsException catch (error) {
      throw TenantRequestCallableException(error.code);
    }
  }
}

final class TenantRequestIdentity {
  factory TenantRequestIdentity({
    required String uid,
    required bool emailVerified,
    required RootRoutingProfile profile,
  }) => TenantRequestIdentity._(
    uid: validateTenantDocumentId(uid.trim(), fieldName: 'uid'),
    emailVerified: emailVerified,
    accountType: profile.accountType,
    globallyActive: profile.isActive,
  );

  const TenantRequestIdentity._({
    required this.uid,
    required this.emailVerified,
    required this.accountType,
    required this.globallyActive,
  });

  final String uid;
  final bool emailVerified;
  final RootAccountType accountType;
  final bool globallyActive;

  bool get canRequestTenant =>
      emailVerified &&
      globallyActive &&
      accountType == RootAccountType.tenantUser;
}

final class TenantRequestIntent {
  const TenantRequestIntent._({
    required this.uid,
    required this.name,
    required this.slug,
    required this.currency,
    required this.requestId,
  });

  final String uid;
  final String name;
  final String slug;

  /// The ISO 4217 code the business will trade in from its first minute.
  final String currency;
  final String requestId;
}

final class TenantRequestResult {
  const TenantRequestResult._({
    required this.tenantId,
    required this.name,
    required this.slug,
    required this.currency,
    required this.provisionalUntil,
  });

  factory TenantRequestResult.fromCallable(
    Object? value, {
    required String expectedName,
    required String expectedSlug,
    required String expectedCurrency,
  }) {
    const keys = {
      'tenantId',
      'name',
      'slug',
      'currency',
      'status',
      'provisionalUntil',
    };
    if (value is! Map || value.length != keys.length) {
      throw const FormatException(
        'requestTenant response must contain the expected fields.',
      );
    }
    final data = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String || !keys.contains(key)) {
        throw const FormatException(
          'requestTenant response must contain the expected fields.',
        );
      }
      data[key] = entry.value;
    }
    if (data['tenantId'] is! String ||
        data['name'] is! String ||
        data['slug'] is! String ||
        data['currency'] is! String ||
        data['status'] != 'pending' ||
        data['provisionalUntil'] is! int) {
      throw const FormatException('requestTenant returned an invalid result.');
    }
    // The instant the provisional trading window shuts, as the server computed
    // it. Read here so the confirmation can say how long there is without a
    // second round trip; the canonical copy lives on the tenant document and on
    // the membership mirror, and both are what every later screen reads.
    final provisionalUntil = DateTime.fromMillisecondsSinceEpoch(
      data['provisionalUntil']! as int,
      isUtc: true,
    );
    late final String tenantId;
    late final String name;
    late final String slug;
    late final String currency;
    try {
      tenantId = validateTenantId(data['tenantId']! as String);
      name = normalizeTenantRequestName(data['name']! as String);
      slug = normalizeTenantRequestSlug(data['slug']! as String);
      currency = normalizeTenantRequestCurrency(data['currency']! as String);
    } on ArgumentError {
      throw const FormatException('requestTenant returned an invalid result.');
    }
    if (name != expectedName ||
        slug != expectedSlug ||
        currency != expectedCurrency) {
      throw const FormatException('requestTenant returned another business.');
    }
    return TenantRequestResult._(
      tenantId: tenantId,
      name: name,
      slug: slug,
      currency: currency,
      provisionalUntil: provisionalUntil,
    );
  }

  final String tenantId;
  final String name;
  final String slug;

  /// What the business trades in, already published at `configuration/checkout`
  /// by the same transaction that created it - so the till can price a sale
  /// before anybody has opened Settings.
  final String currency;

  /// When the provisional trading window shuts, in UTC.
  ///
  /// A self-serve request may trade until this instant and may only be read
  /// after it. Approval before then replaces the question entirely.
  final DateTime provisionalUntil;
  TenantStatus get status => TenantStatus.pending;
}

final class TenantRequestGateway {
  TenantRequestGateway({
    required TenantRequestIdentity identity,
    required RequestTenantCallable callable,
    TenantRequestIdFactory? requestIdFactory,
  }) : _identity = identity,
       _callable = callable,
       _requestIdFactory = requestIdFactory ?? _secureTenantRequestId;

  final TenantRequestIdentity _identity;
  final RequestTenantCallable _callable;
  final TenantRequestIdFactory _requestIdFactory;

  TenantRequestIntent createIntent({
    required String name,
    required String slug,
    required String currency,
  }) {
    if (!_identity.canRequestTenant) {
      throw StateError('This identity cannot request a tenant.');
    }
    final normalizedName = normalizeTenantRequestName(name);
    final normalizedSlug = normalizeTenantRequestSlug(slug);
    final normalizedCurrency = normalizeTenantRequestCurrency(currency);
    final requestId = _requestIdFactory();
    if (!_tenantRequestIdPattern.hasMatch(requestId)) {
      throw StateError('The tenant request ID generator is invalid.');
    }
    return TenantRequestIntent._(
      uid: _identity.uid,
      name: normalizedName,
      slug: normalizedSlug,
      currency: normalizedCurrency,
      requestId: requestId,
    );
  }

  Future<TenantRequestResult> submit(TenantRequestIntent intent) async {
    if (!_identity.canRequestTenant || intent.uid != _identity.uid) {
      throw StateError('The tenant request intent belongs elsewhere.');
    }
    final response = await _callable.call(<String, Object?>{
      'name': intent.name,
      'slug': intent.slug,
      'currency': intent.currency,
      'requestId': intent.requestId,
    });
    return TenantRequestResult.fromCallable(
      response,
      expectedName: intent.name,
      expectedSlug: intent.slug,
      expectedCurrency: intent.currency,
    );
  }
}

/// The one form that creates a business, wherever a business is being created.
///
/// **Two hosts, one widget, deliberately.** It is the third step of onboarding
/// and it is the panel behind *Request business* on the selector, and those are
/// the same act: an owner making their second shop answers the same questions as
/// somebody making their first. Two forms would be two places for the currency
/// to be forgotten, and forgetting it is what `tenant_setup_checklist.dart`
/// exists to apologise for.
///
/// [heading], [description] and the button labels are the only difference
/// between the hosts, because the only difference between the hosts is what the
/// person is in the middle of.
final class TenantRequestForm extends StatefulWidget {
  const TenantRequestForm({
    super.key,
    required this.identity,
    required this.callable,
    required this.onSuccess,
    this.onCancel,
    this.heading = 'Request a business',
    this.description = 'New businesses remain pending until platform review.',
    this.pillSubmit = false,
    this.reviewLabel = 'Review request',
    this.submitLabel = 'Submit request',
    this.requestIdFactory,
    this.isCurrent,
    this.clock,
  });

  final TenantRequestIdentity identity;
  final RequestTenantCallable callable;
  final ValueChanged<TenantRequestResult> onSuccess;

  /// Null where there is nowhere to go back to - the onboarding step has no
  /// screen behind it, so it offers no Cancel. *Back* out of the confirmation
  /// is offered either way, because that one returns to this form.
  final VoidCallback? onCancel;

  /// Null draws no heading at all, for a host whose own frame already names
  /// the page - which is what the onboarding wizard's display heading does.
  final String? heading;

  /// Draws the submit as a capsule, for a host whose other primaries are.
  ///
  /// **Off by default and true only in onboarding.** The business selector
  /// hosts this same form inside the app, where every primary is `radius.md`;
  /// the wizard hosts it beside a sign-in screen whose submit is a capsule. The
  /// form should look like the page it is on rather than pick one shape and be
  /// wrong on the other.
  final bool pillSubmit;

  /// Null draws no paragraph, for a host whose frame already says this.
  ///
  /// The onboarding wizard's subheading carries the one fact worth standing
  /// above a form - that trading starts immediately - and what this used to add
  /// about the name is now the name field's own helper, which is where a fact
  /// about one field belongs.
  final String? description;
  final String reviewLabel;
  final String submitLabel;
  final TenantRequestIdFactory? requestIdFactory;
  final TenantRequestCurrentCheck? isCurrent;

  /// What the derived slug's timestamp is read from. Injected so a test can
  /// assert an exact slug rather than one that changes every minute.
  final DateTime Function()? clock;

  @override
  State<TenantRequestForm> createState() => _TenantRequestFormState();
}

final class _TenantRequestFormState extends State<TenantRequestForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _otherCurrencyController = TextEditingController();
  String _currencySelection = tenantRequestCurrencies.first;
  TenantRequestIntent? _intent;
  bool _confirming = false;
  bool _submitting = false;
  String? _safeError;

  @override
  void didUpdateWidget(covariant TenantRequestForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity.uid == widget.identity.uid &&
        oldWidget.identity.emailVerified == widget.identity.emailVerified &&
        oldWidget.identity.globallyActive == widget.identity.globallyActive &&
        oldWidget.identity.accountType == widget.identity.accountType) {
      return;
    }
    _resetIntent();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _otherCurrencyController.dispose();
    super.dispose();
  }

  /// What the two currency controls mean together.
  ///
  /// The select holds the answer unless it holds the sentinel, in which case the
  /// field beneath it does. Both ends normalize through the same function, so
  /// `kes` typed into the field is the `KES` the list would have given.
  String get _currency => _currencySelection == tenantRequestOtherCurrency
      ? _otherCurrencyController.text
      : _currencySelection;

  String? _validateCurrency() {
    if (_currencySelection != tenantRequestOtherCurrency) return null;
    try {
      normalizeTenantRequestCurrency(_otherCurrencyController.text);
      return null;
    } on ArgumentError {
      return 'Enter a three-letter ISO 4217 code, such as ZMW.';
    }
  }

  void _fieldChanged(String _) {
    if (_intent == null && !_confirming && _safeError == null) return;
    setState(_resetIntent);
  }

  void _resetIntent() {
    _intent = null;
    _confirming = false;
    _submitting = false;
    _safeError = null;
  }

  void _review() {
    if (_submitting || !_isCurrent()) return;
    if (!_formKey.currentState!.validate()) return;
    // The free-text currency is outside the `Form`, because it is only
    // sometimes there at all; validating it here keeps one refusal path.
    if (_validateCurrency() != null) {
      setState(() {});
      return;
    }
    try {
      final gateway = _gateway();
      final intent = gateway.createIntent(
        name: _nameController.text,
        // Derived rather than asked for: see `deriveTenantRequestSlug`.
        slug: deriveTenantRequestSlug(
          _nameController.text,
          (widget.clock ?? DateTime.now)().toUtc(),
        ),
        currency: _currency,
      );
      setState(() {
        _intent = intent;
        _confirming = true;
        _safeError = null;
      });
    } catch (_) {
      setState(() => _safeError = 'This business request is not valid.');
    }
  }

  Future<void> _submit() async {
    if (_submitting || !_isCurrent()) return;
    final intent = _intent;
    if (intent == null || intent.uid != widget.identity.uid) return;
    final submittedUid = widget.identity.uid;
    setState(() {
      _submitting = true;
      _safeError = null;
    });
    late final TenantRequestResult result;
    try {
      result = await _gateway().submit(intent);
    } catch (error) {
      if (!mounted || !_isStillCurrent(submittedUid, intent)) return;
      setState(() {
        _submitting = false;
        _safeError = tenantRequestSafeError(error);
      });
      return;
    }
    if (!mounted || !_isStillCurrent(submittedUid, intent)) return;
    setState(() => _submitting = false);
    showAppSnackBar(
      context,
      AppNotice.confirmed('${result.name} was submitted for review.'),
    );
    widget.onSuccess(result);
  }

  TenantRequestGateway _gateway() => TenantRequestGateway(
    identity: widget.identity,
    callable: widget.callable,
    requestIdFactory: widget.requestIdFactory,
  );

  bool _isStillCurrent(String uid, TenantRequestIntent intent) =>
      identical(_intent, intent) && widget.identity.uid == uid && _isCurrent();

  bool _isCurrent() => widget.isCurrent?.call() ?? true;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.heading case final title?) ...<Widget>[
            SectionHeading(title),
            SizedBox(height: tokens.spacing.s8),
          ],
          if (widget.description case final paragraph?) ...<Widget>[
            Text(paragraph),
            SizedBox(height: tokens.spacing.s16),
          ],
          AppTextField(
            key: const ValueKey('tenant-request-name'),
            controller: _nameController,
            enabled: !_submitting,
            label: 'Business name',
            // Moved off the standing paragraph on 2026-09-02: it is a fact
            // about this field, and a helper is where those go - which is also
            // how the currency field below already explains itself.
            helper: 'This names your till and every receipt it prints.',
            autovalidateMode: AutovalidateMode.onUserInteraction,
            onChanged: _fieldChanged,
            validator: (value) => _validateName(value ?? ''),
          ),
          SizedBox(height: tokens.spacing.s16),
          AppSelect<String>(
            key: const ValueKey('tenant-request-currency'),
            label: 'Currency',
            value: _currencySelection,
            enabled: !_submitting,
            helper: 'Every sale is recorded in this currency.',
            items: [
              for (final code in tenantRequestCurrencies)
                AppSelectItem<String>(
                  key: ValueKey('tenant-request-currency-$code'),
                  value: code,
                  label: '$code - ${_currencyNames[code] ?? code}',
                ),
              const AppSelectItem<String>(
                key: ValueKey('tenant-request-currency-other'),
                value: tenantRequestOtherCurrency,
                label: 'Something else',
              ),
            ],
            onChanged: _submitting
                ? null
                : (value) => setState(() {
                    _currencySelection = value ?? _currencySelection;
                    _resetIntent();
                  }),
          ),
          if (_currencySelection == tenantRequestOtherCurrency) ...[
            SizedBox(height: tokens.spacing.s12),
            AppTextField(
              key: const ValueKey('tenant-request-currency-code'),
              controller: _otherCurrencyController,
              enabled: !_submitting,
              label: 'ISO 4217 currency code',
              helper: 'Three letters, such as ZMW, MWK, or ETB.',
              error: _validateCurrency(),
              maxLength: 3,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: _fieldChanged,
            ),
          ],

          if (_confirming && _intent != null) ...[
            SizedBox(height: tokens.spacing.s16),
            Text(
              'Submit ${_intent!.name} (${_intent!.slug}), trading in '
              '${_intent!.currency}, for platform review?',
              key: const ValueKey('tenant-request-confirmation'),
            ),
          ],
          if (_safeError != null) ...[
            SizedBox(height: tokens.spacing.s12),
            Callout(
              key: const ValueKey('tenant-request-error'),
              // A refusal, named as one rather than painted red: the write
              // was attempted and nothing changed. Before this the whole of
              // the status was the colour, which is the case §9 rules out.
              status: AppNotice.refused(_safeError!).status,
              message: _safeError!,
            ),
          ],
          SizedBox(height: tokens.spacing.s16),
          // **A lone submit fills the row.** With a Cancel beside it the pair
          // sits at the trailing edge, which is the dialog convention this form
          // has always used. Without one - the onboarding step, which has no
          // screen behind it to cancel to - a right-aligned button was a
          // label-width box floating in a stretched column, while every other
          // step of that flow had a full-width primary.
          if (!_confirming && widget.onCancel == null)
            _submitButton(expand: true)
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_confirming || widget.onCancel != null) ...[
                  AppButton(
                    key: const ValueKey('tenant-request-cancel'),
                    label: _confirming ? 'Back' : 'Cancel',
                    tier: AppButtonTier.tertiary,
                    onPressed: _submitting
                        ? null
                        : _confirming
                        ? () => setState(() {
                            _confirming = false;
                            _safeError = null;
                          })
                        : widget.onCancel,
                  ),
                  SizedBox(width: tokens.spacing.s8),
                ],
                _submitButton(),
              ],
            ),
        ],
      ),
    );
  }

  /// The form's primary, in the two widths it is drawn at.
  Widget _submitButton({bool expand = false}) => AppButton(
    key: ValueKey(
      _confirming ? 'tenant-request-confirm' : 'tenant-request-review',
    ),
    label: _confirming ? widget.submitLabel : widget.reviewLabel,
    pill: widget.pillSubmit,
    expand: expand,
    icon: Icons.add_business_outlined,
    tier: AppButtonTier.primary,
    loading: _submitting,
    onPressed: _confirming ? _submit : _review,
  );
}

/// The offered currencies, most likely first.
///
/// **A short list rather than every ISO 4217 code**, because somebody setting up
/// a shop is choosing between the few their customers pay in, and a list of 180
/// is a worse question than a text field. [tenantRequestOtherCurrency] is the
/// escape hatch for everybody else and it validates identically - so the list is
/// a convenience over the field, never a restriction on it.
const List<String> tenantRequestCurrencies = <String>[
  'TZS',
  'KES',
  'UGX',
  'RWF',
];

/// What the currency select holds while the free-text field is the real answer.
const String tenantRequestOtherCurrency = 'other';

/// The same rule `TenantCheckoutConfigurationPublisher.buildUpdateIntent`
/// applies, because this writes the document that one replaces.
const Map<String, String> _currencyNames = <String, String>{
  'TZS': 'Tanzanian shilling',
  'KES': 'Kenyan shilling',
  'UGX': 'Ugandan shilling',
  'RWF': 'Rwandan franc',
};

String normalizeTenantRequestCurrency(String value) {
  final currency = value.trim().toUpperCase();
  if (!_tenantCurrencyPattern.hasMatch(currency)) {
    throw ArgumentError.value(
      value,
      'currency',
      'Must be a three-letter ISO 4217 code.',
    );
  }
  return currency;
}

String normalizeTenantRequestName(String value) {
  final name = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (name.length < 2 || name.length > 100 || _containsControl(name)) {
    throw ArgumentError.value(
      value,
      'name',
      'Must be 2 to 100 safe characters.',
    );
  }
  return name;
}

String normalizeTenantRequestSlug(String value) {
  final slug = value.trim().toLowerCase();
  if (slug.length < 3 ||
      slug.length > 48 ||
      !_tenantSlugPattern.hasMatch(slug) ||
      slug.contains('--')) {
    throw ArgumentError.value(value, 'slug', 'Has an invalid format.');
  }
  return slug;
}

/// The longest slug the server will accept.
const int maximumTenantSlugLength = 48;

/// `chilltent-20260830-1645` - the name, then when it was asked for.
///
/// **The slug stopped being a question on 2026-08-30.** It was a second field
/// asking somebody who wants to open a shop to invent a URL-safe identifier and
/// then explaining, in a helper line, what "lower-case letters, numbers and
/// single hyphens" means. Nothing in the app shows a slug to anybody afterwards
/// - it exists so `tenant_slugs/{slug}` can reserve a name - and the one thing
/// it must be is unique, which a person guessing is *worse* at than a clock is.
/// The failure it produced was the worst kind: `already-exists`, after the
/// form had been filled in, for a name somebody else had taken.
///
/// **The timestamp is what makes it unique, so it is not optional.** Two shops
/// called "Chilltent" a minute apart get different slugs; the same shop
/// requested twice in the same minute does not, and that collision is the one
/// the server's `already-exists` still exists to catch.
///
/// Minute precision rather than seconds: it is long enough to be unique in
/// practice and short enough to leave the name room inside 48 characters.
String deriveTenantRequestSlug(String name, DateTime nowUtc) {
  final stamp = _slugStamp(nowUtc);
  // Everything that is not a letter or a digit becomes one hyphen, which folds
  // spaces, apostrophes and ampersands alike. `&` in "Bob & Sons" is not worth
  // a rule of its own.
  var base = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  // A name made entirely of punctuation, or of a script this transliterates
  // nothing of, still has to produce a usable slug rather than a refusal.
  if (base.isEmpty) base = 'shop';
  final room = maximumTenantSlugLength - stamp.length - 1;
  if (base.length > room) {
    base = base.substring(0, room).replaceAll(RegExp(r'-$'), '');
  }
  if (base.isEmpty) base = 'shop';
  return '$base-$stamp';
}

String _slugStamp(DateTime nowUtc) {
  final t = nowUtc.toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}';
}

String tenantRequestSafeError(Object error) {
  if (error is TenantRequestCallableException) {
    return switch (error.code) {
      'already-exists' =>
        'That business slug is already in use. Choose another slug.',
      'resource-exhausted' =>
        'Your business request limit has been reached. Please try again later.',
      'failed-precondition' =>
        'This account is not currently eligible to request a business.',
      // Deliberately does not name which refusal it was. The server distinguishes
      // an inactive root, a platform identity and a sign-in older than an auth
      // cutoff; saying so here would leak the shape of accounts that are not the
      // caller's. What it must not do is invite a retry, which is what the
      // fallback below does and which cannot succeed for any of these.
      'permission-denied' =>
        'This account cannot request a business. Check that your email is '
            'verified and that you are signed in with the right account.',
      _ => 'Business request could not be submitted. Please try again.',
    };
  }
  return 'Business request could not be submitted. Please try again.';
}

String? _validateName(String value) {
  try {
    normalizeTenantRequestName(value);
    return null;
  } on ArgumentError {
    return 'Enter a business name between 2 and 100 characters.';
  }
}

bool _containsControl(String value) =>
    value.runes.any((rune) => rune <= 0x1f || (rune >= 0x7f && rune <= 0x9f));

String _secureTenantRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return 'tenant-${base64Url.encode(bytes).replaceAll('=', '')}';
}

final _tenantSlugPattern = RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])$');
final _tenantCurrencyPattern = RegExp(r'^[A-Z]{3}$');
final _tenantRequestIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$');
