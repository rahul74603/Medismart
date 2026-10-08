package com.rahul7788.medismart_erp

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.telephony.SmsManager

class MainActivity : FlutterActivity() {
    private val CHANNEL = "medismart/sms"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "sendSms") {
                try {
                    val number = call.argument<String>("number") ?: ""
                    val message = call.argument<String>("message") ?: ""
                    if (number.isEmpty() || message.isEmpty()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    @Suppress("DEPRECATION")
                    val sms = SmsManager.getDefault()
                    val parts = sms.divideMessage(message)
                    if (parts.size > 1) {
                        sms.sendMultipartTextMessage(number, null, parts, null, null)
                    } else {
                        sms.sendTextMessage(number, null, message, null, null)
                    }
                    result.success(true)
                } catch (e: Exception) {
                    result.success(false)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
