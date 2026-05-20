# LIUCHAT — Full Project Documentation

> Lebanese International University Chat Application  
> Backend: Khaled Hammoud  
> Frontend: Mohammad Najjar
> Course Project — Spring 2026

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Tech Stack](#2-tech-stack)
3. [Architecture](#3-architecture)
4. [Database Schema](#4-database-schema)
5. [Authentication & OTP](#5-authentication--otp)
6. [WebSocket Server](#6-websocket-server)
7. [REST API](#7-rest-api)
8. [Security Features](#8-security-features)
9. [E2E Encryption](#9-e2e-encryption)
10. [Flutter Screens](#10-flutter-screens)
11. [Hosting & Deployment](#11-hosting--deployment)
12. [Environment Variables](#12-environment-variables)
13. [How to Test](#13-how-to-test)
14. [Changes Log](#14-changes-log)

---

## 1. Project Overview

LIUCHAT is a real-time mobile chat application exclusively for Lebanese International University (LIU) students. Features:

- Group chats organized by School → Major → Course
- Private messaging between students (E2E encrypted)
- OTP-based login via university email only — no passwords
- Any student can join any group freely
- Alumni supported — same LIU email domain

Only `@students.liu.edu.lb` emails can register. Enforced at database level via PostgreSQL trigger — not just frontend validation.

---

## 2. Tech Stack

| Layer | Technology | Cost |
|---|---|---|
| Mobile Frontend | Flutter / Dart | Free |
| Backend / WebSockets | Node.js + TypeScript | Free |
| Database + Auth | Supabase (PostgreSQL + GoTrue) | Free |
| OTP Email Delivery | Gmail SMTP via Supabase | Free |
| Hosting (Backend) | Render.com | Free |
| Uptime Monitoring | UptimeRobot | Free |
| Keep-Alive | GitHub Actions | Free |

**Total cost: $0**

---

## 3. Architecture

```
Flutter App
    │
    ├── HTTPS ──────────────► Supabase
    │                          ├── PostgreSQL (all data)
    │                          ├── GoTrue (auth + OTP)
    │                          └── JWT tokens
    │
    └── WebSocket (wss://) ──► Node.js Server on Render
                                ├── JWT verification
                                ├── Group message broadcast
                                ├── Private message routing
                                └── REST API (Express)
```

### Message Flow — Group Chat
```
Flutter sends JSON via WebSocket
        ↓
Node.js server saves to group_messages table
        ↓
Broadcasts to all online users
        ↓
Offline users load history from Supabase on next open
```

### Message Flow — Private Chat (E2E Encrypted)
```
Flutter encrypts message with recipient's public key (X25519 + AES-256-GCM)
        ↓
Sends encrypted blob via WebSocket
        ↓
Server verifies sender is conversation member
        ↓
Saves encrypted_content to messages table (never decrypts)
        ↓
Forwards to recipient if online
        ↓
Recipient's Flutter decrypts with their private key
```

---

## 4. Database Schema

### Tables Overview

| Table | Purpose |
|---|---|
| `majors` | Academic majors organized by school |
| `profiles` | User info + public encryption key |
| `groups` | Course chatrooms per major |
| `group_members` | Junction: users ↔ groups |
| `group_messages` | Plain text group messages |
| `conversations` | Private chat container |
| `conversation_members` | Junction: two users ↔ conversation |
| `messages` | E2E encrypted private messages |

### Full SQL

```sql
-- Majors
create table majors (
  id uuid default gen_random_uuid() primary key,
  name text unique not null,
  description text,
  school text,
  created_at timestamptz default now()
);

-- Profiles (auto-created on signup via trigger)
create table profiles (
  id uuid references auth.users(id) on delete cascade primary key,
  username text unique not null,
  email text unique not null,
  public_key text,
  major_id uuid references majors(id) on delete set null,
  created_at timestamptz default now()
);

-- Groups (course chatrooms)
create table groups (
  id uuid default gen_random_uuid() primary key,
  name text unique not null,
  description text,
  major_id uuid references majors(id) on delete cascade,
  is_general boolean default false,
  created_at timestamptz default now()
);

-- Group members
create table group_members (
  id uuid default gen_random_uuid() primary key,
  group_id uuid references groups(id) on delete cascade not null,
  user_id uuid references profiles(id) on delete cascade not null,
  joined_at timestamptz default now(),
  unique(group_id, user_id)
);

-- Group messages (plain text, not encrypted)
create table group_messages (
  id uuid default gen_random_uuid() primary key,
  group_id uuid references groups(id) on delete cascade not null,
  sender_id uuid references profiles(id) on delete cascade not null,
  content text not null,
  created_at timestamptz default now()
);

-- Conversations
create table conversations (
  id uuid default gen_random_uuid() primary key,
  created_at timestamptz default now()
);

-- Conversation members (exactly 2 per conversation)
create table conversation_members (
  id uuid default gen_random_uuid() primary key,
  conversation_id uuid references conversations(id) on delete cascade not null,
  user_id uuid references profiles(id) on delete cascade not null,
  unique(conversation_id, user_id)
);

-- Private messages (E2E encrypted — server never decrypts)
create table messages (
  id uuid default gen_random_uuid() primary key,
  conversation_id uuid references conversations(id) on delete cascade not null,
  sender_id uuid references profiles(id) on delete cascade not null,
  encrypted_content text not null,
  created_at timestamptz default now()
);
```

### Triggers

#### Email domain enforcement (BEFORE INSERT)
Runs before any user is created. Rejects non-LIU emails at database level.

```sql
create or replace function enforce_liu_email()
returns trigger as $$
begin
  if new.email not like '%@students.liu.edu.lb' then
    raise exception 'Only LIU student emails are allowed to sign up';
  end if;
  return new;
end;
$$ language plpgsql security definer;

create or replace trigger check_liu_email
  before insert on auth.users
  for each row
  execute function enforce_liu_email();
```

#### Auto profile creation (AFTER INSERT)
Runs after user is created. Auto-generates username from email prefix.
`john.doe@students.liu.edu.lb` → username: `john.doe`

```sql
create or replace function handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, email, username)
  values (
    new.id,
    new.email,
    split_part(new.email, '@', 1)
  );
  return new;
end;
$$ language plpgsql security definer;

create or replace trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function handle_new_user();
```

### RLS Policies

Row Level Security is enabled on all tables. Key policies:

```sql
-- Profiles: anyone logged in can read, only owner can update
create policy "profiles are viewable by authenticated users"
on profiles for select to authenticated using (true);

create policy "users can update own profile"
on profiles for update to authenticated using (auth.uid() = id);

-- Majors: anyone logged in can read
create policy "majors are viewable by authenticated users"
on majors for select to authenticated using (true);

-- Groups: anyone logged in can read
create policy "groups are viewable by authenticated users"
on groups for select to authenticated using (true);

-- Group members: read all, insert/delete own only
create policy "group_members are viewable by authenticated users"
on group_members for select to authenticated using (true);

create policy "users can join groups"
on group_members for insert to authenticated
with check (auth.uid() = user_id);

create policy "users can leave groups"
on group_members for delete to authenticated
using (auth.uid() = user_id);

-- Group messages: anyone can read, only sender can insert
create policy "group messages are viewable by authenticated users"
on group_messages for select to authenticated using (true);

create policy "users can send group messages"
on group_messages for insert to authenticated
with check (auth.uid() = sender_id);

-- Conversations: only members can see their own
create policy "users can view their own conversations"
on conversations for select to authenticated
using (
  exists (
    select 1 from conversation_members
    where conversation_members.conversation_id = id
    and conversation_members.user_id = auth.uid()
  )
);

create policy "authenticated users can create conversations"
on conversations for insert to authenticated with check (true);

-- Conversation members
create policy "users can view their own conversation memberships"
on conversation_members for select to authenticated
using (auth.uid() = user_id);

create policy "users can create conversation memberships"
on conversation_members for insert to authenticated
with check (auth.uid() = user_id);

-- Messages: only conversation members can read/write
create policy "users can view their own messages"
on messages for select to authenticated
using (
  exists (
    select 1 from conversation_members
    where conversation_members.conversation_id = messages.conversation_id
    and conversation_members.user_id = auth.uid()
  )
);

create policy "users can send private messages"
on messages for insert to authenticated
with check (
  exists (
    select 1 from conversation_members
    where conversation_members.conversation_id = messages.conversation_id
    and conversation_members.user_id = auth.uid()
  )
);
```

### Data Inserted

- **56 majors** across 5 schools with `school` column
- **715 groups** = 659 courses + 56 general chatrooms (one per major)
- Inserted via SQL script in one shot

---

## 5. Authentication & OTP

**Flow — OTP only, no passwords:**

```
1. User enters LIU email in Flutter
2. Flutter calls supabase.auth.signInWithOtp(email: email)
3. Supabase sends 6-digit OTP via Gmail SMTP
4. User enters code in Flutter
5. Flutter calls supabase.auth.verifyOTP(email, token, type: OtpType.email)
6. Supabase returns JWT access token + refresh token
7. Flutter stores session — user stays logged in until logout
8. On app open: checks currentSession — if exists, skip login
```

**Gmail SMTP settings in Supabase:**
```
Host: smtp.gmail.com
Port: 465
Username: [gmail address]
Password: Gmail App Password (Settings → Security → 2FA → App Passwords)
Sender name: LIUCHAT
Minimum interval: 60 seconds
```

**Email template (Magic Link template in Supabase dashboard):**
```html
<h2>Your LIUCHAT Login Code</h2>
<p>Enter this 6-digit code in the app:</p>
<h1 style="letter-spacing: 8px; font-size: 36px;">{{ .Token }}</h1>
<p>This code expires in 10 minutes.</p>
<p>If you didn't request this, ignore this email.</p>
```

**Important Supabase settings:**
- Confirm email: **OFF** (causes magic link instead of OTP if ON)
- Site URL: `https://liuchat-server.onrender.com`

---

## 6. WebSocket Server

**File:** `src/index.ts`
**Live URL:** `wss://liuchat-server.onrender.com`

### Connection & Auth

Flutter connects then immediately sends auth message:
```json
{ "type": "auth", "token": "JWT_TOKEN" }
```

Server verifies JWT with Supabase. If invalid → closes connection.
If valid → responds with:
```json
{ "type": "connected", "user_id": "uuid" }
```

10-second auth timeout — if no auth message received, server disconnects.

### Message Types (Flutter → Server)

**Auth (must be first):**
```json
{ "type": "auth", "token": "JWT_TOKEN" }
```

**Group message:**
```json
{
  "type": "group_message",
  "group_id": "uuid",
  "content": "message text here"
}
```

**Private message (encrypted):**
```json
{
  "type": "private_message",
  "conversation_id": "uuid",
  "encrypted_content": "base64_encrypted_string"
}
```

**Create conversation (before first private message):**
```json
{ "type": "create_conversation", "with_user_id": "uuid" }
```

### Server Responses (Server → Flutter)

```json
{ "type": "connected", "user_id": "uuid" }
{ "type": "conversation_created", "conversation_id": "uuid" }
{ "type": "message_sent", "conversation_id": "uuid" }
{ "type": "group_message", "group_id": "uuid", "sender_id": "uuid", "content": "text", "created_at": "iso" }
{ "type": "private_message", "conversation_id": "uuid", "sender_id": "uuid", "encrypted_content": "base64", "created_at": "iso" }
{ "type": "error", "message": "description" }
```

### Full Server Code

```typescript
// src/index.ts
import { WebSocketServer, WebSocket } from 'ws';
import http from 'http';
import express from 'express';
import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
import apiRouter from './api';

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
const wss = new WebSocketServer({ server, maxPayload: 16 * 1024 });

const clients = new Map<string, WebSocket>();
const messageCount = new Map<string, number>();
const RATE_LIMIT = 10;
const RATE_WINDOW_MS = 5000;

function isRateLimited(userId: string): boolean {
  const count = messageCount.get(userId) || 0;
  if (count >= RATE_LIMIT) return true;
  messageCount.set(userId, count + 1);
  return false;
}

setInterval(() => messageCount.clear(), RATE_WINDOW_MS);

server.listen(PORT, () => console.log(`Server running on port ${PORT}`));

function send(ws: WebSocket, data: object) {
  if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(data));
}

function sendError(ws: WebSocket, message: string) {
  send(ws, { type: 'error', message });
}

async function findExistingConversation(userA: string, userB: string): Promise<string | null> {
  const { data } = await supabase
    .from('conversation_members')
    .select('conversation_id')
    .eq('user_id', userA);
  if (!data) return null;
  for (const row of data) {
    const { data: members } = await supabase
      .from('conversation_members')
      .select('user_id')
      .eq('conversation_id', row.conversation_id)
      .eq('user_id', userB);
    if (members && members.length > 0) return row.conversation_id;
  }
  return null;
}

wss.on('connection', (ws, req) => {
  let userId: string | null = null;
  let authenticated = false;

  const authTimeout = setTimeout(() => {
    if (!authenticated) ws.close(1008, 'Authentication timeout');
  }, 10000);

  ws.on('message', async (raw) => {
    let msg: any;
    try { msg = JSON.parse(raw.toString()); }
    catch { sendError(ws, 'Invalid JSON'); return; }

    if (!msg.type) { sendError(ws, 'Missing message type'); return; }

    // Auth message
    if (msg.type === 'auth') {
      if (!msg.token) { ws.close(1008, 'No token provided'); return; }
      const { data, error } = await supabase.auth.getUser(msg.token);
      if (error || !data.user) { ws.close(1008, 'Invalid token'); return; }
      userId = data.user.id;
      authenticated = true;
      clearTimeout(authTimeout);
      clients.set(userId, ws);
      send(ws, { type: 'connected', user_id: userId });
      return;
    }

    if (!authenticated || !userId) { ws.close(1008, 'Not authenticated'); return; }
    if (isRateLimited(userId)) { sendError(ws, 'Rate limit exceeded'); return; }

    // Create conversation
    if (msg.type === 'create_conversation') {
      if (!msg.with_user_id) { sendError(ws, 'Missing with_user_id'); return; }
      try {
        const existing = await findExistingConversation(userId, msg.with_user_id);
        if (existing) { send(ws, { type: 'conversation_created', conversation_id: existing }); return; }
        const { data: conv } = await supabase.from('conversations').insert({}).select().single();
        if (!conv) { sendError(ws, 'Failed to create conversation'); return; }
        await supabase.from('conversation_members').insert([
          { conversation_id: conv.id, user_id: userId },
          { conversation_id: conv.id, user_id: msg.with_user_id },
        ]);
        send(ws, { type: 'conversation_created', conversation_id: conv.id });
      } catch { sendError(ws, 'Server error'); }
    }

    // Group message
    else if (msg.type === 'group_message') {
      if (!msg.group_id || !msg.content) { sendError(ws, 'Missing fields'); return; }
      const content = msg.content.toString().replace(/<[^>]*>/g, '').slice(0, 2000);
      try {
        await supabase.from('group_messages').insert({ group_id: msg.group_id, sender_id: userId, content });
        const payload = { type: 'group_message', group_id: msg.group_id, sender_id: userId, content, created_at: new Date().toISOString() };
        clients.forEach((client, id) => { if (id !== userId) send(client, payload); });
      } catch { sendError(ws, 'Server error'); }
    }

    // Private message
    else if (msg.type === 'private_message') {
      if (!msg.conversation_id || !msg.encrypted_content) { sendError(ws, 'Missing fields'); return; }
      if (msg.encrypted_content.toString().length > 10000) { sendError(ws, 'Message too large'); return; }
      try {
        const { data: membership } = await supabase
          .from('conversation_members').select('user_id')
          .eq('conversation_id', msg.conversation_id).eq('user_id', userId).single();
        if (!membership) { sendError(ws, 'Not a member of this conversation'); return; }
        await supabase.from('messages').insert({
          conversation_id: msg.conversation_id, sender_id: userId, encrypted_content: msg.encrypted_content
        });
        const { data: members } = await supabase
          .from('conversation_members').select('user_id')
          .eq('conversation_id', msg.conversation_id).neq('user_id', userId);
        if (!members || members.length === 0) return;
        const recipientWs = clients.get(members[0].user_id);
        const payload = { type: 'private_message', conversation_id: msg.conversation_id, sender_id: userId, encrypted_content: msg.encrypted_content, created_at: new Date().toISOString() };
        if (recipientWs) send(recipientWs, payload);
        send(ws, { type: 'message_sent', conversation_id: msg.conversation_id });
      } catch { sendError(ws, 'Server error'); }
    }

    else { sendError(ws, `Unknown message type: ${msg.type}`); }
  });

  ws.on('close', () => {
    if (userId) { clients.delete(userId); messageCount.delete(userId); }
  });

  ws.on('error', (err) => {
    console.error('WebSocket error:', err);
    if (userId) clients.delete(userId);
  });
});
```

---

## 7. REST API

**Base URL:** `https://liuchat-server.onrender.com/api`
**Auth:** All endpoints require `Authorization: Bearer JWT_TOKEN` header

### Endpoints

| Method | Endpoint | Description |
|---|---|---|
| GET | `/api/majors` | All majors with school |
| GET | `/api/majors/:id/groups` | Groups for a major |
| GET | `/api/groups/:id/messages` | Group message history |
| GET | `/api/conversations/:id/messages` | Private message history |
| POST | `/api/conversations` | Create/get conversation |
| GET | `/api/users/:id` | User profile |

### Example Requests

```bash
# Get all majors
curl https://liuchat-server.onrender.com/api/majors \
  -H "Authorization: Bearer JWT_TOKEN"

# Get groups for a major
curl https://liuchat-server.onrender.com/api/majors/UUID/groups \
  -H "Authorization: Bearer JWT_TOKEN"

# Get group message history (with pagination)
curl "https://liuchat-server.onrender.com/api/groups/UUID/messages?limit=50&offset=0" \
  -H "Authorization: Bearer JWT_TOKEN"

# Create conversation
curl -X POST https://liuchat-server.onrender.com/api/conversations \
  -H "Authorization: Bearer JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"with_user_id": "UUID"}'

# Get user profile
curl https://liuchat-server.onrender.com/api/users/UUID \
  -H "Authorization: Bearer JWT_TOKEN"
```

---

## 8. Security Features

| Feature | How |
|---|---|
| Email domain enforcement | PostgreSQL BEFORE trigger — rejects at DB level |
| JWT verification | Every WebSocket connection + every API request |
| Row Level Security | All 8 tables — users only access their own data |
| Rate limiting | Max 10 messages per 5 seconds per user |
| Input sanitization | HTML stripped, max 2000 characters |
| Membership verification | Server checks before routing private messages |
| Payload size limit | 16KB WebSocket frame, 10KB encrypted content |
| Auth timeout | 10 seconds to send auth message or disconnect |
| No plaintext private messages | Server stores and forwards only encrypted blobs |
| Max connections per IP | 3 connections max |

---

## 9. E2E Encryption

**Algorithm: X25519 key exchange + AES-256-GCM encryption**

This is the same approach used by Signal and WhatsApp.

### How it works

```
On first login:
  Flutter generates X25519 key pair
  Private key → stored on device in flutter_secure_storage (never sent)
  Public key → saved to profiles.public_key in Supabase

Sending a message:
  Fetch recipient's public key from Supabase
  X25519 key exchange → shared secret
  AES-256-GCM encrypt with shared secret
  Send base64 blob via WebSocket

Receiving a message:
  Fetch sender's public key from Supabase
  X25519 key exchange → same shared secret
  AES-256-GCM decrypt
  Show plaintext in UI
```

### Encryption Service (`lib/services/encryption_service.dart`)

```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../main.dart';

class EncryptionService {
  static const _storage = FlutterSecureStorage();
  static const _privateKeyStorageKey = 'liuchat_private_key';

  static Future<void> initializeKeys() async {
    final existingKey = await _storage.read(key: _privateKeyStorageKey);
    final profile = await supabase
        .from('profiles').select('public_key')
        .eq('id', supabase.auth.currentUser!.id).single();
    if (existingKey != null && profile['public_key'] != null) return;

    final algorithm = X25519();
    final keyPair = await algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();

    await _storage.write(key: _privateKeyStorageKey, value: base64Encode(privateKeyBytes));
    await supabase.from('profiles').update({
      'public_key': base64Encode(publicKey.bytes),
    }).eq('id', supabase.auth.currentUser!.id);
  }

  static Future<String> encryptMessage(String message, String recipientPublicKeyBase64) async {
    final privateKeyBase64 = await _storage.read(key: _privateKeyStorageKey);
    final privateKeyBytes = base64Decode(privateKeyBase64!);
    final recipientPublicKey = SimplePublicKey(base64Decode(recipientPublicKeyBase64), type: KeyPairType.x25519);

    final x25519 = X25519();
    final ourKeyPair = await x25519.newKeyPairFromSeed(privateKeyBytes);
    final sharedSecret = await x25519.sharedSecretKey(keyPair: ourKeyPair, remotePublicKey: recipientPublicKey);

    final aesGcm = AesGcm.with256bits();
    final secretKey = await aesGcm.newSecretKeyFromBytes(await sharedSecret.extractBytes());
    final secretBox = await aesGcm.encryptString(message, secretKey: secretKey);

    final combined = Uint8List.fromList([...secretBox.nonce, ...secretBox.cipherText, ...secretBox.mac.bytes]);
    return base64Encode(combined);
  }

  static Future<String> decryptMessage(String encryptedBase64, String senderPublicKeyBase64) async {
    final combined = base64Decode(encryptedBase64);
    final nonce = combined.sublist(0, 12);
    final mac = combined.sublist(combined.length - 16);
    final cipherText = combined.sublist(12, combined.length - 16);

    final privateKeyBase64 = await _storage.read(key: _privateKeyStorageKey);
    final privateKeyBytes = base64Decode(privateKeyBase64!);
    final senderPublicKey = SimplePublicKey(base64Decode(senderPublicKeyBase64), type: KeyPairType.x25519);

    final x25519 = X25519();
    final ourKeyPair = await x25519.newKeyPairFromSeed(privateKeyBytes);
    final sharedSecret = await x25519.sharedSecretKey(keyPair: ourKeyPair, remotePublicKey: senderPublicKey);

    final aesGcm = AesGcm.with256bits();
    final secretKey = await aesGcm.newSecretKeyFromBytes(await sharedSecret.extractBytes());
    final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(mac));
    return await aesGcm.decryptString(secretBox, secretKey: secretKey);
  }

  static Future<String?> getPublicKey(String userId) async {
    try {
      final profile = await supabase.from('profiles').select('public_key').eq('id', userId).single();
      return profile['public_key'] as String?;
    } catch (e) { return null; }
  }

  static Future<void> clearKeys() async {
    await _storage.delete(key: _privateKeyStorageKey);
  }
}
```

---

## 10. Flutter Screens

### File Structure
```
lib/
├── main.dart                    ← Supabase init, auto-login if session exists
├── theme/
│   └── app_theme.dart           ← Colors and themes (unchanged)
├── services/
│   └── encryption_service.dart  ← X25519 + AES-256-GCM encryption
└── screens/
    ├── login_screen.dart         ← Email only, sends OTP
    ├── register_screen.dart      ← Email only, sends OTP (same flow)
    ├── verify_screen.dart        ← Verifies OTP, initializes encryption keys
    ├── home_screen.dart          ← Schools list + messages icon
    ├── majors_screen.dart        ← Fetches from Supabase, filters by school
    ├── major_options_screen.dart ← General chat or courses, passes majorId
    ├── courses_screen.dart       ← Fetches courses from Supabase by majorId
    ├── chat_screen.dart          ← Group chat with WebSocket
    ├── general_chat_screen.dart  ← General group chat with WebSocket
    ├── conversations_screen.dart ← Lists all private chats
    ├── user_search_screen.dart   ← Search users by username
    └── private_chat_screen.dart  ← E2E encrypted private messaging
```

### pubspec.yaml Dependencies
```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_screenutil: ^5.9.0
  cupertino_icons: ^1.0.8
  supabase_flutter: ^2.0.0
  web_socket_channel: ^3.0.0
  flutter_secure_storage: ^9.0.0
  cryptography: ^2.5.0
```

### Key Design Decisions

- **Login = Register** — same OTP flow for both. If email exists, logs in. If not, creates account.
- **Username** — auto-generated from email prefix. `john.doe@students.liu.edu.lb` → `john.doe`
- **Stay logged in** — `main.dart` checks `currentSession` on launch. No re-login needed.
- **Dark/light mode** — Flutter's `MediaQuery.platformBrightness` detects device setting automatically.
- **Group messages** — plain text, no encryption needed.
- **Private messages** — always encrypted before leaving device.

---

## 11. Hosting & Deployment

### Backend — Render.com
- Free tier
- Docker-based deployment via `Dockerfile`
- Auto-deploys on every GitHub push to `main`
- URL: `https://liuchat-server.onrender.com`

### Dockerfile
```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npx tsc
EXPOSE 8080
CMD ["node", "dist/index.js"]
```

### Keep-Alive — GitHub Actions
Pings server every 10 minutes so Render free tier never sleeps.

```yaml
# .github/workflows/ping.yml
name: Keep Render Alive
on:
  schedule:
    - cron: '*/10 * * * *'
  workflow_dispatch:
jobs:
  ping:
    runs-on: ubuntu-latest
    steps:
      - name: Ping server
        run: curl https://liuchat-server.onrender.com
```

### Monitoring — UptimeRobot
Monitors every 5 minutes. Sends email alert if server goes down.

### Database — Supabase Free Tier
- 500MB storage, 50,000 monthly active users
- **Pauses after 1 week of inactivity** — resume manually from dashboard
- Project URL: `https://cxiiqwnlucgrnqhlahyb.supabase.co`

---

## 12. Environment Variables

### Node.js server `.env` (never commit to GitHub)
```env
SUPABASE_URL=https://cxiiqwnlucgrnqhlahyb.supabase.co
SUPABASE_SERVICE_KEY=your_service_role_key_here
PORT=8080
```

On Render: set in dashboard → Environment Variables.

### Flutter `main.dart`
```dart
await Supabase.initialize(
  url: 'https://cxiiqwnlucgrnqhlahyb.supabase.co',
  anonKey: 'your_anon_key_here',
);
```

**Key difference:**
- `SERVICE_KEY` → full DB access, bypasses RLS → backend only, never frontend
- `anonKey` → restricted access, respects RLS → safe for frontend

---

## 13. How to Test

### Step 1 — Test OTP email

Request OTP:
```bash
curl -X POST https://cxiiqwnlucgrnqhlahyb.supabase.co/auth/v1/otp \
  -H "apikey: YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"email": "youremail@students.liu.edu.lb"}'
```

Check email for 6-digit code, then verify:
```bash
curl -X POST https://cxiiqwnlucgrnqhlahyb.supabase.co/auth/v1/verify \
  -H "apikey: YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"email": "youremail@students.liu.edu.lb", "token": "123456", "type": "email"}'
```

You get back a JWT `access_token`. Copy it.

### Step 2 — Test REST API

```bash
# Test majors endpoint
curl https://liuchat-server.onrender.com/api/majors \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"

# Should return array of 56 majors with school names
```

### Step 3 — Test WebSocket (using wscat)

Install wscat:
```bash
npm install -g wscat
```

Connect:
```bash
wscat -c wss://liuchat-server.onrender.com
```

Once connected, send auth message:
```json
{"type":"auth","token":"YOUR_JWT_TOKEN"}
```

Should receive:
```json
{"type":"connected","user_id":"..."}
```

Send a group message:
```json
{"type":"group_message","group_id":"VALID_GROUP_UUID","content":"hello world"}
```

### Step 4 — Test Flutter app

1. mohammad builds APK with all updated files
2. Install on two devices
3. Register on both with different LIU emails
4. OTP arrives in email → enter code → logged in
5. Browse schools → majors → courses → open group chat
6. Send message on device 1 → appears on device 2
7. Go to messages icon → search for other user → open private chat
8. Send private message → encrypted on device 1, decrypted on device 2

### Step 5 — Verify encryption is working

In Supabase dashboard → Table Editor → `messages` table. The `encrypted_content` column should show base64 gibberish — never readable text. If you see plain text something is wrong.

---

## 14. Changes Log

Change
|---|---|
Created Supabase project |
Connected Resend SMTP (later replaced with Gmail) |
Built Node.js + TypeScript WebSocket server |
Deployed to Render, set up GitHub Actions keep-alive, UptimeRobot |
Hardened server: rate limiting, sanitization, membership verification, JWT auth via first message |
Built REST API with 6 endpoints using Express |
Switched SMTP from Resend to Gmail |
Fixed OTP email template to show 6-digit code |
Fixed all Flutter screens to connect to Supabase and WebSocket |
Tested full auth flow via curl — confirmed working |
Tested REST API — all endpoints returning correct data |
Built 3 new Flutter screens: ConversationsScreen, UserSearchScreen, PrivateChatScreen |
Built EncryptionService — X25519 + AES-256-GCM |
Rolled back to OTP-only auth (no password) |