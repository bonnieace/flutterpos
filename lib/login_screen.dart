import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'keyboard_controller.dart';
import 'keyboard_scope.dart';
import 'tenancy/sign_in.dart';
import 'ui/tokens.dart';
import 'widgets/pill_input.dart';
import 'widgets/pos_keyboard.dart';
import 'widgets/glass_card.dart';
import 'widgets/pill_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.signIn});

  /// The boundary this screen signs in through.
  ///
  /// Absent, it is a [FirebaseEmailPasswordSignIn] built on first submission, so
  /// a build that never submits never reaches `FirebaseAuth.instance`.
  final EmailPasswordSignIn? signIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final keyboard = KeyboardController();

  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  final emailFocus = FocusNode();
  final passwordFocus = FocusNode();

  late final EmailPasswordSignIn _signIn =
      widget.signIn ?? FirebaseEmailPasswordSignIn();

  String? errorMessage; // For displaying errors
  bool isLoading = false; // For button loading state

  bool rememberMe = true; // Remember Me checkbox state

  /// The text this state has already seen, so a notification that changed no
  /// text can be told apart from one that did. See [_handleInputChanged].
  String _seenEmail = '';
  String _seenPassword = '';

  /// Whether this screen is at §4.1's `compact` band.
  ///
  /// **The third of the three declarations of 768 this app carried**, and the
  /// only one that was not even a named constant - it was `width < 768` with a
  /// comment. `design.md` §4.1 asks that a screen consult one variable, and
  /// step 6 made [AppLayout] that variable; this reads it at the same number.
  /// **Sign-in's visual design is still step 9's** and nothing else here was
  /// touched.
  bool get isMobile =>
      AppLayout.contract.breakpointOf(MediaQuery.of(context).size.width) ==
      AppBreakpoint.compact;

  @override
  void initState() {
    super.initState();
    emailController.addListener(_handleInputChanged);
    passwordController.addListener(_handleInputChanged);
    // Focus email field by default
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      emailFocus.requestFocus();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Attach keyboard only on desktop
    if (!isMobile) {
      keyboard.attach(controller: emailController, focusNode: emailFocus);
    }
  }

  @override
  void dispose() {
    emailController.removeListener(_handleInputChanged);
    passwordController.removeListener(_handleInputChanged);
    emailController.dispose();
    passwordController.dispose();
    emailFocus.dispose();
    passwordFocus.dispose();
    super.dispose();
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
    if (errorMessage == null) return;
    setState(() => errorMessage = null);
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
      setState(() => errorMessage = signInInputDefectMessage(defect));
      return;
    }

    setState(() {
      errorMessage = null;
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
          // a user reads a sentence somebody wrote. See `signInSafeError`.
          errorMessage = signInSafeError(error);
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
    final loginForm = Padding(
      padding: EdgeInsets.all(isMobile ? 24 : 64),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isMobile) const SizedBox(height: 60) else const Spacer(),
          Text(
            "Welcome Back",
            style: TextStyle(
              fontSize: isMobile ? 32 : 40,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            "Sign in to your account.",
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 40),
          PillInput(
            key: const ValueKey('login-email'),
            label: "EMAIL / USER ID",
            hint: "example@spiritpos.com",
            icon: Icons.email_outlined,
            controller: emailController,
            focusNode: emailFocus,
            keyboard: isMobile ? null : keyboard,
          ),
          const SizedBox(height: 24),
          PillInput(
            key: const ValueKey('login-password'),
            label: "PASSWORD",
            hint: "Enter Password",
            icon: Icons.lock_outline,
            obscure: true,
            controller: passwordController,
            focusNode: passwordFocus,
            keyboard: isMobile ? null : keyboard,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Checkbox(
                value: rememberMe,
                onChanged: (value) {
                  setState(() {
                    rememberMe = value ?? true;
                  });
                },
                activeColor: Colors.green,
              ),
              const Text("Remember Me", style: TextStyle(color: Colors.white)),
            ],
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 16),
            Text(
              errorMessage!,
              key: const ValueKey('login-error'),
              style: const TextStyle(color: Colors.red),
            ),
          ],
          const SizedBox(height: 32),
          PillButton(
            key: const ValueKey('login-submit'),
            text: "UNLOCK REGISTER →",
            filled: true,
            onTap: isLoading ? null : _submit,
            isLoading: isLoading,
          ),
          if (isMobile) const SizedBox(height: 40) else const Spacer(),
        ],
      ),
    );

    return KeyboardScope(
      keyboard: keyboard,
      child: Scaffold(
        body: isMobile
            ? Center(child: SingleChildScrollView(child: loginForm))
            : Row(
                children: [
                  // LEFT PANEL
                  Expanded(flex: 5, child: loginForm),
                  // RIGHT PANEL (Desktop only)
                  Expanded(
                    flex: 4,
                    child: GlassCard(
                      margin: const EdgeInsets.all(24),
                      child: const PosKeyboard(),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
