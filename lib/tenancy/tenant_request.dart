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
    required this.requestId,
  });

  final String uid;
  final String name;
  final String slug;
  final String requestId;
}

final class TenantRequestResult {
  const TenantRequestResult._({
    required this.tenantId,
    required this.name,
    required this.slug,
    required this.provisionalUntil,
  });

  factory TenantRequestResult.fromCallable(
    Object? value, {
    required String expectedName,
    required String expectedSlug,
  }) {
    const keys = {'tenantId', 'name', 'slug', 'status', 'provisionalUntil'};
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
    try {
      tenantId = validateTenantId(data['tenantId']! as String);
      name = normalizeTenantRequestName(data['name']! as String);
      slug = normalizeTenantRequestSlug(data['slug']! as String);
    } on ArgumentError {
      throw const FormatException('requestTenant returned an invalid result.');
    }
    if (name != expectedName || slug != expectedSlug) {
      throw const FormatException('requestTenant returned another business.');
    }
    return TenantRequestResult._(
      tenantId: tenantId,
      name: name,
      slug: slug,
      provisionalUntil: provisionalUntil,
    );
  }

  final String tenantId;
  final String name;
  final String slug;

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
  }) {
    if (!_identity.canRequestTenant) {
      throw StateError('This identity cannot request a tenant.');
    }
    final normalizedName = normalizeTenantRequestName(name);
    final normalizedSlug = normalizeTenantRequestSlug(slug);
    final requestId = _requestIdFactory();
    if (!_tenantRequestIdPattern.hasMatch(requestId)) {
      throw StateError('The tenant request ID generator is invalid.');
    }
    return TenantRequestIntent._(
      uid: _identity.uid,
      name: normalizedName,
      slug: normalizedSlug,
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
      'requestId': intent.requestId,
    });
    return TenantRequestResult.fromCallable(
      response,
      expectedName: intent.name,
      expectedSlug: intent.slug,
    );
  }
}

final class TenantRequestForm extends StatefulWidget {
  const TenantRequestForm({
    super.key,
    required this.identity,
    required this.callable,
    required this.onSuccess,
    required this.onCancel,
    this.requestIdFactory,
    this.isCurrent,
    this.clock,
  });

  final TenantRequestIdentity identity;
  final RequestTenantCallable callable;
  final ValueChanged<TenantRequestResult> onSuccess;
  final VoidCallback onCancel;
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
    super.dispose();
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
    try {
      final gateway = _gateway();
      final intent = gateway.createIntent(
        name: _nameController.text,
        // Derived rather than asked for: see `deriveTenantRequestSlug`.
        slug: deriveTenantRequestSlug(
          _nameController.text,
          (widget.clock ?? DateTime.now)().toUtc(),
        ),
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
          SectionHeading('Request a business'),
          SizedBox(height: tokens.spacing.s8),
          const Text('New businesses remain pending until platform review.'),
          SizedBox(height: tokens.spacing.s16),
          AppTextField(
            key: const ValueKey('tenant-request-name'),
            controller: _nameController,
            enabled: !_submitting,
            label: 'Business name',
            autovalidateMode: AutovalidateMode.onUserInteraction,
            onChanged: _fieldChanged,
            validator: (value) => _validateName(value ?? ''),
          ),

          if (_confirming && _intent != null) ...[
            SizedBox(height: tokens.spacing.s16),
            Text(
              'Submit ${_intent!.name} (${_intent!.slug}) for platform review?',
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
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
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
              AppButton(
                key: ValueKey(
                  _confirming
                      ? 'tenant-request-confirm'
                      : 'tenant-request-review',
                ),
                label: _confirming ? 'Submit request' : 'Review request',
                icon: Icons.add_business_outlined,
                tier: AppButtonTier.primary,
                loading: _submitting,
                onPressed: _confirming ? _submit : _review,
              ),
            ],
          ),
        ],
      ),
    );
  }
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
final _tenantRequestIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$');
