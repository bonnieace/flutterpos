/// Signing up, as one continuous act instead of three disconnected surfaces.
///
/// **What this replaces.** Registration used to take an email and a password,
/// deliberately not navigate, and leave the person on *Choose a business* - a
/// screen about picking from a list - where a verification card appeared because
/// that was the one screen an unverified identity was stuck on. They pressed a
/// button to send their own first email, left for their mailbox, read a web page
/// telling them to come back and refresh, came back, pressed *I have verified*,
/// then found a business to create behind a toggle in the app bar of the same
/// list screen. Four surfaces, three of them about something else, and two
/// buttons doing work the app could have done itself.
///
/// **The step is derived from state, never counted.** [deriveOnboardingStep]
/// reads what the account actually has - a name, a verified address, a business -
/// and answers where the person is. That is the whole of resuming: somebody who
/// closed the app on the verify step, or who signed up months ago and never
/// finished, re-enters exactly where they stopped, and no migration or stored
/// cursor is involved. It is also why the account step has two shapes: an
/// account that already exists needs a name, not a password.
///
/// **Nobody presses anything to receive the first email.** `completeSelfSignup`
/// enqueues it as part of saving the name, and the verify step then watches for
/// the address turning verified - on every app resume, and on a timer while it
/// is on screen - so returning from the mailbox advances the flow on its own.
/// *Send again* and *I have verified* remain, as the paths for when that does
/// not happen.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import '../ui/fields.dart';
import '../ui/illustration.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'account_profile.dart';
import 'account_registration.dart';
import 'account_verification.dart';
import 'phone_number.dart';
import 'sign_in.dart' show SignInFailureKind;
import 'tenant_bootstrap.dart';
import 'tenant_request.dart';

/// Where somebody is in signing up.
enum OnboardingStep { account, verify, business, complete }

/// Reads the step from the account's own state.
///
/// Pure, and the single source of truth for the flow's position: both hosts call
/// it, so the pushed wizard and the one the routing shell draws can never
/// disagree about where somebody is.
OnboardingStep deriveOnboardingStep({
  required bool accountExists,
  required String? displayName,
  required String? phone,
  required bool emailVerified,
}) {
  if (!accountExists) return OnboardingStep.account;
  if ((displayName ?? '').trim().isEmpty || (phone ?? '').trim().isEmpty) {
    return OnboardingStep.account;
  }
  if (!emailVerified) return OnboardingStep.verify;
  return OnboardingStep.business;
}

/// What the flow needs to know about the signed-in identity, if there is one.
@immutable
final class OnboardingIdentity {
  const OnboardingIdentity({
    this.uid,
    this.email,
    this.emailVerified = false,
    this.displayName,
    this.phone,
    this.profile,
  });

  /// Null before the account has been created, which is step one's whole shape.
  final String? uid;
  final String? email;
  final bool emailVerified;
  final String? displayName;
  final String? phone;

  /// The root routing profile where a host already has one. The pushed wizard
  /// has not bootstrapped yet and passes none; see [_requestIdentity].
  final RootRoutingProfile? profile;
}

typedef OnboardingIdentityReader = OnboardingIdentity Function();
typedef OnboardingCurrentCheck = bool Function();

/// How often the verify step asks whether the address has turned verified.
///
/// **Two cadences, because the wait has two halves.** Somebody who follows the
/// link immediately is back within a minute and should not sit on a verified
/// address waiting for a slow tick; somebody who was interrupted may be gone for
/// an hour and must not have their battery polled every five seconds for it. The
/// resume listener is the real mechanism - this is what covers verifying on
/// another device while this one stays open.
const Duration onboardingEagerPollInterval = Duration(seconds: 5);
const Duration onboardingRelaxedPollInterval = Duration(seconds: 15);
const Duration onboardingEagerPollWindow = Duration(minutes: 2);

final class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({
    super.key,
    required this.readIdentity,
    required this.reloadIdentity,
    required this.onSignOut,
    this.onOpenBusiness,
    this.registration,
    this.completeSelfSignupCallable,
    this.changeSignupEmailCallable,
    this.sendAccountVerificationCallable,
    this.requestTenantCallable,
    this.accountProfileRequestIdFactory,
    this.accountVerificationRequestIdFactory,
    this.tenantRequestIdFactory,
    this.isCurrent,
    this.clock,
  });

  /// The live identity, re-read on every build rather than captured once.
  final OnboardingIdentityReader readIdentity;

  /// Refreshes the Auth record so `emailVerified` can change. Everything the
  /// verify step does rests on this.
  final Future<void> Function() reloadIdentity;

  final Future<void> Function() onSignOut;

  /// Opens the business that was just created. Null leaves the last step with
  /// nothing to press, which is what a host that cannot route wants.
  final ValueChanged<TenantRequestResult>? onOpenBusiness;

  final EmailPasswordRegistration? registration;
  final CompleteSelfSignupCallable? completeSelfSignupCallable;
  final ChangeSignupEmailCallable? changeSignupEmailCallable;
  final SendAccountVerificationCallable? sendAccountVerificationCallable;
  final RequestTenantCallable? requestTenantCallable;
  final AccountProfileRequestIdFactory? accountProfileRequestIdFactory;
  final AccountVerificationRequestIdFactory?
  accountVerificationRequestIdFactory;
  final TenantRequestIdFactory? tenantRequestIdFactory;

  /// Whether this instance is the one on screen.
  ///
  /// **Two of these can exist at once.** The wizard is pushed above the routing
  /// shell, and the shell draws its own for an account that is resuming - so
  /// without this the polling timer runs twice and the auto-send fires twice.
  /// The server's `requestId` idempotency is the second line of defence; this is
  /// the first. It is the same seam `TenantBusinessSelector` already threads
  /// through its panels.
  final OnboardingCurrentCheck? isCurrent;

  final DateTime Function()? clock;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow>
    with WidgetsBindingObserver {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _newEmailController = TextEditingController();

  DialCode _dialCode = defaultDialCode;
  bool _busy = false;
  bool _changingEmail = false;
  AppNotice? _notice;
  String? _nameError;
  String? _phoneError;

  /// What this flow knows it saved, which the identity reader cannot see until
  /// the root document has been re-read. Held so the step advances the instant
  /// the call returns rather than a bootstrap later.
  String? _savedDisplayName;
  String? _savedPhone;

  TenantRequestResult? _result;

  Timer? _poll;
  DateTime? _verifyingSince;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final identity = widget.readIdentity();
    _nameController.text = identity.displayName ?? '';
    final split = splitE164(identity.phone);
    if (split != null) {
      _dialCode = split.dialCode;
      _phoneController.text = split.localNumber;
    }
    _emailController.text = identity.email ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncPolling());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _newEmailController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // **The single most important line in this file.** Somebody leaves for their
    // mailbox, follows the link, and comes back to the app; this is the moment
    // the app can notice without being told. Everything else - the timer, the
    // App Link, the button - is a fallback for when this does not fire.
    if (state == AppLifecycleState.resumed) unawaited(_refreshIdentity());
  }

  bool _isCurrent() => widget.isCurrent?.call() ?? true;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  OnboardingStep get _step {
    if (_result != null) return OnboardingStep.complete;
    final identity = widget.readIdentity();
    return deriveOnboardingStep(
      accountExists: identity.uid != null,
      displayName: _savedDisplayName ?? identity.displayName,
      phone: _savedPhone ?? identity.phone,
      emailVerified: identity.emailVerified,
    );
  }

  /// Starts, retimes or stops the watch, from whatever the step now is.
  void _syncPolling() {
    _poll?.cancel();
    _poll = null;
    if (!mounted || _step != OnboardingStep.verify || !_isCurrent()) {
      _verifyingSince = null;
      return;
    }
    final since = _verifyingSince ??= _now();
    final interval = _now().difference(since) < onboardingEagerPollWindow
        ? onboardingEagerPollInterval
        : onboardingRelaxedPollInterval;
    _poll = Timer(interval, () async {
      await _refreshIdentity();
      _syncPolling();
    });
  }

  Future<void> _refreshIdentity() async {
    if (!mounted || !_isCurrent()) return;
    if (_step != OnboardingStep.verify) return;
    try {
      await widget.reloadIdentity();
    } catch (_) {
      // A refresh that could not reach the server says nothing about whether
      // the address is verified, so it changes nothing and is not an error the
      // person needs to read. The next tick asks again.
      return;
    }
    if (!mounted) return;
    setState(() {});
    _syncPolling();
  }

  AccountProfileGateway get _profileGateway => AccountProfileGateway(
    completeCallable:
        widget.completeSelfSignupCallable ??
        FirebaseCompleteSelfSignupCallable(),
    changeEmailCallable:
        widget.changeSignupEmailCallable ?? FirebaseChangeSignupEmailCallable(),
    requestIdFactory: widget.accountProfileRequestIdFactory,
  );

  // ---------------------------------------------------------------- step one

  /// Creates the account where there is not one, then names it.
  ///
  /// **Two calls, and the order matters.** `createUserWithEmailAndPassword`
  /// fires the blocking function that writes the root document, and only then
  /// does an identity exist for `completeSelfSignup` to name. A failure between
  /// them leaves an account with no name - which the step derivation reads as
  /// step one again, in its reduced shape, so the next attempt finishes the job
  /// rather than starting a second account.
  Future<void> _submitAccount() async {
    if (_busy || !_isCurrent()) return;
    final identity = widget.readIdentity();
    final creating = identity.uid == null;

    final nameDefect = accountNameDefect(_nameController.text);
    final phoneDefect = phoneNumberDefect(
      dialCode: _dialCode,
      localNumber: _phoneController.text,
    );
    RegistrationInputDefect? credentialDefect;
    if (creating) {
      credentialDefect = registrationInputDefect(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        confirmation: _confirmController.text,
      );
    }
    if (nameDefect != null || phoneDefect != null || credentialDefect != null) {
      setState(() {
        _nameError = nameDefect == null
            ? null
            : accountProfileInputDefectMessage(nameDefect);
        _phoneError = phoneDefect;
        _notice = credentialDefect == null
            ? null
            : AppNotice.refused(
                registrationInputDefectMessage(credentialDefect),
              );
      });
      return;
    }

    setState(() {
      _busy = true;
      _notice = null;
      _nameError = null;
      _phoneError = null;
    });
    try {
      if (creating) {
        final registration =
            widget.registration ?? FirebaseEmailPasswordRegistration();
        await registration.call(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
      final phone = normalizeE164(
        dialCode: _dialCode,
        localNumber: _phoneController.text,
      );
      await _profileGateway.completeSignup(
        displayName: _nameController.text,
        phone: phone,
      );
      if (!mounted) return;
      setState(() {
        _savedDisplayName = _nameController.text.trim();
        _savedPhone = phone;
        _passwordController.clear();
        _confirmController.clear();
        _busy = false;
      });
      _syncPolling();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _notice = _noticeFor(error);
      });
    }
  }

  /// One sentence for a refusal, from whichever boundary raised it.
  AppNotice _noticeFor(Object error) {
    if (error is RegistrationException) {
      final failure = registrationFailure(error);
      return failure.kind == SignInFailureKind.unreachable
          ? AppNotice.offline(failure.message)
          : AppNotice.refused(failure.message);
    }
    final failure = accountProfileFailure(error);
    return failure.kind == SignInFailureKind.unreachable
        ? AppNotice.offline(failure.message)
        : AppNotice.refused(failure.message);
  }

  // ---------------------------------------------------------------- step two

  Future<void> _resend() async {
    final identity = widget.readIdentity();
    final uid = identity.uid;
    if (_busy || uid == null || !_isCurrent()) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final gateway = AccountVerificationGateway(
        identity: AccountVerificationIdentity(
          uid: uid,
          emailVerified: identity.emailVerified,
          profile: identity.profile ?? _assumedProfile,
        ),
        callable:
            widget.sendAccountVerificationCallable ??
            FirebaseSendAccountVerificationCallable(),
        requestIdFactory: widget.accountVerificationRequestIdFactory,
      );
      await gateway.send(gateway.createIntent());
      if (!mounted) return;
      setState(() {
        _busy = false;
        // Deliberately not "sent": the server accepts responsibility for a
        // request, which is not the same as a message arriving. See
        // `AccountVerificationResult`.
        _notice = const AppNotice.confirmed(
          'Another email has been requested.',
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _notice = AppNotice.refused(accountVerificationSafeError(error));
      });
    }
  }

  Future<void> _changeEmail() async {
    if (_busy || !_isCurrent()) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final email = await _profileGateway.changeEmail(_newEmailController.text);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _changingEmail = false;
        _emailController.text = email;
        _newEmailController.clear();
        _notice = const AppNotice.confirmed(
          'Your address has been changed. A new link is on its way to it.',
        );
      });
      // The address moved, so the wait restarts and the eager cadence with it.
      _verifyingSince = null;
      _syncPolling();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _notice = _noticeFor(error);
      });
    }
  }

  // -------------------------------------------------------------- step three

  /// The routing profile an account at this point in the flow demonstrably has.
  ///
  /// The pushed wizard has never bootstrapped, so it holds no
  /// [RootRoutingProfile] - but it has just watched `bootstrapSelfSignupIdentity`
  /// create the root document, and that function writes exactly these two values
  /// and no others. The server re-reads the canonical record on every call
  /// regardless; this only decides whether a button is offered.
  static const RootRoutingProfile _assumedProfile = RootRoutingProfile(
    accountType: RootAccountType.tenantUser,
    globalStatus: 'active',
  );

  TenantRequestIdentity? _requestIdentity() {
    final identity = widget.readIdentity();
    final uid = identity.uid;
    if (uid == null) return null;
    return TenantRequestIdentity(
      uid: uid,
      emailVerified: identity.emailVerified,
      profile: identity.profile ?? _assumedProfile,
    );
  }

  void _businessCreated(TenantRequestResult result) {
    _poll?.cancel();
    setState(() {
      _result = result;
      _notice = null;
    });
  }

  // -------------------------------------------------------------------- view

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final step = _step;
    // **The sign-in screen's frame, not `AppScaffold`'s, since 2026-09-02.**
    // Signing in and signing up are one errand seen twice, and they were drawn
    // as two different kinds of page: sign-in a bare centred credential column,
    // this a titled route with a toolbar, a back arrow and a progress bar. The
    // frame is what carried that difference - a person reads the shape of a
    // page before they read a word of it - so it is the frame that moves.
    //
    // Every value below is `_form`'s in `login_screen.dart`: `surface.base` on
    // a bare `Scaffold`, the s24/s32 inset, `layout.credential`, and the
    // display-plus-body heading pair with s8 between them and s40 under.
    return Scaffold(
      backgroundColor: tokens.colors.surface.base,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: tokens.spacing.s24,
              vertical: tokens.spacing.s32,
            ),
            child: ConstrainedBox(
              // 448, whose own token doc reads "sign-in, and the tenant-entry
              // screens" - so this column was always meant to be one of these
              // and was the only one not taking it.
              constraints: BoxConstraints(maxWidth: tokens.layout.credential),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // **The heading is the step indicator now.** The stepper is
                  // gone at the product owner's direction on 2026-09-02: three
                  // steps is a flow, not a process worth charting, and the bar
                  // spent the top of every screen saying so. What it did carry
                  // - where you are, and how much is left - the subheadings say
                  // in words instead.
                  Semantics(
                    header: true,
                    child: Text(
                      _heading(step),
                      key: const ValueKey('onboarding-heading'),
                      style: tokens.typography.display.copyWith(
                        color: tokens.colors.text.primary,
                      ),
                    ),
                  ),
                  SizedBox(height: tokens.spacing.s8),
                  Text(
                    _subheading(step),
                    key: const ValueKey('onboarding-subheading'),
                    style: tokens.typography.bodyLarge.copyWith(
                      color: tokens.colors.text.secondary,
                    ),
                  ),
                  SizedBox(height: tokens.spacing.s40),
                  if (_notice != null) ...<Widget>[
                    Callout(
                      key: const ValueKey('onboarding-notice'),
                      status: _notice!.status,
                      message: _notice!.message,
                    ),
                    SizedBox(height: tokens.spacing.s16),
                  ],
                  switch (step) {
                    OnboardingStep.account => _buildAccountStep(tokens),
                    OnboardingStep.verify => _buildVerifyStep(tokens),
                    OnboardingStep.business => _buildBusinessStep(),
                    OnboardingStep.complete => _buildCompleteStep(tokens),
                  },
                  // **The way out, which the toolbar used to hold.** Losing the
                  // app bar loses its back arrow, and a flow with no exit is a
                  // trap for anybody who mistyped an address on step 1. It sits
                  // at the foot rather than the top because it is the last
                  // thing anyone here wants, and it is a real button rather
                  // than a tappable word for hard rule 4's 48.
                  if (step != OnboardingStep.complete &&
                      widget.readIdentity().uid != null) ...<Widget>[
                    SizedBox(height: tokens.spacing.s24),
                    Center(
                      child: AppButton(
                        key: const ValueKey('onboarding-sign-out'),
                        label: 'Sign out',
                        tier: AppButtonTier.tertiary,
                        onPressed: _busy ? null : widget.onSignOut,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The step's name, in the role `login_screen.dart` gives *Welcome back*.
  String _heading(OnboardingStep step) => switch (step) {
    OnboardingStep.account =>
      widget.readIdentity().uid == null
          ? 'Create your account'
          : 'Almost there',
    OnboardingStep.verify => 'Check your email',
    OnboardingStep.business => 'Your business',
    OnboardingStep.complete => "You're set up",
  };

  /// One plain sentence under it, in the role *Sign in to your account* holds.
  ///
  /// **These carry what the progress bar used to.** Each one says where the
  /// person is in the flow - *two more steps*, *one more step*, *the last one* -
  /// so removing the chart did not remove the answer to "how much of this is
  /// left", which is the only question it was really answering.
  String _subheading(OnboardingStep step) => switch (step) {
    OnboardingStep.account =>
      widget.readIdentity().uid == null
          ? 'Two more steps and your till is open.'
          : 'Finish the account you already started.',
    OnboardingStep.verify =>
      'We sent a link to ${widget.readIdentity().email ?? 'your address'}. '
          'Open it and this screen moves on by itself.',
    OnboardingStep.business =>
      'The last step. You can trade straight away while it is reviewed.',
    OnboardingStep.complete => 'Your till is ready to take its first sale.',
  };

  Widget _buildAccountStep(AppTokens tokens) {
    final creating = widget.readIdentity().uid == null;
    return Column(
      key: const ValueKey('onboarding-account-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppTextField(
          key: const ValueKey('onboarding-name'),
          controller: _nameController,
          enabled: !_busy,
          label: 'Full name',
          // The glyph and the example between them do what a helper sentence
          // was doing: say what belongs in the box without spending a line
          // under it.
          leading: Icons.person_outline,
          placeholder: 'Amina Wanjiru',
          error: _nameError,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) {
            if (_nameError != null) setState(() => _nameError = null);
          },
        ),
        SizedBox(height: tokens.spacing.s16),
        AppPhoneField(
          key: const ValueKey('onboarding-phone'),
          label: 'Mobile number',
          // No `leading` and no placeholder: the dial-code selector is this
          // field's leading control and `AppPhoneField` already shows
          // `712 345 678` in the box, which is the example wanted here.
          error: _phoneError,
          enabled: !_busy,
          code: _dialCode.code,
          codes: <AppSelectItem<String>>[
            for (final code in dialCodes)
              AppSelectItem<String>(
                key: ValueKey('onboarding-dial-${code.digits}'),
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
          controller: _phoneController,
          onChanged: (_) {
            if (_phoneError != null) setState(() => _phoneError = null);
          },
        ),
        if (creating) ...[
          SizedBox(height: tokens.spacing.s16),
          AppTextField(
            key: const ValueKey('onboarding-email'),
            controller: _emailController,
            enabled: !_busy,
            label: 'Email',
            // `email_outlined` and this exact example are what the sign-in
            // screen shows in the same box, which is the whole point of the
            // change: the field a person met on the way in is the field they
            // meet on the way up.
            leading: Icons.email_outlined,
            placeholder: 'name@example.com',
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            enableSuggestions: false,
          ),
          SizedBox(height: tokens.spacing.s16),
          AppTextField(
            key: const ValueKey('onboarding-password'),
            controller: _passwordController,
            enabled: !_busy,
            label: 'Choose a password',
            leading: Icons.lock_outline,
            helper: 'At least $minimumRegistrationPasswordLength characters.',
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
          ),
          SizedBox(height: tokens.spacing.s16),
          AppTextField(
            key: const ValueKey('onboarding-confirm'),
            controller: _confirmController,
            enabled: !_busy,
            label: 'Type it again',
            leading: Icons.lock_outline,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
          ),
        ],
        SizedBox(height: tokens.spacing.s24),
        AppButton(
          key: const ValueKey('onboarding-account-submit'),
          label: creating ? 'Create account' : 'Continue',
          tier: AppButtonTier.primary,
          // The step's one action, so it takes the step's whole width rather
          // than sitting as a label-width box in a stretched column.
          expand: true,
          // **A capsule, because the sign-in screen's submit is one.** The
          // primary action is the most-looked-at thing on either screen, and
          // *Sign in* being a capsule while *Create account* was a rounded
          // rectangle was the loudest remaining difference between two pages
          // that are meant to read as one errand.
          pill: true,
          loading: _busy,
          onPressed: _submitAccount,
        ),
      ],
    );
  }

  Widget _buildVerifyStep(AppTokens tokens) {
    return Column(
      key: const ValueKey('onboarding-verify-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // **The one step where nothing is being typed and nothing can be
        // hurried.** A person is waiting on a message in another app, and the
        // screen has no field to draw their eye - so the drawing is doing the
        // work the form does everywhere else, which is telling them at a glance
        // what this page is about.
        //
        // It sits above the controls and not below them because at 168 it still
        // leaves *Send again* and *Wrong address?* on the first screenful of a
        // 360x640 handset - measured, because this is the one page somebody
        // reaches when they are already stuck.
        Center(
          child: AppIllustration(
            key: const ValueKey('onboarding-verify-illustration'),
            asset: 'mail-sent.svg',
            size: EmptyState.illustrationSize,
            semanticLabel: 'A letter on its way',
          ),
        ),
        SizedBox(height: tokens.spacing.s24),
        Row(
          children: <Widget>[
            Expanded(
              child: AppButton(
                key: const ValueKey('onboarding-verify-recheck'),
                label: 'I have verified',
                tier: AppButtonTier.primary,
                loading: _busy,
                onPressed: _busy ? null : _refreshIdentity,
              ),
            ),
            SizedBox(width: tokens.spacing.s8),
            AppButton(
              key: const ValueKey('onboarding-verify-resend'),
              label: 'Send again',
              tier: AppButtonTier.secondary,
              onPressed: _busy ? null : _resend,
            ),
          ],
        ),
        SizedBox(height: tokens.spacing.s16),
        if (!_changingEmail)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton(
              key: const ValueKey('onboarding-verify-change-email'),
              label: 'Wrong address?',
              tier: AppButtonTier.tertiary,
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _changingEmail = true;
                      _newEmailController.text = '';
                      _notice = null;
                    }),
            ),
          )
        else ...[
          AppTextField(
            key: const ValueKey('onboarding-verify-new-email'),
            controller: _newEmailController,
            enabled: !_busy,
            label: 'Your email address',
            helper: 'We will send a new link to this one instead.',
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            enableSuggestions: false,
          ),
          SizedBox(height: tokens.spacing.s12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              AppButton(
                key: const ValueKey('onboarding-verify-change-cancel'),
                label: 'Cancel',
                tier: AppButtonTier.tertiary,
                onPressed: _busy
                    ? null
                    : () => setState(() => _changingEmail = false),
              ),
              SizedBox(width: tokens.spacing.s8),
              AppButton(
                key: const ValueKey('onboarding-verify-change-submit'),
                label: 'Use this address',
                tier: AppButtonTier.primary,
                loading: _busy,
                onPressed: _changeEmail,
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildBusinessStep() {
    final identity = _requestIdentity();
    if (identity == null) {
      return const EmptyState(
        key: ValueKey('onboarding-business-unavailable'),
        title: 'Your session has ended',
        hint: 'Sign in again to set up your business.',
      );
    }
    return TenantRequestForm(
      key: const ValueKey('onboarding-business-step'),
      identity: identity,
      callable: widget.requestTenantCallable ?? FirebaseRequestTenantCallable(),
      requestIdFactory: widget.tenantRequestIdFactory,
      isCurrent: widget.isCurrent,
      clock: widget.clock,
      // Null: the frame above already carries the display heading, and a
      // `SectionHeading` under it would be the same page named twice.
      heading: null,
      // Both null: the frame's heading and subheading above already say this,
      // and the fact about the name is the name field's helper now.
      description: null,
      reviewLabel: 'Review',
      submitLabel: 'Create business',
      // See the account step's submit: every primary in this flow is the
      // capsule the sign-in screen uses.
      pillSubmit: true,
      onSuccess: _businessCreated,
    );
  }

  Widget _buildCompleteStep(AppTokens tokens) {
    final result = _result!;
    return Column(
      key: const ValueKey('onboarding-complete-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // **The same reason the verify step carries one.** Nothing is typed on
        // this step and nothing can be hurried, so the drawing does the work
        // the form does everywhere else in this flow - telling somebody at a
        // glance what the page is about. `approve.svg` is the asset the
        // platform's own review screens end on, which is this same fact read
        // from the other side of the desk.
        //
        // No `semanticLabel`: the heading above and the three details below
        // already state every fact here, and hard rule 4 forbids a picture
        // being the only carrier of one.
        Center(
          child: AppIllustration(
            key: const ValueKey('onboarding-complete-illustration'),
            asset: 'approve.svg',
            size: EmptyState.illustrationSize,
          ),
        ),
        SizedBox(height: tokens.spacing.s24),
        Text('${result.name} is ready.', style: tokens.typography.titleMedium),
        SizedBox(height: tokens.spacing.s16),
        _Detail(label: 'Trades as', value: result.slug),
        _Detail(label: 'Currency', value: result.currency),
        _Detail(
          label: 'Status',
          value:
              'Under review. You can sell until '
              '${_formatDate(result.provisionalUntil.toLocal())}.',
        ),
        SizedBox(height: tokens.spacing.s20),
        const Text('Add your first product and you can ring up a sale.'),
        SizedBox(height: tokens.spacing.s24),
        AppButton(
          key: const ValueKey('onboarding-open-business'),
          label: 'Open the till',
          pill: true,
          tier: AppButtonTier.primary,
          onPressed: widget.onOpenBusiness == null
              ? null
              : () => widget.onOpenBusiness!(result),
        ),
      ],
    );
  }
}

final class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.spacing.s8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Proportional rather than a fixed 96: hard rule 2 keeps numbers out
          // of widgets, and a label column that is a share of the row survives
          // a longer word without a value being invented for it.
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: tokens.typography.caption.copyWith(
                color: tokens.colors.text.tertiary,
              ),
            ),
          ),
          Expanded(flex: 5, child: Text(value)),
        ],
      ),
    );
  }
}

String _formatDate(DateTime value) {
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
  return '${value.day} ${months[value.month - 1]} ${value.year}';
}
