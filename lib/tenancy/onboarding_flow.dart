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
/// **Nobody presses anything to receive the first email, and nobody presses
/// anything to be believed about it either.** `completeSelfSignup` enqueues the
/// email as part of saving the name, and the verify step then watches for the
/// address turning verified - on every app resume, and on a timer for as long as
/// the step is alive - so returning from the mailbox advances the flow on its
/// own. An App Link on the continue URL means *returning* is usually automatic
/// too; `AndroidManifest.xml` has the filter and the reasoning.
///
/// *I have verified* was removed on 2026-09-11. It called the same reload the
/// watch calls, on the same guards, so it could do nothing the app was not
/// already doing five seconds later - while sitting as the mint button directly
/// under a sentence promising the person they need not press anything. The two
/// states that could have justified it were better answered than displayed: a
/// watch stalled by a route pushed over the flow is now simply not stalled (see
/// [_OnboardingFlowState._syncPolling]), and a reload that keeps failing raises
/// [onboardingUnreachableNotice] with a *Try again* that names the app's problem
/// rather than asking for the person's claim.
///
/// *Send again* and *Wrong address?* remain, as the two ways the wait can be
/// wrong.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uzapay_pos/observability/app_telemetry.dart';

import '../ui/buttons.dart';
import '../ui/fields.dart';
import '../ui/illustration.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'account_profile.dart';
import 'account_registration.dart';
import 'account_verification.dart';
import 'email_delivery_status.dart';
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

/// How many reloads must fail in a row before the wait admits it.
///
/// **Three, because one means nothing.** A single reload that could not reach
/// the server is the ordinary condition of a phone on mobile data, and the next
/// tick five seconds later usually answers. Three consecutive failures is about
/// fifteen seconds of a screen promising to move on by itself while it has no
/// way to find out whether it should - which is the point at which the promise
/// is worth qualifying.
const int onboardingRefreshFailuresBeforeNotice = 3;

/// What the verify step says when it cannot reach the server to check.
///
/// **`info` rather than `problem`.** Nothing has failed and nothing is lost: the
/// address may well be verified already, the watch is still running, and the
/// next tick may answer. §2.1's `info` is *"offline, read-only, informational"*,
/// and a device that cannot currently read is exactly that. `problem` would be
/// claiming a difference was found, and none was.
const AppNotice onboardingUnreachableNotice = AppNotice.offline(
  'We cannot check your address from here right now. We are still trying, and '
  'nothing you have done is lost.',
);

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
    this.emailDeliveryStatusCallable,
    this.requestTenantCallable,
    this.accountProfileRequestIdFactory,
    this.accountVerificationRequestIdFactory,
    this.tenantRequestIdFactory,
    this.isCurrent,
    this.clock,
    this.refreshSession,
    this.reauthenticate,
    this.identityChanges,
    this.resumeSession,
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

  /// Reads whether the address being waited on can receive mail at all.
  ///
  /// **Without it this step can only be optimistic.** The server accepts a
  /// verification request without promising delivery - a suppressed address is
  /// accepted and sends nothing - so *Another email has been requested* is the
  /// most the flow can honestly say on its own. This is what lets it say the
  /// useful thing instead. While it is absent the step makes no claim.
  final EmailDeliveryStatusCallable? emailDeliveryStatusCallable;

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

  /// Mints a newer ID token without ending the session.
  ///
  /// Cures the refusal raised by a token that predates *Wrong address?*, which
  /// the server now names separately. Absent leaves that refusal to be read
  /// out rather than fixed.
  final Future<void> Function()? refreshSession;

  /// Proves the signed-in person again, from their password, in place.
  ///
  /// **This is what replaces "sign out and sign in again".** The server wants a
  /// sign-in under five minutes old before it will send another verification
  /// email, and only a real re-authentication moves `auth_time` - refreshing
  /// the token does not. Re-authenticating does move it *and* keeps the
  /// session, so the wizard, the step and everything typed into it survive
  /// what used to be a round trip through the login screen. Absent falls back
  /// to telling the person to sign out, which is all a host without a password
  /// can offer.
  final Future<void> Function(String password)? reauthenticate;

  /// Ticks whenever the signed-in identity changes, including to nobody.
  ///
  /// **The flow could not see a session end underneath it.** [readIdentity] is
  /// read during build, and nothing rebuilt when the identity went away - so a
  /// session that ended mid-flow left the last step it had drawn on screen,
  /// live-looking and inert, describing an account that no longer existed.
  /// Changing the address is one way to reach that: the server rewrites the
  /// Auth email, which rebinds the password credential, and the refresh token
  /// dies with it.
  ///
  /// A tick rather than the identity itself, because [readIdentity] is already
  /// the source of truth and this file deliberately knows nothing about
  /// Firebase. Absent means the flow cannot observe a sign-out, which is how it
  /// behaved before this existed.
  final Stream<Object?>? identityChanges;

  /// Exchanges a server-minted credential for a live session, in place.
  ///
  /// **This is what keeps *Wrong address?* from signing anybody out.** The
  /// address change rebinds the password credential and kills the refresh token
  /// the device holds; a credential minted against the uid does not care, so
  /// exchanging one before the old session lapses means nothing is interrupted.
  /// Absent - or a server that could not mint one - leaves the session to end,
  /// which [_buildSessionEnded] then says plainly instead of hiding.
  final Future<void> Function(String token)? resumeSession;

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
  final _reauthController = TextEditingController();

  DialCode _dialCode = defaultDialCode;
  bool _busy = false;
  bool _changingEmail = false;
  AppNotice? _notice;

  /// The step [_notice] was raised on, so it cannot outlive it.
  ///
  /// **A notice is about a step, and the step can change underneath it.** The
  /// field was cleared only at the start of the next action, so *Another email
  /// has been requested* - true of the verify step - stayed on screen when
  /// verification landed and the flow moved to *Your business*, asserting
  /// something about a step the person had already left. Recording where it was
  /// raised is cheaper than finding every transition that can strand it.
  OnboardingStep? _noticeStep;

  /// The password is being asked for so another email can be sent.
  bool _reauthRequired = false;

  StreamSubscription<Object?>? _identitySubscription;

  /// The last identity this flow saw, so losing one can be told from never
  /// having had one. The pushed wizard legitimately starts with nobody.
  String? _seenUid;

  /// The session ended while this flow was on screen.
  bool _sessionEnded = false;

  /// The flow is signing out on purpose, so the loss is not a surprise.
  bool _leaving = false;

  /// Whether an address change was attempted and never answered.
  ///
  /// **The third outcome.** `_changeEmail` had two branches - it succeeded and
  /// recorded the address, or it was refused and recorded nothing - for three
  /// possible results. An unreachable server is the third: the change may have
  /// been applied and the reply lost, so neither the identity's cached copy nor
  /// [_changedEmail] can be trusted to name where the link went. Cleared by the
  /// next reload that reaches the server, which settles it either way.
  bool _addressOutcomeUnknown = false;

  /// The address this flow changed the account to, if it changed one.
  ///
  /// **Read in preference to the identity's own address.** The change is made
  /// server-side, so the client's cached user record still reports the old
  /// address until something reloads it - which is why the verify step went on
  /// naming an address the account had already stopped using. What the flow
  /// itself just saved it already knows, and knowing it does not depend on the
  /// session that the same change may have ended.
  String? _changedEmail;
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

  /// Whether a check somebody asked for is running right now.
  ///
  /// **Separate from `_busy`, and separate from the watch.** The same reload
  /// serves the silent five-second tick and the *Try again* somebody pressed;
  /// marking `_busy` would disable *Send again* and *Wrong address?* every time
  /// the watch fired, and marking nothing left the one control on a screen that
  /// has just admitted it is stuck doing nothing visible at all. This is the
  /// press, and only the press.
  bool _manualRefresh = false;

  /// Reloads that could not reach the server, since the last one that could.
  ///
  /// Counted rather than flagged because a single failure is not worth saying
  /// anything about; see [onboardingRefreshFailuresBeforeNotice]. It stops
  /// climbing at the threshold, so a long outage rebuilds this screen three
  /// times rather than once every tick.
  int _refreshFailures = 0;

  /// What the server last said about reaching this address, if it was asked.
  EmailDeliveryStatus? _deliveryStatus;

  /// The idempotency key each attempt on this screen is holding, if any.
  ///
  /// **One key per attempt, held across its retries.** Every callable behind
  /// this flow is idempotent by request ID, and a key minted per *call* is the
  /// one input that defeats that: the server cannot tell a repeat of an attempt
  /// whose answer went missing from a brand new one. For *Wrong address?* the
  /// consequence is the worst of the three - the retry is refused by the address
  /// the lost attempt already set, so the person is told the change failed and
  /// then told it is forbidden, while the link is already on its way.
  ///
  /// **Reused by comparing the input, not by clearing on edit.** See
  /// [_signupIntentFor] and [_addressIntentFor]. An accessor that checks what
  /// the key was minted for has no edit path to forget; a `didUpdateWidget` and
  /// a handful of `onChanged` resets have one for every field anybody adds
  /// later. The comparison is the same one `account_verification.dart` makes on
  /// the uid, widened to the values the server hashes.
  AccountSignupIntent? _signupIntent;
  AccountAddressChangeIntent? _emailChangeIntent;
  AccountVerificationIntent? _verificationIntent;

  /// The key for naming this account, minted once for these exact values.
  AccountSignupIntent _signupIntentFor(
    AccountProfileGateway gateway, {
    required String displayName,
    required String phone,
  }) {
    final existing = _signupIntent;
    if (existing != null &&
        existing.displayName == displayName.trim() &&
        existing.phone == phone) {
      return existing;
    }
    return _signupIntent = gateway.createSignupIntent(
      displayName: displayName,
      phone: phone,
    );
  }

  /// The key for moving to this address, minted once for this exact address.
  ///
  /// A different address is a different attempt: reusing the key would make the
  /// server answer `already-exists` for an input that no longer matches what it
  /// recorded, which is a refusal rather than the edit the person asked for.
  AccountAddressChangeIntent _addressIntentFor(
    AccountProfileGateway gateway,
    String email,
  ) {
    final existing = _emailChangeIntent;
    if (existing != null && existing.email == email.trim()) return existing;
    return _emailChangeIntent = gateway.createAddressChangeIntent(email);
  }

  /// The key for asking again, minted once per identity this flow is serving.
  ///
  /// Cleared when the address moves: the delivery id the server deduplicates on
  /// is derived from the address as well as the key, so a key minted for the old
  /// one no longer describes this request.
  AccountVerificationIntent _verificationIntentFor(
    AccountVerificationGateway gateway,
  ) => _verificationIntent ??= gateway.createIntent();

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
    _seenUid = identity.uid;
    _subscribeToIdentityChanges();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncPolling());
  }

  /// Watches for the identity going away under the flow.
  ///
  /// **Only a loss matters here, and only a loss it did not ask for.** An
  /// identity arriving is already covered - the step is derived on every build
  /// and the account step's own submit rebuilds it - so this exists for the one
  /// transition nothing else could see. A deliberate sign-out sets [_leaving]
  /// first, because a person who pressed *Sign out* does not need to be told
  /// their session ended.
  void _subscribeToIdentityChanges() {
    _identitySubscription = widget.identityChanges?.listen(
      (_) {
        if (!mounted) return;
        final uid = widget.readIdentity().uid;
        final lost = uid == null && _seenUid != null && !_leaving;
        // **A different account never inherits these keys.** They are recorded
        // against the uid that minted them, so a retry under somebody else's
        // identity would address the previous person's operation. The accessors
        // compare the input; only this can see the identity move underneath
        // them. `account_verification.dart` makes the same guard for the same
        // reason.
        final changedIdentity =
            uid != null && _seenUid != null && uid != _seenUid;
        if (changedIdentity) {
          _signupIntent = null;
          _emailChangeIntent = null;
          _verificationIntent = null;
        }
        setState(() {
          if (uid != null) {
            _seenUid = uid;
            _sessionEnded = false;
          } else if (lost) {
            _sessionEnded = true;
            _poll?.cancel();
            _poll = null;
            _busy = false;
            _reauthRequired = false;
            _reauthController.clear();
            _clearNotice();
          }
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        AppTelemetry.captureHandled(
          error,
          stackTrace,
          boundary: 'auth.identity_stream',
        );
      },
    );
  }

  @override
  void didUpdateWidget(covariant OnboardingFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.identityChanges, widget.identityChanges)) {
      _identitySubscription?.cancel();
      _subscribeToIdentityChanges();
    }
  }

  /// Leaves for the sign-in screen, without reporting a surprise on the way.
  Future<void> _leave() async {
    setState(() => _leaving = true);
    await widget.onSignOut();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _identitySubscription?.cancel();
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _newEmailController.dispose();
    _reauthController.dispose();
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
  ///
  /// **A route pushed over the flow pauses the watch; it does not stop it.**
  /// This used to cancel on `!_isCurrent()` as well, and nothing re-armed it:
  /// [_refreshIdentity] returns early on the same condition, so a dialog opened
  /// and dismissed over the verify step left the flow with no watch at all, for
  /// the rest of its life, until the app happened to be backgrounded and
  /// resumed. The tick itself is what skips the work while something covers this
  /// screen - a timer that fires into an early return costs nothing, and it is
  /// always armed when the cover goes away.
  void _syncPolling() {
    _poll?.cancel();
    _poll = null;
    if (!mounted || _step != OnboardingStep.verify) {
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

  /// Asks the server whether the address has been verified yet.
  ///
  /// [asked] marks the call a person made rather than one the watch made, which
  /// is the whole of the difference between the two: a tick that fails says
  /// nothing and shows nothing, and a press that fails has to answer the person
  /// who made it.
  Future<void> _refreshIdentity({bool asked = false}) async {
    if (!mounted || !_isCurrent()) return;
    if (_step != OnboardingStep.verify) return;
    if (asked) {
      if (_manualRefresh) return;
      setState(() => _manualRefresh = true);
    }
    try {
      await widget.reloadIdentity();
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'auth.identity_reload',
      );
      // A refresh that could not reach the server says nothing about whether
      // the address is verified, so it changes nothing and is not an error the
      // person needs to read. The next tick asks again.
      //
      // **Counted, though, because enough of them do need reading.** Silence is
      // right for the ordinary dropped request and wrong for a screen that has
      // been unable to check for a quarter of a minute while telling somebody it
      // will move on by itself. See [onboardingRefreshFailuresBeforeNotice].
      //
      // **A press is answered even when the count has nothing left to say.**
      // The counter stops at the threshold, and the counter is what redraws
      // this screen - so once the notice was up, pressing *Try again* changed
      // no number, rebuilt nothing, and looked exactly like a dead control. The
      // pending state below is what the press has to show for itself; clearing
      // it here is the frame that says the attempt is over and failed.
      if (mounted) {
        setState(() {
          if (_refreshFailures < onboardingRefreshFailuresBeforeNotice) {
            _refreshFailures++;
          }
          _manualRefresh = false;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _manualRefresh = false;
      _refreshFailures = 0;
      // **A reload that reached the server outranks what this flow remembers.**
      // [_changedEmail] stands in for an identity whose cached copy a
      // server-side change does not touch - but it was written once, on a
      // success, and never cleared. So a *later* change whose answer went
      // missing left the earlier address shadowing an identity that had since
      // been reloaded with the right one, for the life of this widget, on the
      // one screen whose whole job is naming the address being waited on.
      //
      // Dropping it whenever the server disagrees keeps the stand-in for the
      // case it exists for - a change this flow just made, before any reload
      // has caught up - and lets the authority win everywhere else.
      final refreshed = widget.readIdentity().email;
      if (refreshed != null &&
          _changedEmail != null &&
          refreshed != _changedEmail) {
        _changedEmail = null;
        // Minted against an address the account no longer holds.
        _verificationIntent = null;
      }
      // The server was reached, so whatever it now reports is the answer the
      // unanswered attempt never gave.
      _addressOutcomeUnknown = false;
    });
    _syncPolling();
  }

  /// Asks whether the address this step is waiting on can receive mail.
  ///
  /// **Read after a send, never instead of one.** The suppression that matters
  /// is written by the delivery task moments after the callable returns, so the
  /// answer worth having is the one read on the *next* attempt - which is
  /// exactly when somebody who received nothing presses *Send again*.
  ///
  /// A failure here is deliberately silent. The send itself succeeded, and a
  /// diagnostic about it that could not be read is not something the person can
  /// act on. [parseEmailDeliveryStatus] refuses an unrecognised answer rather
  /// than reading it as working, so a server whose wording moves makes this step
  /// say nothing rather than something false.
  Future<void> _readDeliveryStatus(String sentUid) async {
    final callable = widget.emailDeliveryStatusCallable;
    if (callable == null) return;
    final EmailDeliveryStatus status;
    try {
      status = await EmailDeliveryStatusReader(callable: callable).read();
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'auth.email_delivery_status_read',
      );
      return;
    }
    // The answer is about the address the send was made from. An identity that
    // changed underneath it - signed out, or swapped - must not inherit it.
    if (!mounted || widget.readIdentity().uid != sentUid) return;
    setState(() => _deliveryStatus = status);
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
  /// What the account step was when the person pressed the button.
  ///
  /// Null except while a submission is in flight. See `_creatingAccount`.
  bool? _submittingNewAccount;

  /// Whether the account step is creating an account rather than finishing one.
  ///
  /// **Prefers the submission's own snapshot over the live identity.** Signing
  /// up is two calls: the Auth account is created, and only then are the name
  /// and phone saved. In the window between them the account exists with
  /// neither, and reading the identity live there flips this to false - which
  /// retitles the screen *Almost there / Finish the account you already
  /// started* and drops the email and password fields, two seconds after the
  /// person pressed **Create account** and while that very submission is still
  /// running. The wording is right for somebody who abandoned signup and came
  /// back; it is a lie mid-flight. `_submitAccount` already snapshots this for
  /// its own use, so the screen now reads the same snapshot it does.
  bool get _creatingAccount =>
      _submittingNewAccount ?? (widget.readIdentity().uid == null);

  Future<void> _submitAccount() async {
    if (_busy || !_isCurrent()) return;
    final identity = widget.readIdentity();
    final creating = identity.uid == null;
    final telemetry = AppTelemetry.current;
    final operation = telemetry.start(
      'auth.signup',
      screen: 'onboarding',
      context: {
        'attempted_email': _emailController.text.trim(),
        'user_id': identity.uid,
      },
    );

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
      AppTelemetry.captureHandled(
        ArgumentError('registration_input'),
        StackTrace.current,
        operation: operation,
        code: 'validation_registration_input',
      );
      setState(() {
        _nameError = nameDefect == null
            ? null
            : accountProfileInputDefectMessage(nameDefect);
        _phoneError = phoneDefect;
        if (credentialDefect == null) {
          _clearNotice();
        } else {
          _raise(
            AppNotice.refused(registrationInputDefectMessage(credentialDefect)),
          );
        }
      });
      return;
    }

    setState(() {
      _busy = true;
      // **Held for as long as the submission runs.** Creating the account and
      // saving the name and phone are two calls, and between them the account
      // exists with neither - a state the copy below would otherwise read as
      // "you abandoned this and came back". Snapshotting here is what keeps
      // the screen saying what it said when the button was pressed.
      _submittingNewAccount = creating;
      _clearNotice();
      _nameError = null;
      _phoneError = null;
    });
    try {
      telemetry.recordStep(operation, 'validated');
      if (creating) {
        final registration =
            widget.registration ?? FirebaseEmailPasswordRegistration();
        await telemetry.trace(
          operation,
          'create_identity',
          () => registration.call(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          ),
        );
        telemetry.recordStep(operation, 'submitted');
      }
      final phone = normalizeE164(
        dialCode: _dialCode,
        localNumber: _phoneController.text,
      );
      final gateway = _profileGateway;
      await telemetry.trace(
        operation,
        'save_profile',
        () => gateway.completeSignup(
          _signupIntentFor(
            gateway,
            displayName: _nameController.text,
            phone: phone,
          ),
        ),
      );
      telemetry.recordStep(operation, 'confirmed_on_server');
      if (!mounted) return;
      setState(() {
        _savedDisplayName = _nameController.text.trim();
        _savedPhone = phone;
        _passwordController.clear();
        _confirmController.clear();
        _busy = false;
        _submittingNewAccount = null;
        // The attempt is over, so the key that carried it is spent. A later
        // edit to the name is a new attempt and mints its own.
        _signupIntent = null;
      });
      _syncPolling();
      // Nobody pressed anything to send the first message, so this is the only
      // place it can be asked about.
      final sentUid = widget.readIdentity().uid;
      if (sentUid != null) unawaited(_readDeliveryStatus(sentUid));
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        operation: operation,
        boundary: 'auth.signup',
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _submittingNewAccount = null;
        _raise(_noticeFor(error));
      });
    }
  }

  /// Raises a notice and remembers the step it belongs to.
  ///
  /// A plain mutator rather than a `setState` of its own: every caller is
  /// already inside one, and nesting them would rebuild twice.
  void _raise(AppNotice notice) {
    _notice = notice;
    _noticeStep = _step;
  }

  void _clearNotice() {
    _notice = null;
    _noticeStep = null;
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
    if (_busy || !_isCurrent()) return;
    final telemetry = AppTelemetry.current;
    final operation = telemetry.start(
      'auth.verification_resend',
      screen: 'onboarding',
      context: {'user_id': uid},
    );
    // **Says so rather than doing nothing.** This guard used to return in
    // silence, so a session that had ended left *Send again* rendering as an
    // enabled button that swallowed every press without a word. The flow now
    // notices the loss and draws [_buildSessionEnded] instead, which is why
    // this is a backstop; a backstop that says nothing is how the original
    // defect hid for so long.
    if (uid == null) {
      AppTelemetry.captureHandled(
        StateError('session_ended'),
        StackTrace.current,
        operation: operation,
        code: 'session_ended',
      );
      setState(() {
        _sessionEnded = true;
        _clearNotice();
      });
      return;
    }
    setState(() {
      _busy = true;
      _clearNotice();
    });
    try {
      telemetry.recordStep(operation, 'submitted');
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
        // Cures a token left behind by *Wrong address?* without anybody being
        // told about it. See `AccountVerificationGateway`.
        refreshSession: widget.refreshSession,
      );
      await telemetry.trace(
        operation,
        'send_verification',
        () => gateway.send(_verificationIntentFor(gateway)),
      );
      telemetry.recordStep(operation, 'confirmed_on_server');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _reauthRequired = false;
        _reauthController.clear();
        // Asked and answered. The next *Send again* is a new request.
        _verificationIntent = null;
        // Deliberately not "sent": the server accepts responsibility for a
        // request, which is not the same as a message arriving. See
        // `AccountVerificationResult`.
        _raise(const AppNotice.confirmed('Another email has been requested.'));
      });
      unawaited(_readDeliveryStatus(uid));
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        operation: operation,
        boundary: 'auth.verification_resend',
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        // **A stale sign-in asks for a password, not a sign-out.** The server
        // wants an `auth_time` under five minutes old and only a real
        // re-authentication moves one; doing it in place keeps the session,
        // and with it this wizard and the step it is on.
        if (accountVerificationRefusalOf(error) ==
                AccountVerificationRefusal.staleSignIn &&
            widget.reauthenticate != null) {
          _reauthRequired = true;
          _reauthController.clear();
          _raise(
            const AppNotice.refused(
              'For your security, confirm your password to send another '
              'email.',
            ),
          );
          return;
        }
        _raise(AppNotice.refused(accountVerificationSafeError(error)));
      });
    }
  }

  /// Proves the person again from their password, then sends the email.
  ///
  /// **The password is never held.** It is read out of the field, handed
  /// straight to the host's re-authentication and the field is cleared; what
  /// survives is a newer `auth_time`, which is the only thing the server asked
  /// for. A refusal here is the password being wrong, so it is said plainly
  /// and the field stays open for another go.
  Future<void> _confirmReauthentication() async {
    final reauthenticate = widget.reauthenticate;
    final password = _reauthController.text;
    if (_busy || reauthenticate == null || !_isCurrent()) return;
    if (password.isEmpty) {
      setState(() => _raise(const AppNotice.refused('Enter your password.')));
      return;
    }
    setState(() {
      _busy = true;
      _clearNotice();
    });
    try {
      await reauthenticate(password);
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'auth.reauthenticate',
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _raise(
          const AppNotice.refused('That password was not accepted. Try again.'),
        );
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _reauthController.clear();
    });
    await _resend();
  }

  Future<void> _changeEmail() async {
    if (_busy || !_isCurrent()) return;
    final telemetry = AppTelemetry.current;
    final operation = telemetry.start(
      'auth.change_email',
      screen: 'onboarding',
      context: {'attempted_email': _newEmailController.text.trim()},
    );
    setState(() {
      _busy = true;
      _clearNotice();
    });
    try {
      telemetry.recordStep(operation, 'submitted');
      final gateway = _profileGateway;
      final change = await telemetry.trace(
        operation,
        'change_address',
        () => gateway.changeEmail(
          _addressIntentFor(gateway, _newEmailController.text),
        ),
      );
      telemetry.recordStep(operation, 'confirmed_on_server');
      final email = change.email;
      // **Before the frame that reports success.** The old refresh token is
      // already doomed at this point and the SDK will notice within seconds;
      // exchanging first means the session never visibly lapses. A failure here
      // is deliberately swallowed - the address did move, and the loss it
      // leaves behind is exactly what the session-ended state is for.
      final resume = widget.resumeSession;
      final token = change.sessionToken;
      if (resume != null && token != null) {
        try {
          await resume(token);
        } catch (error, stackTrace) {
          AppTelemetry.captureHandled(
            error,
            stackTrace,
            operation: operation,
            boundary: 'auth.resume_after_email_change',
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _changingEmail = false;
        _emailController.text = email;
        _changedEmail = email;
        // The server answered, so there is nothing left to be unsure about -
        // including an earlier attempt of this same change that went unanswered.
        _addressOutcomeUnknown = false;
        _newEmailController.clear();
        // The attempt landed, so its key is spent - and so is the resend key,
        // which was minted for an address this account no longer holds.
        _emailChangeIntent = null;
        _verificationIntent = null;
        // The address moved, so a sign-in old enough to need confirming is no
        // longer what is standing between this person and their mail.
        _reauthRequired = false;
        _reauthController.clear();
        _raise(
          const AppNotice.confirmed(
            'Your address has been changed. A new link is on its way to it.',
          ),
        );
        // Deliverability was a fact about the address that just went away.
        _deliveryStatus = null;
      });
      // The address moved, so the wait restarts and the eager cadence with it.
      _verifyingSince = null;
      _syncPolling();
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        operation: operation,
        boundary: 'auth.change_email',
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        // **Only when the server was not reached.** A refusal is an answer: the
        // address did not move and the one on screen is still right. An
        // unreachable server is not, and the change may have been applied on the
        // far side of it. `SignInFailureKind.unreachable` is exactly the
        // "nothing was attempted, or we cannot tell" case - see
        // `accountProfileFailure`.
        final notice = _noticeFor(error);
        if (accountProfileFailure(error).kind ==
            SignInFailureKind.unreachable) {
          _addressOutcomeUnknown = true;
        }
        _raise(notice);
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
      _clearNotice();
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
                      _sessionEnded ? 'Your session has ended' : _heading(step),
                      key: const ValueKey('onboarding-heading'),
                      textAlign:
                          step == OnboardingStep.verify ||
                              step == OnboardingStep.complete
                          ? TextAlign.center
                          : TextAlign.start,
                      style: tokens.typography.display.copyWith(
                        color: tokens.colors.text.primary,
                      ),
                    ),
                  ),
                  SizedBox(height: tokens.spacing.s8),
                  Builder(
                    builder: (BuildContext context) {
                      final subheading = _sessionEnded
                          ? _endedSubheading()
                          : _subheading(step);
                      return Text(
                        subheading,
                        key: const ValueKey('onboarding-subheading'),
                        textAlign:
                            step == OnboardingStep.verify ||
                                step == OnboardingStep.complete
                            ? TextAlign.center
                            : TextAlign.start,
                        // **The zero-width space is for the line breaker, not
                        // for a listener.** [_breakableVerifyingAddress] puts
                        // one inside the address so the sentence can wrap.
                        // Screen readers mostly ignore it - and "mostly" is not
                        // a thing to leave inside an address somebody is being
                        // asked to check against their mailbox, so what is
                        // spoken is the unbroken sentence.
                        semanticsLabel: subheading.replaceAll('\u200b', ''),
                        style: tokens.typography.bodyLarge.copyWith(
                          color: tokens.colors.text.secondary,
                        ),
                      );
                    },
                  ),
                  SizedBox(height: tokens.spacing.s40),
                  // **Only while the step it was raised on is still the step.**
                  // See [_noticeStep].
                  if (!_sessionEnded &&
                      _notice != null &&
                      _noticeStep == step) ...<Widget>[
                    Callout(
                      key: const ValueKey('onboarding-notice'),
                      status: _notice!.status,
                      message: _notice!.message,
                    ),
                    SizedBox(height: tokens.spacing.s16),
                  ],
                  // **A step is only worth drawing for an identity that still
                  // exists.** Without this the flow kept the last step it had
                  // drawn - enabled controls, a live-looking wait on an email -
                  // for an account the session no longer reached. The step
                  // derivation would have shown the *account* step instead,
                  // asking somebody who already has an account to create one,
                  // which is a different wrong answer rather than a right one.
                  if (_sessionEnded)
                    _buildSessionEnded(tokens)
                  else
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
                  if (!_sessionEnded &&
                      step != OnboardingStep.complete &&
                      widget.readIdentity().uid != null) ...<Widget>[
                    SizedBox(height: tokens.spacing.s24),
                    Center(
                      child: AppButton(
                        key: const ValueKey('onboarding-sign-out'),
                        label: 'Sign out',
                        tier: AppButtonTier.tertiary,
                        onPressed: _busy ? null : _leave,
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

  /// The address the verify step is waiting on.
  ///
  /// [_changedEmail] first: the account's address is whatever this flow last
  /// set it to, and the identity's copy is read from a cached user record that
  /// a server-side change does not touch. Falls back to the identity for the
  /// ordinary case where nothing has been changed.
  String? get _verifyingAddress => _changedEmail ?? widget.readIdentity().email;

  /// The address the verify subheading prints, with somewhere legal to break.
  ///
  /// **An address is one unbreakable token, so it orphans the line above it.**
  /// Unicode's line breaker breaks at spaces, and an email address contains
  /// none - `@` is not a break opportunity and neither is a `.` with a letter
  /// behind it. So an address that does not fit in what is left of the current
  /// line cannot be split across the boundary; it moves down whole, and the
  /// words before it are left stranded on a line of their own. Measured on a
  /// 360dp handset the sentence misses by about one character, which is why it
  /// reads as though it should have fitted.
  ///
  /// A zero-width space gives the breaker a legal break without putting a
  /// character on the screen.
  ///
  /// **At the `@` and at the dots, which is every break an address offers.**
  /// The `@` alone was tried first, on the reasoning that a trailing `@` reads
  /// as *continues below* while a line opening `com.` reads as the tail of a
  /// sentence. It moved the problem rather than solving it: the break left
  /// `swahilipro.com.` as the next unbreakable run, still too wide for what was
  /// left of the line by about ten pixels, so the line kept a gap of roughly
  /// 210px instead of 380px.
  ///
  /// The product owner's call on 2026-09-12, having seen both on a device: a
  /// hole inside a line of prose is worse than a split inside an address. The
  /// breaker takes the last opportunity that fits, so the dots are what close
  /// the gap.
  ///
  /// The subheading's `semanticsLabel` strips the space again, so a screen
  /// reader still hears the unbroken address; nothing here is load-bearing
  /// beyond the line break.
  String get _breakableVerifyingAddress {
    final address = _verifyingAddress;
    if (address == null) return 'your address';
    return address.replaceAll('@', '@\u200b').replaceAll('.', '.\u200b');
  }

  /// The step's name, in the role `login_screen.dart` gives *Welcome back*.
  String _heading(OnboardingStep step) => switch (step) {
    OnboardingStep.account =>
      _creatingAccount ? 'Create your account' : 'Almost there',
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
      _creatingAccount
          ? 'Two more steps and your register is open.'
          : 'Finish the account you already started.',
    // **Names the address only when it can.** An attempt whose answer never
    // arrived leaves this flow unable to say where the link went: the change
    // may have landed, and both the identity's cached copy and this flow's own
    // note would still read the address it moved away from. Naming one then is
    // not a hedge, it is a false statement - and pointing somebody at a mailbox
    // that has nothing in it is the one outcome this screen must not cause.
    //
    // The generic sentence lasts until a reload settles it, which is seconds
    // once the connection is back, and it is followed by
    // [onboardingUnreachableNotice] saying why in the meantime.
    OnboardingStep.verify =>
      _addressOutcomeUnknown
          ? 'We sent a link to your address. Open it to continue.'
          : 'We sent a link to $_breakableVerifyingAddress. '
                'Open it to continue.',
    OnboardingStep.business =>
      'The last step. You can trade straight away while it is reviewed.',
    OnboardingStep.complete => 'Ready for your first sale.',
  };

  /// One sentence for a session that ended without being asked to.
  ///
  /// Names the address when the flow changed one, because that is both the
  /// likely reason the session ended and the thing the person now has to sign
  /// in with - and the old address would send them in circles.
  String _endedSubheading() {
    final changed = _changedEmail;
    if (changed != null) {
      return 'Your address is now $changed. Sign in with it to carry on where '
          'you left off.';
    }
    return 'Sign in again to carry on where you left off. Nothing you have '
        'finished is lost.';
  }

  /// What to draw when the identity went away under the flow.
  ///
  /// **Nothing is lost and the copy says so, because nothing is.**
  /// [deriveOnboardingStep] reads the account rather than a stored cursor, so
  /// signing in again lands on exactly this step. The one action offered is the
  /// way to the sign-in screen; the pushed host pops to reveal it, the shell
  /// host routes to it.
  Widget _buildSessionEnded(AppTokens tokens) => Column(
    key: const ValueKey('onboarding-session-ended'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      AppButton(
        key: const ValueKey('onboarding-session-ended-sign-in'),
        label: 'Sign in again',
        tier: AppButtonTier.primary,
        loading: _busy,
        onPressed: _busy ? null : _leave,
      ),
    ],
  );

  Widget _buildAccountStep(AppTokens tokens) {
    final creating = _creatingAccount;
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
        // Above the buttons and not below them: it exists to be read *before*
        // *Send again* is pressed, by somebody who has already pressed it once.
        if (_deliveryStatus == EmailDeliveryStatus.unavailable) ...<Widget>[
          Callout(
            key: const ValueKey('onboarding-verify-undeliverable'),
            status: emailUndeliverableNotice.status,
            message: emailUndeliverableNotice.message,
          ),
          SizedBox(height: tokens.spacing.s16),
        ],
        // **Above *Send again*, because it is what *Send again* now needs.**
        // Shown only after the server has actually refused for recency, so the
        // ordinary path never sees a password field at all.
        if (_reauthRequired) ...<Widget>[
          AppTextField(
            key: const ValueKey('onboarding-verify-reauth-password'),
            controller: _reauthController,
            enabled: !_busy,
            label: 'Your password',
            helper: 'Confirms it is you, without signing you out.',
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
          ),
          SizedBox(height: tokens.spacing.s12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              AppButton(
                key: const ValueKey('onboarding-verify-reauth-cancel'),
                label: 'Cancel',
                tier: AppButtonTier.tertiary,
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _reauthRequired = false;
                        _reauthController.clear();
                        _clearNotice();
                      }),
              ),
              SizedBox(width: tokens.spacing.s8),
              AppButton(
                key: const ValueKey('onboarding-verify-reauth-submit'),
                label: 'Confirm and send',
                tier: AppButtonTier.primary,
                loading: _busy,
                onPressed: _busy ? null : _confirmReauthentication,
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.s16),
        ],
        // **Above the buttons, for the reason the undeliverable notice is.** It
        // exists to be read *before* anything is pressed, by somebody who has
        // been watching a screen that promised to move on by itself while it
        // silently could not find out whether it should.
        if (_refreshFailures >=
            onboardingRefreshFailuresBeforeNotice) ...<Widget>[
          Callout(
            key: const ValueKey('onboarding-verify-unreachable'),
            status: onboardingUnreachableNotice.status,
            message: onboardingUnreachableNotice.message,
          ),
          SizedBox(height: tokens.spacing.s12),
          // **The only manual check this screen has, and it is only here.**
          // *I have verified* used to sit where *Send again* is now, always
          // visible and always doing exactly what the watch does on its own -
          // asking somebody to assert something the app can read for itself, in
          // a mint button directly under a sentence promising them they need
          // not. This is the one state where pressing something is worth
          // offering: a reload has failed three times running, and a person who
          // has just reconnected should not have to wait out another tick.
          //
          // It names the app's problem rather than asking for the person's
          // claim, which is also why it can be honest when it fails again.
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: AppButton(
              key: const ValueKey('onboarding-verify-retry'),
              label: 'Try again',
              tier: AppButtonTier.tertiary,
              loading: _manualRefresh,
              onPressed: _busy || _manualRefresh
                  ? null
                  : () => _refreshIdentity(asked: true),
            ),
          ),
          // s24 below against s12 above, so the retry reads as belonging to the
          // sentence that explains it rather than floating equidistant between
          // that and the row underneath, which is what s16 both sides gave it.
          SizedBox(height: tokens.spacing.s24),
        ],
        // **One row, and nothing in it is primary.** What this step expects is
        // that nobody touches it: the address turns verified in a mailbox, the
        // watch notices, and the flow moves on - which is what the subheading
        // says in as many words. A mint button would be the screen contradicting
        // its own sentence, and §2.1's "exactly one per screen region" is
        // satisfied by none as readily as by one.
        //
        // Both are the same tier and the same width because they are the same
        // kind of thing: two ways the wait can be wrong, neither more expected
        // than the other. *Wrong address?* was a tertiary word hugging the left
        // margin under a stretched row, which put three alignments in a column
        // of four controls.
        Row(
          children: <Widget>[
            Expanded(
              child: AppButton(
                key: const ValueKey('onboarding-verify-resend'),
                label: 'Send again',
                tier: AppButtonTier.secondary,
                // Both fill their half. [AppButton.expand]'s doc describes a
                // button alone on its row, and the reason generalises: the width
                // is worth taking when something else has already decided it.
                // Left to size themselves the two sit at unequal widths inside
                // equal halves, which reads as a measuring error rather than a
                // pair.
                expand: true,
                onPressed: _busy ? null : _resend,
              ),
            ),
            if (!_changingEmail) ...<Widget>[
              SizedBox(width: tokens.spacing.s8),
              Expanded(
                child: AppButton(
                  key: const ValueKey('onboarding-verify-change-email'),
                  label: 'Wrong address?',
                  tier: AppButtonTier.secondary,
                  expand: true,
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _changingEmail = true;
                          _newEmailController.text = '';
                          _clearNotice();
                        }),
                ),
              ),
            ],
          ],
        ),
        if (_changingEmail) ...<Widget>[
          SizedBox(height: tokens.spacing.s16),
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
        illustration: 'session-ended.svg',
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
      // Null: the frame above already carries the display heading, and a
      // `SectionHeading` under it would be the same page named twice.
      heading: null,
      // Both null: the frame's heading and subheading above already say this,
      // and the fact about the name is the name field's helper now.
      description: null,
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
        Text(
          '${result.name} is ready.',
          textAlign: TextAlign.center,
          style: tokens.typography.titleMedium,
        ),
        SizedBox(height: tokens.spacing.s16),
        _Detail(label: 'Currency', value: result.currency),
        const _Detail(label: 'Status', value: 'Open for business.'),
        SizedBox(height: tokens.spacing.s20),
        const Text(
          'Add a product to start selling.',
          textAlign: TextAlign.center,
        ),
        SizedBox(height: tokens.spacing.s24),
        AppButton(
          key: const ValueKey('onboarding-open-business'),
          // **Named for where it goes.** `TenantSafeLandingScreen` is the
          // business home - the catalog, the shift, the day's takings - not the
          // till. The line above this one says to add a product before a sale
          // can be rung up, so a button promising the till contradicted the
          // sentence directly above it as well as the route below it.
          label: 'Open your business',
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
