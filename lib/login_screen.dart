/// The sign-in screen. `design.md` §11 step 9, and the last unmigrated surface
/// the app's root reaches.
///
/// **It is a `Scaffold` rather than an `AppScaffold`, and that is the one
/// framing decision here worth arguing with.** `AppScaffold` is a toolbar, a
/// [PageHeader] and a §4.2-capped body, in that order and spanning the page.
/// Sign-in has nothing for a toolbar — there is no way back from the app's front
/// door and there is nothing to sign out of — so it would draw 56 logical pixels
/// of empty chrome above the title. More decisively, on a wide window this
/// screen is two panes and **the title belongs to the form**, not to a header
/// spanning a form and a keypad. `AppScaffold` cannot express that; [PageHeader]
/// inside the form column can, and it is the part of §7's page pattern that
/// carries the defect §7 names. So the pattern is kept and the frame is not.
///
/// **What §7's order does and does not decide here.** The pattern is
/// *`PageHeader` → optional `Callout` → filters → content*, and the notice on
/// this screen is not that `Callout`: §7's slot is for a standing fact about the
/// page — read-only, offline — and this one is what the identity provider
/// answered a moment ago. It therefore sits with the control that produced it,
/// where the seven back-office surfaces put theirs, and where this screen has
/// always drawn it.
///
/// **The defects this closes are `DESIGN-AUDIT.md` §4.4's, plus two it did not
/// have.** Uppercase field labels where §2.2 permits uppercase only on
/// `label.eyebrow`; a radius-32 well where §2.3 says `radius.sm`; a green glow
/// `BoxShadow` where §9 requires a 2px ring at a 2px offset; `Colors.green` for
/// the remember checkbox, a different green from the accent; `Colors.red` for
/// the refusal rather than §2.1's `problem`; and `"UNLOCK REGISTER →"`, which
/// §8 rule 3 names in its own words as the thing a control must not say. The two
/// it did not have are the **double border** every field has drawn since commit
/// `1b2b13b` — `InputDecorator` prefers `enabledBorder` over the
/// `border: InputBorder.none` `PillInput` set, and the theme supplies one — and
/// the **notice model**, which the 2026-08-15 sweep missed because this screen
/// names its state `login-error` rather than a notice.
///
/// **The keypad's boundary is measured rather than declared**, and it replaces
/// `width < 768`. §9 makes a key 48 wide, ten of them plus their gaps, the
/// card's inset and the pane's margin need [PosKeyboard.minimumWidth], and the
/// two panes share the window — so the question "is there room" is arithmetic
/// this screen can do rather than a band it can look up. See [showsKeypad], which
/// also records what the old boundary cost. Below it the form is one centred
/// column, which is §4.3's `Form` row at every band.
library;

import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'keyboard_controller.dart';
import 'keyboard_scope.dart';
import 'tenancy/sign_in.dart';
import 'ui/buttons.dart';
import 'ui/fields.dart';
import 'ui/press.dart';
import 'ui/scaffold.dart';
import 'ui/status.dart';
import 'ui/tokens.dart';
import 'widgets/pos_keyboard.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.signIn});

  /// The boundary this screen signs in through.
  ///
  /// Absent, it is a [FirebaseEmailPasswordSignIn] built on first submission, so
  /// a build that never submits never reaches `FirebaseAuth.instance`.
  final EmailPasswordSignIn? signIn;

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

  Future<void> _submit() async {
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
                      // No padding here, deliberately: the keypad's margin is
                      // inside `PosKeyboard.minimumWidth`'s sum, and a second
                      // inset added out here is a term that answer does not know
                      // about. The cap is §4.2's form width, so the two panes
                      // are the same measure on a window wider than 1440.
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: tokens.layout.reading,
                          ),
                          child: const PosKeyboard(),
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

  /// The form column, at §4.2's width for a form and centred in its pane.
  ///
  /// `Center` around the scroll view rather than inside it: a form shorter than
  /// the window sits in the middle of it and a taller one scrolls, which is what
  /// this screen has always done.
  Widget _form(AppTokens tokens) {
    final inset = AppScaffold.horizontalInset(tokens.spacing);
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: inset,
          vertical: tokens.spacing.s32,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: tokens.layout.reading),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // §7's first row, and §2.2's two screen-title roles. The subtitle
              // is the sentence that was already under the title, moved into the
              // slot built for it rather than reworded — which is the ruling
              // §7's title chunk made on 2026-08-15.
              const PageHeader(
                title: 'Welcome back',
                subtitle: 'Sign in to your account.',
              ),
              SizedBox(height: tokens.density.sectionGap),
              AppTextField(
                key: const ValueKey('login-email'),
                // Sentence case, not new words. §2.2 restricts uppercase to
                // `label.eyebrow` and §8 rule 7 asks for sentence case
                // everywhere else; *what* this field should be called is a copy
                // question and §11 step 11 is the copy pass.
                // **It was not merely wordy, it was false.** This screen signs
                // in through `signInWithEmailAndPassword` and nothing anywhere
                // accepts a user ID, so half the label named a credential this
                // app has never had - the same class of defect as the heading
                // that told every reader the staff directory was read-only.
                label: 'Email address',
                // §5.2's leading icon, back where the original had it. These two
                // are the clearest case the section describes: an envelope and a
                // padlock say which of the two boxes is which before the labels
                // are read, which is what a person signing in twice a day wants.
                leading: Icons.email_outlined,
                // `spiritpos.com` is not this product and never was - it is
                // Chilltent. The replacement names no domain at all rather than
                // swapping one for another: `example.com` is reserved by
                // RFC 2606, so it cannot ever be a real business's address, and
                // §5.2 asks a placeholder to be an example rather than a claim.
                placeholder: 'name@example.com',
                controller: emailController,
                focusNode: emailFocus,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                enableSuggestions: false,
                error: _errorFor(SignInInputDefect.missingEmail),
              ),
              SizedBox(height: tokens.spacing.s16),
              AppTextField(
                key: const ValueKey('login-password'),
                label: 'Password',
                leading: Icons.lock_outline,
                // **Asterisks, at the product owner's direction (2026-08-23),
                // and they are an example rather than a restatement.** §5.2
                // permits a placeholder that shows the shape of the value and
                // forbids one that repeats the label - which is why the note
                // this replaces was right to delete "Enter Password" and wrong
                // to conclude the field could carry nothing at all. Eight
                // asterisks are what this box will look like once somebody
                // types in it, so the placeholder and `obscuringCharacter`
                // below are deliberately the same glyph.
                placeholder: '********',
                controller: passwordController,
                focusNode: passwordFocus,
                obscureText: _passwordHidden,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                error: _errorFor(SignInInputDefect.missingPassword),
                trailing: _revealToggle(tokens),
              ),
              SizedBox(height: tokens.spacing.s16),
              _rememberRow(tokens),
              if (_notice case final answer?) ...<Widget>[
                SizedBox(height: tokens.spacing.s16),
                Callout(
                  key: const ValueKey('login-notice'),
                  status: answer.status,
                  message: answer.message,
                ),
              ],
              SizedBox(height: tokens.spacing.s24),
              AppButton(
                key: const ValueKey('login-submit'),
                // §8 rule 3: a control names its effect. §8's own list of what a
                // control must never say has "Unlock register" on it.
                label: 'Sign in',
                tier: AppButtonTier.primary,
                expand: true,
                loading: isLoading,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The error line under a field, where this screen refused that field.
  String? _errorFor(SignInInputDefect defect) =>
      _defect == defect ? signInInputDefectMessage(defect) : null;

  /// The reveal toggle inside the password well.
  ///
  /// A [PressSurface] rather than an `IconButton`: §9 wants a 48 x 48 target and
  /// a semantic label on an icon-only control, and `PressSurface` is the only
  /// thing in this app that gives both. It fits inside §5.2's 48-high well
  /// because the target is the box rather than an inset around the glyph.
  ///
  /// **At [AppButton.iconSize]**, which is one of the two icon sizes §5.2 names.
  /// A field's trailing control has no size row of its own, so it borrows a named
  /// one rather than inventing a third — the same gap `Callout.glyphSize` and
  /// `Disclosure.glyphSize` record, and the same answer.
  Widget _revealToggle(AppTokens tokens) => PressSurface(
    borderRadius: BorderRadius.circular(tokens.radius.sm),
    onPressed: _toggleReveal,
    hoverOverlay: tokens.colors.action.tertiary.hoverFill(),
    pressedOverlay: tokens.colors.action.tertiary.pressedFill(),
    semanticLabel: _passwordHidden ? 'Show the password' : 'Hide the password',
    child: Icon(
      _passwordHidden ? Icons.visibility_off : Icons.visibility,
      size: AppButton.iconSize,
      color: tokens.colors.text.tertiary,
    ),
  );

  void _toggleReveal() {
    setState(() {
      _passwordHidden = !_passwordHidden;
      // Restore cursor to end after toggling.
      passwordController.selection = TextSelection.collapsed(
        offset: passwordController.text.length,
      );
    });
  }

  Widget _rememberRow(AppTokens tokens) => Row(
    children: <Widget>[
      Checkbox(
        value: rememberMe,
        onChanged: (value) {
          setState(() {
            rememberMe = value ?? true;
          });
        },
      ),
      SizedBox(width: tokens.spacing.s8),
      Text(
        // Sentence case, §8 rule 7.
        'Remember me',
        style: tokens.density
            .body(tokens.typography)
            .copyWith(color: tokens.colors.text.secondary),
      ),
    ],
  );
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
