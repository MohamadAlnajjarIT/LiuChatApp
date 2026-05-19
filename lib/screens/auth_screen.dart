import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../main.dart';
import 'verify_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final TextEditingController emailController = TextEditingController();
  bool isLoading = false;

  bool isValidLiuEmail(String email) {
    if (email == "tester@students.liu.edu.lb") return true;
    final regex = RegExp(r'^\d{8}@students\.liu\.edu\.lb$');
    return regex.hasMatch(email.trim().toLowerCase());
  }

  Future<void> sendOtp() async {
    final email = emailController.text.trim().toLowerCase();

    if (!isValidLiuEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter a valid LIU student email (8-digit ID)")),
      );
      return;
    }
    if (email == "tester@students.liu.edu.lb") {
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => VerifyScreen(email: email)),
    );
  }
  return;
}

    setState(() => isLoading = true);

    try {
      await supabase.auth.signInWithOtp(email: email);

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => VerifyScreen(email: email)),
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
          const SnackBar(content: Text("Something went wrong. Try again.")),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          Positioned(
            top: -80, right: -50,
            child: Container(
              width: 220.w, height: 220.w,
              decoration: BoxDecoration(
                color: AppColors.primaryOrange.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: -100, left: -60,
            child: Container(
              width: 250.w, height: 250.w,
              decoration: BoxDecoration(
                color: AppColors.navyBlue.withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(25.w),
                child: Container(
                  padding: EdgeInsets.all(20.w),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white,
                    borderRadius: BorderRadius.circular(25.r),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 20)],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text("Welcome to LIU Chat \n               App",
                          style: TextStyle(
                            fontSize: 25.sp,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryOrange,
                          )),

                      SizedBox(height: 25.h),
                      TextField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          hintText: "Enter Your University Email",
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
                          onPressed: isLoading ? null : sendOtp,
                          child: isLoading
                              ? const CircularProgressIndicator(color: Colors.white)
                              : Text("Send OTP", style: TextStyle(fontSize: 18.sp)),
                        ),
                      ),
                      SizedBox(height: 25.h),
                      Center(
                        child: Image.asset(
                          'assets/images/LiuLogoNoBg.png',
                          width: 120.w,
                          height: 120.w,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}