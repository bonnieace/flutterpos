import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'keyboard_controller.dart';
import 'keyboard_scope.dart';
import 'widgets/pill_input.dart';
import 'widgets/pos_keyboard.dart';
import 'widgets/glass_card.dart';
import 'widgets/pill_button.dart';
import 'pos/pos.dart';
import 'screens/main_hub_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final keyboard = KeyboardController();

  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  final emailFocus = FocusNode();
  final passwordFocus = FocusNode();

  String? errorMessage; // For displaying errors
  bool isLoading = false; // For button loading state

  bool rememberMe = true; // Remember Me checkbox state

  bool get isMobile {
    final width = MediaQuery.of(context).size.width;
    return width < 768; // Mobile/tablet breakpoint
  }

  @override
  void initState() {
    super.initState();
    // Focus email field by default
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
    emailController.dispose();
    passwordController.dispose();
    emailFocus.dispose();
    passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (isLoading) return; // Prevent multiple clicks
    setState(() {
      errorMessage = null;
      isLoading = true;
    });
    try {
      // Set Firebase Auth persistence based on rememberMe
      // On web, you can set persistence. On mobile, it's always local, but this is safe.
      try {
        await FirebaseAuth.instance.setPersistence(
          rememberMe ? Persistence.LOCAL : Persistence.SESSION,
        );
      } catch (_) {
        // setPersistence is not supported on mobile, ignore error
      }

      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text,
      );
      
      // Fetch user role from Firestore
      final userDoc = await FirebaseFirestore.instance
          .collection('staff')
          .doc(credential.user!.uid)
          .get();
      
      if (!userDoc.exists) {
        setState(() {
          errorMessage = "User data not found";
        });
        await FirebaseAuth.instance.signOut();
        return;
      }
      
      final role = userDoc.data()?['role'] ?? 'cashier';
      
      // Navigate based on role
      if (mounted) {
        if (role == 'cashier') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const MainHubScreen()),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const MainHubScreen()),
          );
        }
      }
    } on FirebaseAuthException catch (e, st) {
      await Sentry.captureException(e, stackTrace: st);
      setState(() {
        errorMessage = e.message ?? "Login failed";
        isLoading = false;
      });
    } catch (e, st) {
      await Sentry.captureException(e, stackTrace: st);
      setState(() {
        errorMessage = "An unexpected error occurred";
        isLoading = false;
      });
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
            label: "EMAIL / USER ID",
            hint: "example@spiritpos.com",
            icon: Icons.email_outlined,
            controller: emailController,
            focusNode: emailFocus,
            keyboard: isMobile ? null : keyboard,
          ),
          const SizedBox(height: 24),
          PillInput(
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
              const Text(
                "Remember Me",
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 16),
            Text(
              errorMessage!,
              style: const TextStyle(color: Colors.red),
            ),
          ],
          const SizedBox(height: 32),
          PillButton(
            text: "UNLOCK REGISTER →",
            filled: true,
            onTap: isLoading ? null : _signIn,
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
                  Expanded(
                    flex: 5,
                    child: loginForm,
                  ),
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
