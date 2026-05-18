import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import 'private_chat_screen.dart';
import 'user_search_screen.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  List<Map<String, dynamic>> conversations = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchConversations();
  }

  Future<void> fetchConversations() async {
    try {
      final myId = supabase.auth.currentUser!.id;

      // Get all conversations I'm a member of
      final myConversations = await supabase
          .from('conversation_members')
          .select('conversation_id')
          .eq('user_id', myId);

      if (myConversations.isEmpty) {
        if (mounted) setState(() => isLoading = false);
        return;
      }

      final conversationIds = myConversations
          .map((c) => c['conversation_id'])
          .toList();

      // For each conversation get the other member's profile
      List<Map<String, dynamic>> convList = [];

      for (final convId in conversationIds) {
        final otherMember = await supabase
            .from('conversation_members')
            .select('user_id, profiles(username, email)')
            .eq('conversation_id', convId)
            .neq('user_id', myId)
            .single();

        // Get last message
        final lastMessages = await supabase
            .from('messages')
            .select('created_at')
            .eq('conversation_id', convId)
            .order('created_at', ascending: false)
            .limit(1);

        convList.add({
          'conversation_id': convId,
          'recipient_id': otherMember['user_id'],
          'username': otherMember['profiles']['username'],
          'email': otherMember['profiles']['email'],
          'last_message_at': lastMessages.isNotEmpty
              ? lastMessages[0]['created_at']
              : null,
        });
      }

      // Sort by most recent message
      convList.sort((a, b) {
        if (a['last_message_at'] == null) return 1;
        if (b['last_message_at'] == null) return -1;
        return b['last_message_at'].compareTo(a['last_message_at']);
      });

      if (mounted) {
        setState(() {
          conversations = convList;
          isLoading = false;
        });
      }
    } catch (e, stack) {
      debugPrint('CONV ERROR: $e');
      debugPrint('STACK: $stack');
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Messages"),

        actions: [
          Padding(
            padding: EdgeInsets.only(right: 5.w),
            child: Image.asset(
              'assets/images/LiuLogoNoBg.png',
              width: 35.w,
              height: 35.h,
              fit: BoxFit.contain,
            ),
          ),

          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const UserSearchScreen(),
                ),
              ).then((_) => fetchConversations());
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : conversations.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.message_outlined,
                        size: 60.w,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 16.h),
                      Text(
                        "No conversations yet",
                        style: TextStyle(
                          fontSize: 16.sp,
                          color: Colors.grey,
                        ),
                      ),
                      SizedBox(height: 8.h),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const UserSearchScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.search),
                        label: const Text("Find a student to message"),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: fetchConversations,
                  child: ListView.builder(
                    padding: EdgeInsets.all(12.w),
                    itemCount: conversations.length,
                    itemBuilder: (context, index) {
                      final conv = conversations[index];
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
                              backgroundColor: AppColors.navyBlue,
                              child: Text(
                                conv['username'][0].toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              conv['username'],
                              style: TextStyle(
                                fontSize: 15.sp,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              "Tap to open",
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: Colors.grey,
                              ),
                            ),
                            trailing: const Icon(
                              Icons.lock,
                              size: 16,
                              color: Colors.grey,
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PrivateChatScreen(
                                    recipientId: conv['recipient_id'],
                                    recipientUsername: conv['username'],
                                    existingConversationId: conv['conversation_id'],
                                  ),
                                ),
                              ).then((_) => fetchConversations());
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primaryOrange,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const UserSearchScreen()),
          ).then((_) => fetchConversations());
        },
        child: const Icon(Icons.edit, color: Colors.white),
      ),
    );
  }
}