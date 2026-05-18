import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../main.dart';
import 'chat_screen.dart';

class CoursesScreen extends StatefulWidget {
  final String majorName;
  final String majorId;

  const CoursesScreen({
    super.key,
    required this.majorName,
    required this.majorId,
  });

  @override
  State<CoursesScreen> createState() => _CoursesScreenState();
}

class _CoursesScreenState extends State<CoursesScreen> {
  List<Map<String, dynamic>> courses = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchCourses();
  }

  Future<void> fetchCourses() async {
    try {
      final response = await supabase
          .from('groups')
          .select('id, name')
          .eq('major_id', widget.majorId)
          .eq('is_general', false)
          .order('name');

      if (mounted) {
        setState(() {
          courses = List<Map<String, dynamic>>.from(response);
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to load courses")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.majorName} Courses"),

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
      ),      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : courses.isEmpty
              ? const Center(child: Text("No courses found"))
              : ListView.builder(
                  padding: EdgeInsets.all(12.w),
                  itemCount: courses.length,
                  itemBuilder: (context, index) {
                    final course = courses[index];
                    return Padding(
                      padding: EdgeInsets.only(bottom: 12.h),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white10 : Colors.white,
                          borderRadius: BorderRadius.circular(18.r),
                          boxShadow: const [
                            BoxShadow(color: Colors.black12, blurRadius: 8)
                          ],
                        ),
                        child: ListTile(
                          title: Text(
                            course['name'],
                            style: TextStyle(
                              fontSize: 15.sp,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          trailing: const Icon(Icons.chat_bubble_outline),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  title: course['name'],
                                  roomId: course['id'],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}