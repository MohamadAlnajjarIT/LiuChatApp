import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../services/encryption_service.dart';

class PrivateChatScreen extends StatefulWidget {
  final String recipientId;
  final String recipientUsername;
  final String? existingConversationId;

  const PrivateChatScreen({
    super.key,
    required this.recipientId,
    required this.recipientUsername,
    this.existingConversationId,
  });

  @override
  State<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

class _PrivateChatScreenState extends State<PrivateChatScreen> {
  final TextEditingController messageController = TextEditingController();

  List<Map<String, dynamic>> messages = [];
  WebSocketChannel? channel;
  String? conversationId;
  String? recipientPublicKey;
  bool isLoading = true;
  bool isSending = false;
  final myId = supabase.auth.currentUser!.id;

  // Key cache: tracks fetched keys. null value = fetch attempted but key missing.
  // Use containsKey() to distinguish "not yet fetched" from "fetched but null".
  final Map<String, String?> _keyCache = {};

  @override
  void initState() {
    super.initState();
    initChat();
  }

  Future<void> initChat() async {
    try {
      // Fetch recipient's public key — needed for encryption
      recipientPublicKey = await EncryptionService.getPublicKey(widget.recipientId);

      // Pre-populate cache with recipient key (even if null)
      _keyCache[widget.recipientId] = recipientPublicKey;

      if (recipientPublicKey == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("This user hasn't set up encryption yet. They need to log in first."),
            ),
          );
          setState(() => isLoading = false);
        }
        return;
      }

      // Connect WebSocket first
      await connectWebSocket();

      // If we have an existing conversation, load history
      if (widget.existingConversationId != null) {
        conversationId = widget.existingConversationId;
        await loadMessageHistory();
      }

      if (mounted) setState(() => isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to initialize chat: $e")),
        );
      }
    }
  }

  Future<void> connectWebSocket() async {
    final token = supabase.auth.currentSession?.accessToken;
    if (token == null) return;

    channel = WebSocketChannel.connect(
      Uri.parse('wss://liuchat-server.onrender.com'),
    );

    // Auth first
    channel!.sink.add(jsonEncode({
      'type': 'auth',
      'token': token,
    }));

    // Listen for messages
    channel!.stream.listen(
          (data) async {
        final msg = jsonDecode(data);

        if (msg['type'] == 'connected') {
          // Auth confirmed — if no existing conversation, create one
          if (widget.existingConversationId == null) {
            channel!.sink.add(jsonEncode({
              'type': 'create_conversation',
              'with_user_id': widget.recipientId,
            }));
          }
        } else if (msg['type'] == 'conversation_created') {
          conversationId = msg['conversation_id'];
          await loadMessageHistory();
        } else if (msg['type'] == 'private_message' &&
            msg['conversation_id'] == conversationId) {
          await handleIncomingMessage(msg);
        } else if (msg['type'] == 'error') {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(msg['message'] ?? 'Server error')),
            );
          }
        }
      },
      onError: (error) {
        debugPrint('WebSocket error: $error');
      },
    );
  }

  /// Fetches a public key with caching.
  /// Uses containsKey() so we don't re-fetch keys that returned null.
  Future<String?> _getCachedKey(String userId) async {
    if (_keyCache.containsKey(userId)) {
      return _keyCache[userId]; // already fetched (may be null)
    }
    final key = await EncryptionService.getPublicKey(userId);
    _keyCache[userId] = key; // cache even if null
    return key;
  }

  Future<void> loadMessageHistory() async {
    if (conversationId == null) return;

    try {
      final msgs = await supabase
          .from('messages')
          .select('id, encrypted_content, sender_id, created_at')
          .eq('conversation_id', conversationId!)
          .order('created_at', ascending: false);

      List<Map<String, dynamic>> decryptedMessages = [];

      for (final msg in msgs) {
        final senderId = msg['sender_id'] as String;
        try {
          String decryptedContent;

          if (senderId == myId) {
            // Own message — was encrypted with recipient's public key
            decryptedContent = await EncryptionService.decryptMessage(
              msg['encrypted_content'],
              recipientPublicKey!,
            );
          } else {
            // Their message — decrypt using sender's public key
            final senderKey = await _getCachedKey(senderId);
            if (senderKey == null) {
              decryptedContent = '[Unable to decrypt]';
            } else {
              decryptedContent = await EncryptionService.decryptMessage(
                msg['encrypted_content'],
                senderKey,
              );
            }
          }

          decryptedMessages.add({
            'content': decryptedContent,
            'sender_id': senderId,
            'created_at': msg['created_at'],
            'isMe': senderId == myId,
          });
        } catch (e) {
          decryptedMessages.add({
            'content': '[Unable to decrypt message]',
            'sender_id': senderId,
            'created_at': msg['created_at'],
            'isMe': senderId == myId,
          });
        }
      }

      if (mounted) setState(() => messages = decryptedMessages);
    } catch (e) {
      debugPrint('Failed to load message history: $e');
    }
  }

  Future<void> handleIncomingMessage(Map<String, dynamic> msg) async {
    try {
      final senderId = msg['sender_id'] as String;
      final senderKey = await _getCachedKey(senderId);

      debugPrint('sender_id: $senderId');
      debugPrint('senderKey: $senderKey');
      debugPrint('myId: $myId');
      debugPrint('recipientId: ${widget.recipientId}');

      if (senderKey == null) {
        debugPrint('KEY IS NULL — cannot decrypt');
        return;
      }

      final decrypted = await EncryptionService.decryptMessage(
        msg['encrypted_content'],
        senderKey,
      );

      if (mounted) {
        setState(() {
          messages.insert(0, {
            'content': decrypted,
            'sender_id': senderId,
            'created_at': msg['created_at'],
            'isMe': false,
          });
        });
      }
    } catch (e) {
      debugPrint('Failed to decrypt incoming message: $e');
    }
  }

  Future<void> sendMessage() async {
    if (messageController.text.trim().isEmpty) return;
    if (conversationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Conversation not ready yet")),
      );
      return;
    }
    if (recipientPublicKey == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Cannot encrypt — recipient has no public key")),
      );
      return;
    }

    final text = messageController.text.trim();
    messageController.clear();

    setState(() => isSending = true);

    try {
      final encryptedContent = await EncryptionService.encryptMessage(
        text,
        recipientPublicKey!,
      );

      channel?.sink.add(jsonEncode({
        'type': 'private_message',
        'conversation_id': conversationId,
        'encrypted_content': encryptedContent,
      }));

      setState(() {
        messages.insert(0, {
          'content': text,
          'sender_id': myId,
          'created_at': DateTime.now().toIso8601String(),
          'isMe': true,
        });
        isSending = false;
      });
    } catch (e) {
      setState(() => isSending = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to send: $e")),
        );
      }
    }
  }

  String formatTime(String isoString) {
    final dt = DateTime.parse(isoString).toLocal();
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$hour:$min';
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

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 16.r,
              backgroundColor: AppColors.primaryOrange,
              child: Text(
                widget.recipientUsername[0].toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            SizedBox(width: 10.w),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.recipientUsername,
                  style: TextStyle(fontSize: 15.sp),
                ),
                Row(
                  children: [
                    Icon(
                      Icons.lock,
                      size: 10.sp,
                      color: Colors.greenAccent,
                    ),
                    SizedBox(width: 3.w),
                    Text(
                      "End-to-end encrypted",
                      style: TextStyle(
                        fontSize: 10.sp,
                        color: Colors.greenAccent,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
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
          : Column(
        children: [
          // Encryption notice banner
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 6.h),
            color: Colors.green.withValues(alpha: 0.1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock, size: 12.sp, color: Colors.green),
                SizedBox(width: 4.w),
                Text(
                  "Messages are end-to-end encrypted",
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ),

          // Messages list
          Expanded(
            child: messages.isEmpty
                ? Center(
              child: Text(
                "No messages yet. Say hi! 👋",
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 14.sp,
                ),
              ),
            )
                : ListView.builder(
              reverse: true,
              padding: EdgeInsets.all(12.w),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final msg = messages[index];
                final isMe = msg['isMe'] as bool;

                return Align(
                  alignment: isMe
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: EdgeInsets.only(bottom: 10.h),
                    constraints: BoxConstraints(
                      maxWidth:
                      MediaQuery.of(context).size.width * 0.75,
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal: 14.w,
                      vertical: 10.h,
                    ),
                    decoration: BoxDecoration(
                      color: isMe
                          ? AppColors.primaryOrange
                          : (isDark
                          ? Colors.white10
                          : Colors.grey[200]),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(15.r),
                        topRight: Radius.circular(15.r),
                        bottomLeft: isMe
                            ? Radius.circular(15.r)
                            : Radius.circular(4.r),
                        bottomRight: isMe
                            ? Radius.circular(4.r)
                            : Radius.circular(15.r),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: isMe
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        Text(
                          msg['content'],
                          style: TextStyle(
                            color: isMe ? Colors.white : null,
                            fontSize: 14.sp,
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          formatTime(msg['created_at']),
                          style: TextStyle(
                            fontSize: 10.sp,
                            color: isMe
                                ? Colors.white70
                                : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Input bar
          Padding(
            padding: EdgeInsets.all(10.w),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: messageController,
                    maxLines: null,
                    decoration: InputDecoration(
                      hintText: "Type a message...",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20.r),
                      ),
                    ),
                    onSubmitted: (_) => sendMessage(),
                  ),
                ),
                SizedBox(width: 8.w),
                isSending
                    ? Padding(
                  padding: EdgeInsets.all(8.w),
                  child: const CircularProgressIndicator(
                      strokeWidth: 2),
                )
                    : IconButton(
                  onPressed: sendMessage,
                  icon: const Icon(
                    Icons.send,
                    color: AppColors.primaryOrange,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}