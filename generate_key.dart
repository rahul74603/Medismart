// फाइल का नाम: lib/generate_key.dart
import 'dart:convert';
import 'package:crypto/crypto.dart';

void main() {
  // ---------------------------------------------------------
  // 1. यहाँ दुकानदार की भेजी हुई ID डालो
  String clientDeviceId = "TP1A.220624.014"; 
  // ---------------------------------------------------------

  // 2. आपका सीक्रेट कोड (यह main.dart में भी सेम होना चाहिए)
  String secretSalt = "RAHUL_MEDICAL_ERP_2024_SECRET";

  // 3. जादुई मंत्र (Password Generation)
  var bytes = utf8.encode(clientDeviceId + secretSalt);
  var digest = sha256.convert(bytes);
  
  // 4. पासवर्ड तैयार है (शुरू के 8 अक्षर)
  String activationKey = digest.toString().substring(0, 8).toUpperCase();

  print("\n===========================================");
  print("DEVICE ID    : $clientDeviceId");
  print("PASSWORD (KEY): $activationKey");
  print("===========================================\n");
}