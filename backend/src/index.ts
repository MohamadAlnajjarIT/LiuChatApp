import express from 'express';
import apiRouter from './api';
import { WebSocketServer, WebSocket } from 'ws';
import http from 'http';
import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';

dotenv.config();

export const supabase = createClient(
  process.env.SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_KEY!
);


const PORT = parseInt(process.env.PORT || '8080');

const app = express();
app.use(express.json());
app.use('/api', apiRouter);

const server = http.createServer(app);

const wss = new WebSocketServer({
  server,
  maxPayload: 16 * 1024,
});

// Map of user_id → WebSocket connection
const clients = new Map<string, WebSocket>();

// Rate limiting
const messageCount = new Map<string, number>();
const RATE_LIMIT = 10;
const RATE_WINDOW_MS = 5000;

function isRateLimited(userId: string): boolean {
  const count = messageCount.get(userId) || 0;
  if (count >= RATE_LIMIT) return true;
  messageCount.set(userId, count + 1);
  return false;
}

setInterval(() => {
  messageCount.clear();
}, RATE_WINDOW_MS);

server.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});

// ── Helpers ────────────────────────────────────────────────

function send(ws: WebSocket, data: object) {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(data));
  }
}

function sendError(ws: WebSocket, message: string) {
  send(ws, { type: 'error', message });
}

async function findExistingConversation(
  userA: string,
  userB: string
): Promise<string | null> {
  const { data } = await supabase
    .from('conversation_members')
    .select('conversation_id')
    .eq('user_id', userA);

  if (!data) return null;

  const conversationIds = data.map((r) => r.conversation_id);

  for (const convId of conversationIds) {
    const { data: members } = await supabase
      .from('conversation_members')
      .select('user_id')
      .eq('conversation_id', convId)
      .eq('user_id', userB);

    if (members && members.length > 0) return convId;
  }

  return null;
}

// ── WebSocket connection ───────────────────────────────────

wss.on('connection', (ws, req) => {
  let userId: string | null = null;
  let authenticated = false;

  // Auth timeout — if no auth message in 10 seconds, disconnect
  const authTimeout = setTimeout(() => {
    if (!authenticated) {
      ws.close(1008, 'Authentication timeout');
    }
  }, 10000);

  ws.on('message', async (raw) => {
    let msg: any;

    try {
      msg = JSON.parse(raw.toString());
    } catch {
      sendError(ws, 'Invalid JSON');
      return;
    }

    if (!msg.type) {
      sendError(ws, 'Missing message type');
      return;
    }

    // ── Handle: auth — must be first message ──────────────
    if (msg.type === 'auth') {
      if (!msg.token) {
        ws.close(1008, 'No token provided');
        return;
      }

      const { data, error } = await supabase.auth.getUser(msg.token);

      if (error || !data.user) {
        ws.close(1008, 'Invalid token');
        return;
      }

      userId = data.user.id;
      authenticated = true;
      clearTimeout(authTimeout);
      clients.set(userId, ws);

      console.log(`User connected: ${userId}`);
      send(ws, { type: 'connected', user_id: userId });
      return;
    }

    // ── All other messages require auth ───────────────────
    if (!authenticated || !userId) {
      ws.close(1008, 'Not authenticated');
      return;
    }

    // Rate limit check
    if (isRateLimited(userId)) {
      sendError(ws, 'Rate limit exceeded — slow down');
      return;
    }

    // ── Handle: create_conversation ────────────────────────
    if (msg.type === 'create_conversation') {
      if (!msg.with_user_id) {
        sendError(ws, 'Missing with_user_id');
        return;
      }

      try {
        const existing = await findExistingConversation(
          userId,
          msg.with_user_id
        );

        if (existing) {
          send(ws, { type: 'conversation_created', conversation_id: existing });
          return;
        }

        const { data: conv, error: convError } = await supabase
          .from('conversations')
          .insert({})
          .select()
          .single();

        if (convError || !conv) {
          sendError(ws, 'Failed to create conversation');
          return;
        }

        await supabase.from('conversation_members').insert([
          { conversation_id: conv.id, user_id: userId },
          { conversation_id: conv.id, user_id: msg.with_user_id },
        ]);

        send(ws, { type: 'conversation_created', conversation_id: conv.id });
      } catch (err) {
        console.error('create_conversation error:', err);
        sendError(ws, 'Server error');
      }
    }

    // ── Handle: group_message ──────────────────────────────
    else if (msg.type === 'group_message') {
      if (!msg.group_id || !msg.content) {
        sendError(ws, 'Missing group_id or content');
        return;
      }

      const content = msg.content.toString().replace(/<[^>]*>/g, '').slice(0, 2000);

      try {
        const { error: insertError } = await supabase
          .from('group_messages')
          .insert({
            group_id: msg.group_id,
            sender_id: userId,
            content,
          });

        if (insertError) {
          sendError(ws, 'Failed to save message');
          return;
        }

        const payload = {
          type: 'group_message',
          group_id: msg.group_id,
          sender_id: userId,
          content,
          created_at: new Date().toISOString(),
        };

        clients.forEach((client, id) => {
          if (id !== userId) send(client, payload);
        });
      } catch (err) {
        console.error('group_message error:', err);
        sendError(ws, 'Server error');
      }
    }

    // ── Handle: private_message ────────────────────────────
    else if (msg.type === 'private_message') {
      if (!msg.conversation_id || !msg.encrypted_content) {
        sendError(ws, 'Missing conversation_id or encrypted_content');
        return;
      }

      if (msg.encrypted_content.toString().length > 10000) {
        sendError(ws, 'Message too large');
        return;
      }

      try {
        const { data: membership } = await supabase
          .from('conversation_members')
          .select('user_id')
          .eq('conversation_id', msg.conversation_id)
          .eq('user_id', userId)
          .single();

        if (!membership) {
          sendError(ws, 'Not a member of this conversation');
          return;
        }

        const { error: insertError } = await supabase
          .from('messages')
          .insert({
            conversation_id: msg.conversation_id,
            sender_id: userId,
            encrypted_content: msg.encrypted_content,
          });

        if (insertError) {
          sendError(ws, 'Failed to save message');
          return;
        }

        const { data: members } = await supabase
          .from('conversation_members')
          .select('user_id')
          .eq('conversation_id', msg.conversation_id)
          .neq('user_id', userId);

        if (!members || members.length === 0) return;

        const recipientId = members[0].user_id;
        const recipientWs = clients.get(recipientId);

        const payload = {
          type: 'private_message',
          conversation_id: msg.conversation_id,
          sender_id: userId,
          encrypted_content: msg.encrypted_content,
          created_at: new Date().toISOString(),
        };

        if (recipientWs) send(recipientWs, payload);

        send(ws, {
          type: 'message_sent',
          conversation_id: msg.conversation_id,
        });
      } catch (err) {
        console.error('private_message error:', err);
        sendError(ws, 'Server error');
      }
    }

    // ── Unknown message type ───────────────────────────────
    else {
      sendError(ws, `Unknown message type: ${msg.type}`);
    }
  });

  ws.on('close', () => {
    if (userId) {
      clients.delete(userId);
      messageCount.delete(userId);
      console.log(`User disconnected: ${userId}`);
    }
  });

  ws.on('error', (err) => {
    console.error('WebSocket error:', err);
    if (userId) clients.delete(userId);
  });
});
