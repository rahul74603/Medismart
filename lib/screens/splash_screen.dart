import 'dart:async';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../main.dart'; // Dashboard ke liye

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  
  @override
  void initState() {
    super.initState();
    // 3 Second ka timer, uske baad Dashboard par jump karega
    Timer(const Duration(seconds: 3), () {
      Navigator.pushReplacement(
        context, 
        MaterialPageRoute(builder: (context) => const DashboardScreen())
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Gradient Background (Professional Look)
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1565C0), Color(0xFF42A5F5)], // Blue Gradient
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // --- LOGO ICON ---
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, spreadRadius: 2)]
              ),
              child: const Icon(FontAwesomeIcons.heartPulse, size: 60, color: Color(0xFF1565C0)),
            ),
            
            const SizedBox(height: 20),
            
            // --- APP NAME ---
            const Text(
              "MediSmart",
              style: TextStyle(
                fontSize: 32, 
                fontWeight: FontWeight.bold, 
                color: Colors.white,
                letterSpacing: 2
              ),
            ),
            
            const Text(
              "Pharmacy Management System",
              style: TextStyle(fontSize: 14, color: Colors.white70),
            ),

            const SizedBox(height: 50),

            // --- LOADER ---
            const CircularProgressIndicator(color: Colors.white),
          ],
        ),
      ),
    );
  }
}