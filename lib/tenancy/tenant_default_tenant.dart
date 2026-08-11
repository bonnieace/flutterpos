import 'dart:convert';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import 'tenant_id.dart';
import 'tenant_membership.dart';
import 'tenant_session.dart';
import 'tenant_session_controller.dart';

typedef TenantDefaultRequestIdFactory = String Function();

/// The narrow callable boundary for the enabled `setDefaultTenant` mutation.
abstract interface class SetDefaultTenantCallable {
  Future<Object?> call(Map<String, Object?> payload);
}

/// Firebase adapter for `setDefaultTenant`; validation remains above it.
final class FirebaseSetDefaultTenantCallable
    implements SetDefaultTenantCallable {
  FirebaseSetDefaultTenantCallable({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    final result = await _functions
        .httpsCallable('setDefaultTenant')
        .call<Object?>(payload);
    return result.data;
  }
}

/// One session-bound default-selection intent and its stable idempotency key.
final class TenantDefaultIntent {
  const TenantDefaultIntent._({
    required this.uid,
    required this.tenantId,
    required this.sessionEpoch,
    required this.requestId,
  });

  final String uid;
  final String tenantId;
  final int sessionEpoch;
  final String requestId;
}

/// Strictly decoded result from `setDefaultTenant`.
final class TenantDefaultResult {
  const TenantDefaultResult._({
    required this.tenantId,
    required this.defaultTenantId,
  });

  factory TenantDefaultResult.fromCallable(
    Object? value, {
    required String expectedTenantId,
  }) {
    const keys = {'tenantId', 'defaultTenantId'};
    if (value is! Map || value.length != keys.length) {
      throw const FormatException(
        'setDefaultTenant response must contain the expected fields.',
      );
    }
    final data = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String || !keys.contains(key)) {
        throw const FormatException(
          'setDefaultTenant response must contain the expected fields.',
        );
      }
      data[key] = entry.value;
    }
    if (data['tenantId'] is! String || data['defaultTenantId'] is! String) {
      throw const FormatException(
        'setDefaultTenant returned invalid tenant identifiers.',
      );
    }
    late final String tenantId;
    late final String defaultTenantId;
    try {
      tenantId = validateTenantId(data['tenantId']! as String);
      defaultTenantId = validateTenantId(data['defaultTenantId']! as String);
    } on ArgumentError {
      throw const FormatException(
        'setDefaultTenant returned invalid tenant identifiers.',
      );
    }
    if (tenantId != expectedTenantId || defaultTenantId != expectedTenantId) {
      throw const FormatException(
        'setDefaultTenant returned another default tenant.',
      );
    }
    return TenantDefaultResult._(
      tenantId: tenantId,
      defaultTenantId: defaultTenantId,
    );
  }

  final String tenantId;
  final String defaultTenantId;
}

/// Active-session-bound gateway with no arbitrary tenant input surface.
final class TenantDefaultGateway {
  TenantDefaultGateway({
    required TenantSession session,
    required SetDefaultTenantCallable callable,
    TenantDefaultRequestIdFactory? requestIdFactory,
  }) : _session = session,
       _callable = callable,
       _requestIdFactory = requestIdFactory ?? _secureDefaultRequestId;

  final TenantSession _session;
  final SetDefaultTenantCallable _callable;
  final TenantDefaultRequestIdFactory _requestIdFactory;

  TenantDefaultIntent createIntent() {
    _requireActiveSession();
    final requestId = _requestIdFactory();
    if (!_defaultRequestIdPattern.hasMatch(requestId)) {
      throw StateError('The default tenant request ID generator is invalid.');
    }
    return TenantDefaultIntent._(
      uid: _session.uid,
      tenantId: _session.tenantId,
      sessionEpoch: _session.epoch,
      requestId: requestId,
    );
  }

  Future<TenantDefaultResult> submit(TenantDefaultIntent intent) async {
    _requireActiveSession();
    if (intent.uid != _session.uid ||
        intent.tenantId != _session.tenantId ||
        intent.sessionEpoch != _session.epoch) {
      throw StateError('The default tenant intent belongs to another session.');
    }
    final response = await _callable.call(<String, Object?>{
      'tenantId': _session.tenantId,
      'requestId': intent.requestId,
    });
    return TenantDefaultResult.fromCallable(
      response,
      expectedTenantId: _session.tenantId,
    );
  }

  void _requireActiveSession() {
    if (!_session.canAccess()) {
      throw StateError('An active tenant session is required.');
    }
  }
}

/// Explicit, recoverable confirmation for the current tenant session.
final class TenantDefaultForm extends StatefulWidget {
  const TenantDefaultForm({
    super.key,
    required this.session,
    required this.membership,
    required this.callable,
    required this.onSuccess,
    required this.onCancel,
    this.requestIdFactory,
  });

  final TenantSession session;
  final TenantMembership membership;
  final SetDefaultTenantCallable callable;
  final VoidCallback onSuccess;
  final VoidCallback onCancel;
  final TenantDefaultRequestIdFactory? requestIdFactory;

  @override
  State<TenantDefaultForm> createState() => _TenantDefaultFormState();
}

final class _TenantDefaultFormState extends State<TenantDefaultForm> {
  TenantDefaultIntent? _intent;
  bool _submitting = false;
  String? _safeError;

  @override
  void didUpdateWidget(covariant TenantDefaultForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session == widget.session &&
        oldWidget.membership.tenantId == widget.membership.tenantId) {
      return;
    }
    _intent = null;
    _submitting = false;
    _safeError = null;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final controller = TenantSessionScope.read(context);
    final submittedSession = widget.session;
    if (!_isCurrent(controller, submittedSession)) return;
    if (widget.membership.tenantId != submittedSession.tenantId) {
      setState(() => _safeError = 'This business cannot be made default.');
      return;
    }
    final gateway = TenantDefaultGateway(
      session: submittedSession,
      callable: widget.callable,
      requestIdFactory: widget.requestIdFactory,
    );
    late final TenantDefaultIntent intent;
    try {
      intent = _intent ??= gateway.createIntent();
    } catch (_) {
      if (!mounted || !_isCurrent(controller, submittedSession)) return;
      setState(() => _safeError = 'This business cannot be made default.');
      return;
    }
    setState(() {
      _submitting = true;
      _safeError = null;
    });
    try {
      await gateway.submit(intent);
    } catch (_) {
      if (!mounted || !_isCurrent(controller, submittedSession)) return;
      setState(() {
        _submitting = false;
        _safeError = 'Default business could not be changed. Please try again.';
      });
      return;
    }
    if (!mounted || !_isCurrent(controller, submittedSession)) return;
    setState(() => _submitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${widget.membership.tenantName} is now default.'),
      ),
    );
    widget.onSuccess();
  }

  bool _isCurrent(TenantSessionController controller, TenantSession expected) {
    final current = controller.session;
    return widget.session == expected &&
        widget.membership.tenantId == expected.tenantId &&
        current != null &&
        current.uid == expected.uid &&
        current.tenantId == expected.tenantId &&
        current.epoch == expected.epoch &&
        current.canAccess();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Make ${widget.membership.tenantName} your default business?',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      const Text(
        'This business will be preferred when no valid device selection exists.',
      ),
      if (_safeError != null) ...[
        const SizedBox(height: 12),
        Text(
          _safeError!,
          key: const ValueKey('set-default-tenant-error'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
      const SizedBox(height: 16),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(
            key: const ValueKey('set-default-tenant-cancel'),
            label: 'Cancel',
            tier: AppButtonTier.tertiary,
            onPressed: _submitting ? null : widget.onCancel,
          ),
          const SizedBox(width: 8),
          AppButton(
            key: const ValueKey('set-default-tenant-confirm'),
            label: 'Make default',
            icon: Icons.star_outline,
            tier: AppButtonTier.primary,
            loading: _submitting,
            onPressed: _submit,
          ),
        ],
      ),
    ],
  );
}

String _secureDefaultRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return 'default-${base64Url.encode(bytes).replaceAll('=', '')}';
}

final _defaultRequestIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$');
