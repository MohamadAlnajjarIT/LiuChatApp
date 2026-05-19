import '../main.dart';
import 'auth_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../theme/app_theme.dart';
import 'majors_screen.dart';
import 'conversations_screen.dart';
import 'about_us_screen.dart';
class HomeScreen extends StatelessWidget {
  HomeScreen({super.key});

  final List<Map<String, String>> schools = [
    {"name": "School of Arts & Sciences", "icon": "🎓"},
    {"name": "School of Business", "icon": "🎓"},
    {"name": "School of Engineering", "icon": "🎓"},
    {"name": "School of Pharmacy", "icon": "🎓"},
    {"name": "School of Education", "icon": "🎓"},
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,


        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),

              onSelected: (value) {
                if (value == 'about') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AboutUsScreen(),
                    ),
                  );
                }
              },

              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'about',
                  child: Text("About Us"),
                ),
              ],
            ),
            Text(
              "Liu Chat",
              style: TextStyle(
                fontSize: 20.sp,
                fontWeight: FontWeight.bold,
              ),
            ),

            SizedBox(width: 10.w),

            Image.asset(
              'assets/images/LiuLogoNoBg.png',
              width: 35.w,
              height: 35.h,
              fit: BoxFit.contain,
            ),
          ],
        ),

        actions: [
          IconButton(
            icon: const Icon(Icons.message),
            tooltip: "Private Messages",
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ConversationsScreen(),
              ),
            ),
          ),

          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: "Logout",
            onPressed: () async {
              await supabase.auth.signOut();

              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AuthScreen(),
                  ),
                      (_) => false,
                );
              }
            },
          ),
        ],
      ),

      body: ListView.builder(
        padding: EdgeInsets.only(top: 25.h),
        itemCount: schools.length,
        itemBuilder: (context, index) {
          final school = schools[index];
          return Padding(
            padding: EdgeInsets.only(
              bottom: 30.h,
              left: 12.w,
              right: 12.w,
            ),
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MajorsScreen(
                      schoolName: school["name"]!,
                    ),
                  ),
                );
              },
              child: Container(
                padding: EdgeInsets.all(33.w),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : Colors.white,
                  borderRadius: BorderRadius.circular(20.r),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 10)
                  ],
                ),
                child: Row(
                  children: [
                    Text(
                      school["icon"]!,
                      style: TextStyle(fontSize: 24.sp),
                    ),
                    SizedBox(width: 15.w),
                    Expanded(
                      child: Text(
                        school["name"]!,
                        style: TextStyle(
                          fontSize: 18.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios,
                      color: AppColors.primaryOrange,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}