/// The sign-in screen.
///
/// **Reverted to the pre-multitenancy app's look and flow on 2026-08-25** — see
/// the plan at `C:\Users\BonifaceMasota\.claude\plans\look-at-the-old-expressive-sutton.md`.
/// Existing customers know the old two-pane, pill-and-glass front door; this
/// screen recreates it, styled entirely from [AppTokens] rather than the old
/// screen's hardcoded colors, so the shape is old but nothing here is a literal.
/// The sign-in boundary itself ([_submit], the notice model, the keyboard
/// wiring) is unchanged from the prior Stitch-era version of this file — only
/// the widget tree changed.
///
/// **The keypad's boundary is still measured rather than declared.** §9 makes a
/// key 48 wide, ten of them plus their gaps, the pane's own inset need
/// [PosKeyboard.minimumWidth], and the two panes share the window — so "is
/// there room" is arithmetic this screen can do rather than a band it looks up.
/// See [showsKeypad].
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'keyboard_controller.dart';
import 'keyboard_scope.dart';
import 'tenancy/password_reset.dart';
import 'tenancy/sign_in.dart';
import 'ui/buttons.dart';
import 'ui/press.dart';
import 'ui/status.dart';
import 'ui/tokens.dart';
import 'widgets/pos_keyboard.dart';

/// Which of the three things this screen is doing.
///
/// **One screen rather than three routes.** All three are the same two or three
/// fields in the same pane in front of the same keypad, and the person moving
/// between them has typed an address they should not have to type again. A push
/// would also put a back arrow on the app's front door, which is the one place
/// there is nothing behind.
enum LoginMode {
  signIn,

  /// Asking for a password-reset email.
  resetPassword,
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.signIn,
    this.createAccountRoute,
    this.passwordReset,
  });

  /// The boundary this screen signs in through.
  ///
  /// Absent, it is a [FirebaseEmailPasswordSignIn] built on first submission, so
  /// a build that never submits never reaches `FirebaseAuth.instance`.
  final EmailPasswordSignIn? signIn;

  /// The boundary this screen creates accounts through.
  /// Builds the route *Create an account* opens.
  ///
  /// **Signing up left this screen on 2026-09-02.** It used to be a third mode
  /// here, taking an email and a password and nothing else - no name, no phone -
  /// and then deliberately not navigating, which left the person on the business
  /// selector with the rest of signing up scattered across it. `OnboardingFlow`
  /// is that flow now, and it is a route rather than a mode because it has three
  /// steps and a mailbox in the middle of it.
  ///
  /// Null hides the link: a host with nowhere to send somebody must not offer to
  /// send them there.
  final WidgetBuilder? createAccountRoute;

  /// The boundary this screen asks for reset emails through.
  final RequestPasswordResetCallable? passwordReset;

  /// Whether the keypad is drawn beside the form at [screenWidth].
  ///
  /// **The two panes share the window equally, so the question is whether half
  /// of it can hold a row of keys a finger can hit.** That is a measurement
  /// [PosKeyboard.minimumWidth] takes out of §9's tap target and §2.3's scale,
  /// not a breakpoint: §4.1's bands describe how much room a *page* has and say
  /// nothing about how much room a keyboard needs, and this screen asked §4.1
  /// the wrong question for as long as it read `width < 768`.
  ///
  /// **What that cost, computed rather than estimated.** The old layout gave the
  /// keypad four ninths of the window, then spent 48 on the card's margin and 48
  /// more on its padding. At §4.1's `medium` floor that is
  /// `768 × 4/9 - 96 = 245` for ten keys — **24 pixels of slot each and 13
  /// painted**, against §9's 48 — and at the top of the band, 1023, it is still
  /// only 36 and 24. The keypad had been rendering that way since the screen was
  /// written.
  ///
  /// It resolves to **1264** at the comfortable density §3 gives this screen by
  /// name. Exposed so a test can ask the same question the screen asks rather
  /// than asserting a pixel width and hoping the two agree — the argument
  /// `PageHeader.showsDisplayTitle` already makes.
  static bool showsKeypad(double screenWidth, AppTokens tokens) =>
      screenWidth / 2 >= PosKeyboard.minimumWidth(tokens);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final KeyboardController keyboard = KeyboardController();

  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  final emailFocus = FocusNode();
  final passwordFocus = FocusNode();

  late final EmailPasswordSignIn _signIn =
      widget.signIn ?? FirebaseEmailPasswordSignIn();

  late final PasswordResetGateway _passwordReset = PasswordResetGateway(
    callable: widget.passwordReset ?? FirebaseRequestPasswordResetCallable(),
  );

  /// Which of the two things this screen is doing. See [LoginMode].
  LoginMode _mode = LoginMode.signIn;

  /// Whether a reset request has been accepted.
  ///
  /// A state rather than a notice, because it is the end of this screen's part
  /// in the flow: the form is replaced by the sentence, so there is nothing
  /// left to submit twice.
  bool _resetAccepted = false;

  /// What the identity provider answered, if it answered.
  ///
  /// **An [AppNotice] rather than a `String?`, which is the model the seven
  /// back-office surfaces took on 2026-08-15 and this one did not.** The kind of
  /// answer is not in the sentence: *this device could not reach the server* and
  /// *that password is wrong* were the same red paragraph in the same position,
  /// on the one screen where the first one is not the person's fault.
  AppNotice? _notice;

  /// What this screen itself refused, if anything.
  ///
  /// **Separate from [_notice] because it belongs to a field rather than to the
  /// page.** §5.2 gives a field an error line that replaces its helper, and §9
  /// asks that a form error be programmatically associated with the input it is
  /// about. "Enter the password for this account." is about one box; "That email
  /// address and password do not match an account." is about the credential, and
  /// the credential is not a box.
  SignInInputDefect? _defect;

  bool isLoading = false; // For button loading state

  bool rememberMe = true; // Remember Me checkbox state

  /// Whether the password is hidden. Was `PillInput`'s; the reveal toggle is
  /// this screen's now, in [AppTextField.trailing]'s slot.
  bool _passwordHidden = true;

  /// Whether the keypad is on screen, resolved in `build` and held.
  ///
  /// **Held rather than read where it is needed**, because the reader is a focus
  /// callback: a pointer or a focus change still in flight when the tree above
  /// it goes away delivers to a deactivated element, and an inherited-widget
  /// lookup there throws. Read in `build`, which is also where the dependency is
  /// registered properly.
  bool _keypadShown = false;

  /// The text this state has already seen, so a notification that changed no
  /// text can be told apart from one that did. See [_handleInputChanged].
  String _seenEmail = '';
  String _seenPassword = '';

  @override
  void initState() {
    super.initState();
    emailController.addListener(_handleInputChanged);
    passwordController.addListener(_handleInputChanged);
    // The keypad follows the focus. `PillInput` did this from inside itself;
    // `AppTextField` knows nothing about an on-screen keyboard and should not,
    // so the two listeners that did it move up here with the controller.
    emailFocus.addListener(_handleEmailFocus);
    passwordFocus.addListener(_handlePasswordFocus);
    // Focus email field by default
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      emailFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    emailController.removeListener(_handleInputChanged);
    passwordController.removeListener(_handleInputChanged);
    emailFocus.removeListener(_handleEmailFocus);
    passwordFocus.removeListener(_handlePasswordFocus);
    emailController.dispose();
    passwordController.dispose();
    emailFocus.dispose();
    passwordFocus.dispose();
    super.dispose();
  }

  void _handleEmailFocus() => _attachKeypad(emailController, emailFocus);

  void _handlePasswordFocus() =>
      _attachKeypad(passwordController, passwordFocus);


  /// Points the on-screen keypad at the field that has just taken the focus.
  void _attachKeypad(TextEditingController controller, FocusNode node) {
    if (!_keypadShown || !node.hasFocus) return;
    keyboard.attach(controller: controller, focusNode: node);
  }

  /// Clears a refusal the moment the input it describes stops being the input.
  ///
  /// Keyed on the text rather than on the notification, because a
  /// [TextEditingController] also notifies when only the selection moves — which
  /// is what the password field's own reveal toggle does, and revealing a
  /// password answers nothing the refusal said.
  void _handleInputChanged() {
    final email = emailController.text;
    final password = passwordController.text;
    if (email == _seenEmail && password == _seenPassword) return;
    _seenEmail = email;
    _seenPassword = password;
    if (_notice == null && _defect == null) return;
    setState(() {
      _notice = null;
      _defect = null;
    });
  }

  /// Moves to another mode, keeping the address and dropping everything else.
  ///
  /// **The address survives and the passwords do not.** Somebody who has just
  /// been told an account already uses that address is about to sign in with
  /// it, and somebody who cannot remember a password is about to ask for a
  /// reset for the same address - so retyping it is the one thing this
  /// transition should never ask for. A password carried across modes, by
  /// contrast, would be a credential typed for one purpose reused for another.
  void _changeMode(LoginMode mode) {
    if (isLoading) return;
    setState(() {
      _mode = mode;
      _notice = null;
      _defect = null;
      _resetAccepted = false;
      passwordController.clear();
      _seenPassword = '';
      _passwordHidden = true;
    });
  }

  /// Dispatches to whichever of the two this screen is doing.
  Future<void> _submit() => switch (_mode) {
    LoginMode.signIn => _submitSignIn(),
    LoginMode.resetPassword => _submitPasswordReset(),
  };

  /// Opens the signup flow, which owns everything after this screen.
  void _createAccount() {
    final route = widget.createAccountRoute;
    if (isLoading || route == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: route));
  }

  /// Asks the server to send a reset link.
  ///
  /// **The accepted state says nothing about whether an account exists**, and
  /// cannot: `requestPasswordReset` answers identically either way so that it
  /// cannot be used to discover who has one. See `password_reset.dart`.
  Future<void> _submitPasswordReset() async {
    if (isLoading) return;

    final email = emailController.text.trim();
    final defect = passwordResetInputDefect(email: email);
    if (defect != null) {
      setState(() {
        _defect = SignInInputDefect.missingEmail;
        _notice = null;
      });
      return;
    }

    setState(() {
      _defect = null;
      _notice = null;
      isLoading = true;
    });

    try {
      final gateway = _passwordReset;
      await gateway.submit(gateway.createIntent(email: email));
      if (mounted) {
        setState(() {
          _resetAccepted = true;
          isLoading = false;
        });
      }
    } catch (error, stackTrace) {
      if (mounted) {
        final failure = passwordResetFailure(error);
        setState(() {
          _notice = switch (failure.kind) {
            PasswordResetFailureKind.refused => AppNotice.refused(
              failure.message,
            ),
            PasswordResetFailureKind.unreachable => AppNotice.offline(
              failure.message,
            ),
          };
          isLoading = false;
        });
      }
      await Sentry.captureException(error, stackTrace: stackTrace);
    }
  }

  Future<void> _submitSignIn() async {
    if (isLoading) return; // Prevent multiple clicks

    final email = emailController.text.trim();
    final password = passwordController.text;

    // Refused here rather than by the identity provider. An empty password is
    // not a credential, and sending one reached a platform channel that threw
    // something which was not a `FirebaseAuthException` — which is how a raw
    // channel name came to be printed on the first screen of this app.
    final defect = signInInputDefect(email: email, password: password);
    if (defect != null) {
      setState(() {
        _defect = defect;
        _notice = null;
      });
      return;
    }

    setState(() {
      _defect = null;
      _notice = null;
      isLoading = true;
    });

    try {
      await _signIn.call(
        email: email,
        password: password,
        remember: rememberMe,
      );
      // Deliberately still loading. The routing shell replaces this screen once
      // the session opens, and releasing the button first offers a second
      // sign-in against a session that is already being built.
      return;
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() {
          // Never the caught object and never its message: whatever was thrown,
          // a user reads a sentence somebody wrote. See `signInFailure`.
          _notice = _noticeFor(signInFailure(error));
          isLoading = false;
        });
      }
      // Reported after the user has been answered, so a slow or failing
      // reporting transport can neither delay the sentence on screen nor
      // swallow it.
      await Sentry.captureException(error, stackTrace: stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    // `componentOf`, not `of`: this screen is pumped by widget tests that build
    // a bare `MaterialApp` with no theme at all, and crashing in all of them
    // buys nothing. See the accessor's own note for why the fallback cannot
    // shrink a tap target.
    final tokens = AppTokens.componentOf(context);
    _keypadShown = LoginScreen.showsKeypad(
      MediaQuery.sizeOf(context).width,
      tokens,
    );

    return KeyboardScope(
      keyboard: keyboard,
      child: Scaffold(
        backgroundColor: tokens.colors.surface.base,
        body: SafeArea(
          child: _keypadShown
              ? Row(
                  children: <Widget>[
                    Expanded(child: _form(tokens)),
                    Expanded(
                      // **No padding around the pane, deliberately.** The
                      // keypad's own margin is inside
                      // `PosKeyboard.minimumWidth`'s sum, and an inset added
                      // out here is a term that answer does not know about —
                      // which is exactly how the old layout came to draw
                      // 43-pixel keys against a component promising 48.
                      child: _GlassPane(
                        tokens: tokens,
                        child: Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: tokens.layout.reading,
                            ),
                            child: const PosKeyboard(),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : _form(tokens),
        ),
      ),
    );
  }

  /// The credential column: a title, a sentence, and the pill form under them.
  Widget _form(AppTokens tokens) {
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.s24,
          vertical: tokens.spacing.s32,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: tokens.layout.credential),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Semantics(
                header: true,
                child: Text(
                  _heading,
                  style: tokens.typography.display.copyWith(
                    color: tokens.colors.text.primary,
                  ),
                ),
              ),
              SizedBox(height: tokens.spacing.s8),
              Text(
                _subheading,
                key: const ValueKey('login-subheading'),
                style: tokens.typography.bodyLarge.copyWith(
                  color: tokens.colors.text.secondary,
                ),
              ),
              SizedBox(height: tokens.spacing.s40),
              _PillField(
                key: const ValueKey('login-email'),
                label: 'EMAIL / USER ID',
                leading: Icons.email_outlined,
                placeholder: 'name@example.com',
                controller: emailController,
                focusNode: emailFocus,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                enableSuggestions: false,
                error: _errorFor(SignInInputDefect.missingEmail),
                errorKey: const ValueKey('login-email-error'),
              ),
              if (_mode != LoginMode.resetPassword) ...<Widget>[
                SizedBox(height: tokens.spacing.s24),
                _PillField(
                  key: const ValueKey('login-password'),
                  label: 'PASSWORD',
                  leading: Icons.lock_outline,
                  placeholder: '********',
                  controller: passwordController,
                  focusNode: passwordFocus,
                  obscureText: _passwordHidden,
                  obscuringCharacter: '*',
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  error: _passwordError,
                  errorKey: const ValueKey('login-password-error'),
                  trailing: _revealToggle(tokens),
                ),
              ],
              if (_mode == LoginMode.signIn) ...<Widget>[
                SizedBox(height: tokens.spacing.s16),
                _rememberRow(tokens),
              ],
              if (_notice case final answer?) ...<Widget>[
                SizedBox(height: tokens.spacing.s16),
                Callout(
                  key: const ValueKey('login-notice'),
                  status: answer.status,
                  message: answer.message,
                ),
              ],
              if (_resetAccepted) ...<Widget>[
                SizedBox(height: tokens.spacing.s16),
                Callout(
                  key: const ValueKey('login-reset-accepted'),
                  status: AppStatus.ok,
                  message: passwordResetAcceptedMessage,
                ),
              ],
              SizedBox(height: tokens.spacing.s32),
              // The one submit is hidden once a reset has been accepted: there
              // is nothing left to ask for, and a live button beside "a link is
              // on its way" invites a second request the server would throttle.
              if (!_resetAccepted)
                _PillSubmitButton(
                  key: const ValueKey('login-submit'),
                  label: _submitLabel,
                  loading: isLoading,
                  onPressed: _submit,
                  tokens: tokens,
                ),
              SizedBox(height: tokens.spacing.s24),
              ..._modeLinks(tokens),
            ],
          ),
        ),
      ),
    );
  }

  /// The error line under a field, where this screen refused that field.
  String? _errorFor(SignInInputDefect defect) =>
      _defect == defect ? signInInputDefectMessage(defect) : null;

  /// The heading, which names what this screen is about to do.
  String get _heading => switch (_mode) {
    LoginMode.signIn => 'Welcome back',
    LoginMode.resetPassword => 'Forgotten password',
  };

  String get _subheading => switch (_mode) {
    LoginMode.signIn => 'Sign in to your account.',
    LoginMode.resetPassword =>
      'Enter the address for the account and a link to set a new password '
          'will be sent to it.',
  };

  String get _submitLabel => switch (_mode) {
    LoginMode.signIn => 'Sign in',
    LoginMode.resetPassword => 'Send the link',
  };

  /// The error under the password field.
  String? get _passwordError => _errorFor(SignInInputDefect.missingPassword);

  /// The ways out of this mode, under the submit.
  ///
  /// **Buttons, not sentences with a tappable word in them.** §9 makes a tap
  /// target 48 high pass/fail, and a link inside a paragraph is neither 48 high
  /// nor separately focusable. `AppButtonTier.tertiary` is the quiet tier, so
  /// they read as secondary to the submit above without being hard to hit.
  List<Widget> _modeLinks(AppTokens tokens) => switch (_mode) {
    LoginMode.signIn => <Widget>[
      _ModeLink(
        key: const ValueKey('login-go-reset'),
        label: 'I have forgotten my password',
        onPressed: isLoading
            ? null
            : () => _changeMode(LoginMode.resetPassword),
      ),
      SizedBox(height: tokens.spacing.s8),
      if (widget.createAccountRoute != null)
        _ModeLink(
          key: const ValueKey('login-go-register'),
          label: 'Create an account',
          onPressed: isLoading ? null : _createAccount,
        ),
    ],
    LoginMode.resetPassword => <Widget>[
      _ModeLink(
        key: const ValueKey('login-go-sign-in'),
        label: 'Back to sign in',
        onPressed: isLoading ? null : () => _changeMode(LoginMode.signIn),
      ),
    ],
  };

  /// The reveal toggle inside the password well.
  Widget _revealToggle(AppTokens tokens) => PressSurface(
    borderRadius: BorderRadius.circular(tokens.radius.sm),
    onPressed: _toggleReveal,
    hoverOverlay: tokens.colors.action.tertiary.hoverFill(),
    pressedOverlay: tokens.colors.action.tertiary.pressedFill(),
    semanticLabel: _passwordHidden ? 'Show the password' : 'Hide the password',
    child: Icon(
      _passwordHidden ? Icons.visibility_off : Icons.visibility,
      size: _pillIconSize,
      color: tokens.colors.text.tertiary,
    ),
  );

  void _toggleReveal() {
    setState(() {
      _passwordHidden = !_passwordHidden;
      passwordController.selection = TextSelection.collapsed(
        offset: passwordController.text.length,
      );
    });
  }

  Widget _rememberRow(AppTokens tokens) => SizedBox(
    height: tokens.density.minimumTapTarget.height,
    child: Row(
      children: <Widget>[
        Checkbox(
          value: rememberMe,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          activeColor: tokens.colors.action.primary.container,
          onChanged: (value) {
            setState(() {
              rememberMe = value ?? true;
            });
          },
        ),
        SizedBox(width: tokens.spacing.s12),
        Text(
          'Remember me',
          style: tokens.typography.bodyMedium.copyWith(
            color: tokens.colors.text.secondary,
          ),
        ),
      ],
    ),
  );
}

/// The icon size a pill field's leading glyph and trailing toggle share.
///
/// [AppButton.iconSize] would be the usual borrow, but this screen no longer
/// imports `buttons.dart` — its controls are pill-shaped, not that
/// component's — so the figure is named here instead of duplicated.
const double _pillIconSize = 20;

/// A label, an icon, and a pill-shaped well — the old front door's field,
/// redrawn from [AppTokens] instead of the hardcoded colors it used to read.
///
/// Deliberately not a restyled [AppFieldWell]: that component is `radius.md`
/// everywhere else in the app on purpose, and forking its shape here would
/// either fork the component or change every field in the app. This is the
/// same trade the old app made with its own `PillInput`, purpose-built for one
/// screen.
final class _PillField extends StatefulWidget {
  const _PillField({
    super.key,
    required this.label,
    required this.leading,
    required this.controller,
    required this.focusNode,
    this.placeholder,
    this.obscureText = false,
    this.obscuringCharacter = '*',
    this.keyboardType,
    this.textInputAction,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.onSubmitted,
    this.error,
    this.errorKey,
    this.trailing,
  });

  /// Addresses the error line, so a test reads the sentence a person reads
  /// rather than a field's private state.
  final Key? errorKey;

  final String label;
  final IconData leading;
  final String? placeholder;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool obscureText;
  final String obscuringCharacter;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool autocorrect;
  final bool enableSuggestions;
  final ValueChanged<String>? onSubmitted;
  final String? error;
  final Widget? trailing;

  @override
  State<_PillField> createState() => _PillFieldState();
}

class _PillFieldState extends State<_PillField> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocusChanged);
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!mounted || _focused == widget.focusNode.hasFocus) return;
    setState(() => _focused = widget.focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final failed = widget.error != null;
    final borderColor = failed
        ? colors.status.problem.fg
        : _focused
        ? colors.action.focusRing.color
        : Colors.transparent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          widget.label,
          style: tokens.typography.labelEyebrow.copyWith(
            color: colors.text.tertiary,
          ),
        ),
        SizedBox(height: tokens.spacing.s8),
        Container(
          constraints: BoxConstraints(
            minHeight: tokens.density.minimumTapTarget.height,
          ),
          padding: EdgeInsets.symmetric(horizontal: tokens.spacing.s20),
          decoration: BoxDecoration(
            color: colors.surface.field,
            borderRadius: BorderRadius.circular(tokens.radius.pill),
            border: Border.all(color: borderColor, width: 2),
          ),
          child: Row(
            children: <Widget>[
              Icon(widget.leading, size: _pillIconSize, color: colors.text.tertiary),
              SizedBox(width: tokens.spacing.s12),
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: widget.focusNode,
                  obscureText: widget.obscureText,
                  obscuringCharacter: widget.obscuringCharacter,
                  keyboardType: widget.keyboardType,
                  textInputAction: widget.textInputAction,
                  autocorrect: widget.autocorrect,
                  enableSuggestions: widget.enableSuggestions,
                  onSubmitted: widget.onSubmitted,
                  style: tokens.typography.bodyLarge.copyWith(
                    color: colors.text.primary,
                  ),
                  cursorColor: colors.action.focusRing.color,
                  // **All six border slots, not just `border`.** An
                  // `InputDecorator` prefers `enabledBorder`/`focusedBorder`
                  // over `border`, and the theme supplies both — so setting
                  // only `border` leaves the theme's outline painted inside
                  // this pill's own well. That is the `1b2b13b` defect, and
                  // it came straight back the first time this screen was
                  // reverted.
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    filled: false,
                    isCollapsed: true,
                    contentPadding: EdgeInsets.zero,
                    hintText: widget.placeholder,
                    hintStyle: tokens.typography.bodyLarge.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ),
              ),
              if (widget.trailing case final trailing?) ...<Widget>[
                SizedBox(width: tokens.spacing.s8),
                trailing,
              ],
            ],
          ),
        ),
        if (widget.error case final message?) ...<Widget>[
          SizedBox(height: tokens.spacing.s4),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: tokens.spacing.s4),
            child: Text(
              message,
              key: widget.errorKey,
              style: tokens.typography.caption.copyWith(
                color: colors.status.problem.fg,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The old front door's filled pill button, drawn in the primary action role.
final class _PillSubmitButton extends StatelessWidget {
  const _PillSubmitButton({
    super.key,
    required this.label,
    required this.loading,
    required this.onPressed,
    required this.tokens,
  });

  final String label;
  final bool loading;
  final VoidCallback? onPressed;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    final role = tokens.colors.action.primary;
    final enabled = onPressed != null && !loading;
    final radius = BorderRadius.circular(tokens.radius.pill);

    Widget content = Text(
      label,
      style: tokens.typography.labelLarge.copyWith(color: role.label),
    );
    if (loading) {
      content = Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Opacity(opacity: 0, child: content),
          SizedBox(
            width: tokens.colors.action.loadingIndicatorSize,
            height: tokens.colors.action.loadingIndicatorSize,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(role.label),
            ),
          ),
        ],
      );
    }

    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: loading ? '$label, working' : label,
      onTap: enabled ? onPressed : null,
      excludeSemantics: true,
      child: PressSurface(
        borderRadius: radius,
        onPressed: enabled ? onPressed : null,
        hoverOverlay: role.hoverFill(),
        pressedOverlay: role.pressedFill(),
        fillWidth: true,
        excludeSemantics: true,
        child: DecoratedBox(
          decoration: BoxDecoration(color: role.container, borderRadius: radius),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: tokens.density.minimumTapTarget.height,
            ),
            child: Center(child: content),
          ),
        ),
      ),
    );
  }
}

/// The blurred, gradient-tinted pane the old front door drew its on-screen
/// keyboard inside. See [AppEffects.glassBlurSigma].
///
/// No `BoxShadow`: [AppSurfaceRoles]'s own note is that depth here is a
/// surface step, never a drop shadow, and this pane keeps that rule rather
/// than reintroducing the old screen's blurred black shadow.
final class _GlassPane extends StatelessWidget {
  const _GlassPane({required this.tokens, required this.child});

  final AppTokens tokens;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(tokens.radius.lg);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            tokens.colors.surface.raised,
            tokens.colors.surface.overlay,
          ],
        ),
        border: Border.all(color: tokens.colors.surface.borderSubtle),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: tokens.effects.glassBlurSigma,
            sigmaY: tokens.effects.glassBlurSigma,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Which §2.1 status a sign-in failure is drawn as.
///
/// **The lookup is here rather than in `sign_in.dart`**, for the reason that
/// file's own doc gives about codes: the boundary carries what happened, and
/// what colour that is belongs to the screen. It is the same split
/// `checkout_configuration_panel.dart` makes between a write kind and its
/// notice.
AppNotice _noticeFor(SignInFailure failure) => switch (failure.kind) {
  SignInFailureKind.refused => AppNotice.refused(failure.message),
  // §2.1's `info` is "offline, read-only, informational" in its own words, and
  // `AppNotice.offline` is the constructor for *nothing was attempted*. Nothing
  // was: the request never arrived.
  SignInFailureKind.unreachable => AppNotice.offline(failure.message),
};


/// One quiet route out of the current mode.
///
/// A real button rather than a tappable word inside a sentence: §9 makes the
/// 48-high tap target pass/fail, and a `TextSpan` recognizer is neither that
/// tall nor separately reachable by a keyboard or a screen reader.
final class _ModeLink extends StatelessWidget {
  const _ModeLink({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => AppButton(
    label: label,
    tier: AppButtonTier.tertiary,
    onPressed: onPressed,
  );
}
