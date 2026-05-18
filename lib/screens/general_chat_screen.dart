import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../main.dart';

class GeneralChatScreen extends StatefulWidget {
  final String majorName;
  final String majorId;

  const GeneralChatScreen({
    super.key,
    required this.majorName,
    required this.majorId,
  });

  @override
  State<GeneralChatScreen> createState() => _GeneralChatScreenState();
}

class _GeneralChatScreenState extends State<GeneralChatScreen> {
  final TextEditingController messageController = TextEditingController();
  List<Map<String, dynamic>> messages = [];
  WebSocketChannel? channel;
  String? groupId;
  bool isLoading = true;
  Map<String, String> usernameCache = {};

  @override
  void initState() {
    super.initState();
    initChat();
  }

  Future<String> getUsername(String userId) async {
    if (usernameCache.containsKey(userId)) return usernameCache[userId]!;
    try {
      final response = await supabase
          .from('profiles')
          .select('username')
          .eq('id', userId)
          .single();
      usernameCache[userId] = response['username'];
      return response['username'];
    } catch (_) {
      return 'Unknown';
    }
  }

  Future<void> initChat() async {
    try {
      final response = await supabase
          .from('groups')
          .select('id')
          .eq('major_id', widget.majorId)
          .eq('is_general', true)
          .single();

      groupId = response['id'];

      final msgs = await supabase
          .from('group_messages')
          .select('content, sender_id, created_at, profiles(username)')
          .eq('group_id', groupId!)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          messages = List<Map<String, dynamic>>.from(msgs);
          isLoading = false;
        });
      }

      connectWebSocket();
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to load chat")),
        );
      }
    }
  }

  void connectWebSocket() {
    final token = supabase.auth.currentSession?.accessToken;
    if (token == null) return;

    channel = WebSocketChannel.connect(
      Uri.parse('wss://liuchat-server.onrender.com'),
      protocols: [],
    );

    channel!.sink.add(jsonEncode({
      'type': 'auth',
      'token': token,
    }));

    channel!.stream.listen(
      (data) async {
        final msg = jsonDecode(data);
        if (msg['type'] == 'group_message' &&
            msg['group_id'] == groupId &&
            msg['sender_id'] != supabase.auth.currentUser?.id) {
          final username = await getUsername(msg['sender_id']);
          if (mounted) {
            setState(() {
              messages.insert(0, {
                'content': msg['content'],
                'sender_id': msg['sender_id'],
                'created_at': msg['created_at'],
                'profiles': {'username': username},
              });
            });
          }
        }
      },
      onError: (error) {
        debugPrint('WebSocket error: $error');
      },
    );
  }


  void sendMessage() {
    if (messageController.text.trim().isEmpty || groupId == null) return;

    final text = messageController.text.trim();

    channel?.sink.add(jsonEncode({
      'type': 'group_message',
      'group_id': groupId,
      'content': text,
    }));

    setState(() {
      messages.insert(0, {
        'content': text,
        'sender_id': supabase.auth.currentUser!.id,
        'created_at': DateTime.now().toIso8601String(),
        'profiles': {'username': 'You'},
      });
    });

    messageController.clear();
  }

  @override
  void dispose() {
    channel?.sink.close();
    messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final myId = supabase.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.majorName}"),

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
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    reverse: true,
                    padding: EdgeInsets.all(12.w),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final isMe = msg['sender_id'] == myId;
                      final username = msg['profiles']?['username'] ?? 'Unknown';

                      return Align(
                        alignment: isMe
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: EdgeInsets.only(bottom: 10.h),
                          padding: EdgeInsets.all(12.w),
                          decoration: BoxDecoration(
                            color: isMe
                                ? Theme.of(context).primaryColor
                                : (isDark ? Colors.white10 : Colors.grey[200]),
                            borderRadius: BorderRadius.circular(15.r),
                          ),
                          child: Column(
                            crossAxisAlignment: isMe
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              if (!isMe)
                                Text(
                                  username,
                                  style: TextStyle(
                                    fontSize: 11.sp,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey,
                                  ),
                                ),
                              Text(
                                msg['content'],
                                style: TextStyle(
                                  color: isMe ? Colors.white : Colors.black,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(10.w),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: messageController,
                          decoration: InputDecoration(
                            hintText: "Type a message...",
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20.r),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 10.w),
                      IconButton(
                        onPressed: sendMessage,
                        icon: const Icon(Icons.send),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}