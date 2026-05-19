import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import 'private_chat_screen.dart';

class UserSearchScreen extends StatefulWidget {
  const UserSearchScreen({super.key});

  @override
  State<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends State<UserSearchScreen> {
  final TextEditingController searchController = TextEditingController();
  List<Map<String, dynamic>> results = [];
  bool isLoading = false;
  Timer? _debounce;

  @override
  void dispose() {
    searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      final cleaned = query.trim();
      // Only digits, minimum 2 characters
      if (cleaned.length >= 2 && RegExp(r'^\d+$').hasMatch(cleaned)) {
        searchUsers(cleaned);
      } else {
        setState(() => results = []);
      }
    });
  }

  Future<void> searchUsers(String query) async {
    setState(() => isLoading = true);

    try {
      final myId = supabase.auth.currentUser!.id;

      final response = await supabase
          .from('profiles')
          .select('id, username, email')
          .ilike('username', '%$query%')
          .neq('id', myId) // exclude yourself
          .limit(20);

      if (mounted) {
        setState(() {
          results = List<Map<String, dynamic>>.from(response);
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Search failed")),
        );
      }
    }
  }

  void startConversation(Map<String, dynamic> user) {
   Navigator.push(
     context,
     MaterialPageRoute(
       builder: (_) => PrivateChatScreen(
         recipientId: user['id'],
         recipientUsername: user['username'],
       ),
     ),
   );
 }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Find a Student"),

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
      ),      body: Column(
        children: [
          // Search bar
          Padding(
            padding: EdgeInsets.all(12.w),
            child: TextField(
              controller: searchController,
              onChanged: onSearchChanged,
              autofocus: true,
              decoration: InputDecoration(
                hintText: "Search by student ID...",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: isLoading
                    ? Padding(
                        padding: EdgeInsets.all(12.w),
                        child: SizedBox(
                          width: 16.w,
                          height: 16.w,
                          child: const CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15.r),
                ),
              ),
            ),
          ),

          // Results
          Expanded(
            child: results.isEmpty
                ? Center(
                    child: Text(
                      searchController.text.length < 2
                          ? "Type at least 2 characters to search"
                          : "No students found",
                      style: TextStyle(color: Colors.grey, fontSize: 14.sp),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.symmetric(horizontal: 12.w),
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      final user = results[index];
                      return Padding(
                        padding: EdgeInsets.only(bottom: 10.h),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white10 : Colors.white,
                            borderRadius: BorderRadius.circular(15.r),
                            boxShadow: const [
                              BoxShadow(color: Colors.black12, blurRadius: 6)
                            ],
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppColors.primaryOrange,
                              child: Text(
                                user['username'][0].toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              user['username'],
                              style: TextStyle(
                                fontSize: 15.sp,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              user['email'],
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: Colors.grey,
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.message,
                                color: AppColors.primaryOrange,
                              ),
                              onPressed: () => startConversation(user),
                            ),
                            onTap: () => startConversation(user),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}