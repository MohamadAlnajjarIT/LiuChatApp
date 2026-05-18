import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../main.dart';
import '../services/encryption_service.dart';
import 'home_screen.dart';

class VerifyScreen extends StatefulWidget {
  final String email;

  const VerifyScreen({
    super.key,
    required this.email,
  });

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  final TextEditingController codeController = TextEditingController();
  bool isLoading = false;
  bool canResend = false;
  int countdown = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    startCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    codeController.dispose();
    super.dispose();
  }

  void startCooldown() {
    setState(() {
      canResend = false;
      countdown = 60;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        countdown--;
        if (countdown <= 0) {
          canResend = true;
          timer.cancel();
        }
      });
    });
  }

  Future<void> verifyCode() async {
    final code = codeController.text.trim();

    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter the 6-digit code")),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      await supabase.auth.verifyOTP(
        email: widget.email,
        token: code,
        type: OtpType.email,
      );

      await EncryptionService.initializeKeys();

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => HomeScreen()),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Verification failed. Try again.")),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> resendCode() async {
    if (!canResend) return;
    try {
      await supabase.auth.signInWithOtp(email: widget.email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Code resent to your email")),
        );
        startCooldown();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to resend code")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Verify Email"),

        actions: [
          Padding(
            padding: EdgeInsets.only(right: 12.w),
            child: Image.asset(
              'assets/images/LiuLogoNoBg.png',
              width: 35.w,
              height: 35.h,
              fit: BoxFit.contain,
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned(
            top: -60, right: -40,
            child: Container(
              width: 180.w, height: 180.w,
              decoration: BoxDecoration(
                color: AppColors.primaryOrange.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: -80, left: -50,
            child: Container(
              width: 220.w, height: 220.w,
              decoration: BoxDecoration(
                color: AppColors.navyBlue.withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: EdgeInsets.all(20.w),
              child: Container(
                padding: EdgeInsets.all(25.w),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white,
                  borderRadius: BorderRadius.circular(25.r),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 20)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Email Verification",
                      style: TextStyle(fontSize: 25.sp, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 15.h),
                    Text(
                      "Enter the 6-digit code sent to\n${widget.email}",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14.sp, color: Colors.grey),
                    ),
                    SizedBox(height: 25.h),
                    TextField(
                      controller: codeController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 22.sp, letterSpacing: 8),
                      decoration: InputDecoration(
                        hintText: "------",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15.r),
                        ),
                      ),
                    ),
                    SizedBox(height: 30.h),
                    SizedBox(
                      width: double.infinity,
                      height: 45.h,
                      child: ElevatedButton(
                        onPressed: isLoading ? null : verifyCode,
                        child: isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : Text("Verify", style: TextStyle(fontSize: 18.sp)),
                      ),
                    ),
                    SizedBox(height: 15.h),
                    TextButton(
                      onPressed: canResend ? resendCode : null,
                      child: Text(
                        canResend ? "Resend Code" : "Resend in ${countdown}s",
                        style: TextStyle(
                          color: canResend ? AppColors.primaryOrange : Colors.grey,
                          fontSize: 14.sp,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}