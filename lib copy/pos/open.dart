import 'package:Thamani/pos/nav_menu.dart';
import 'package:flutter/material.dart';






class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Simulate a delay, such as fetching data or performing some tasks
    Future.delayed(const Duration(seconds: 2), () {
      // Navigate to the 'pos.dart' page
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const NavigationMenu()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
            SizedBox(
            height: 150,
            child: Image.asset('images/payment.png')),
          ],
        ),

         

      ),
      
    );
  }
}


