import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../main.dart';
import 'major_options_screen.dart';

class MajorsScreen extends StatefulWidget {
  final String schoolName;

  const MajorsScreen({super.key, required this.schoolName});

  @override
  State<MajorsScreen> createState() => _MajorsScreenState();
}

class _MajorsScreenState extends State<MajorsScreen> {
  List<Map<String, dynamic>> majors = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchMajors();
  }

  Future<void> fetchMajors() async {
    try {
      final response = await supabase
          .from('majors')
          .select('id, name')
          .eq('school', widget.schoolName)
          .order('name');

      if (mounted) {
        setState(() {
          majors = List<Map<String, dynamic>>.from(response);
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to load majors")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.schoolName),

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
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : majors.isEmpty
              ? const Center(child: Text("No majors found"))
              : ListView.builder(
                  padding: EdgeInsets.all(12.w),
                  itemCount: majors.length,
                  itemBuilder: (context, index) {
                    final major = majors[index];
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
                            major['name'],
                            style: TextStyle(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MajorOptionsScreen(
                                  majorName: major['name'],
                                  majorId: major['id'],
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