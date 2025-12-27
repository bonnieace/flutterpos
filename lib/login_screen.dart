import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  @override
  void initState() {
    super.initState();
    // Focus email field by default
    WidgetsBinding.instance.addPostFrameCallback((_) {
      emailFocus.requestFocus();
      keyboard.attach(controller: emailController, focusNode: emailFocus);
    });
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
    setState(() {
      errorMessage = null;
    });
    try {
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
            MaterialPageRoute(builder: (context) => const pos()),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const MainHubScreen()),
          );
        }
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        errorMessage = e.message ?? "Login failed";
      });
    } catch (e) {
      setState(() {
        errorMessage = "An unexpected error occurred";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardScope(
      keyboard: keyboard,
      child: Scaffold(
        body: Row(
          children: [
            // LEFT PANEL
            Expanded(
              flex: 5,
              child: Padding(
                padding: const EdgeInsets.all(64),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Spacer(),
                    const Text(
                      "Welcome Back",
                      style: TextStyle(
                        fontSize: 40,
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
                      keyboard: keyboard,
                    ),
                    const SizedBox(height: 24),
                    PillInput(
                      label: "PASSWORD",
                      hint: "Enter Password",
                      icon: Icons.lock_outline,
                      obscure: true,
                      controller: passwordController,
                      focusNode: passwordFocus,
                      keyboard: keyboard,
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
                      onTap: _signIn,
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
            // RIGHT PANEL
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
