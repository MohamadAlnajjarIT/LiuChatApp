import { Router, Request, Response } from 'express';
import { supabase } from './index';

const router = Router();


// ── Middleware — verify JWT on all API routes ──────────────
async function requireAuth(req: Request, res: Response, next: Function) {
  const token = req.headers['authorization']?.split(' ')[1];

  if (!token) {
    res.status(401).json({ error: 'No token provided' });
    return;
  }

  const { data, error } = await supabase.auth.getUser(token);

  if (error || !data.user) {
    res.status(401).json({ error: 'Invalid token' });
    return;
  }

  (req as any).userId = data.user.id;
  next();
}

// ── GET /majors ────────────────────────────────────────────
router.get('/majors', requireAuth, async (req: Request, res: Response) => {
  try {
    const { data, error } = await supabase
      .from('majors')
      .select('id, name, school')
      .order('name');

    if (error) throw error;
    res.json(data);
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch majors' });
  }
});

// ── GET /majors/:id/groups ─────────────────────────────────
router.get('/majors/:id/groups', requireAuth, async (req: Request, res: Response) => {
  try {
    // get course ids for this major
    const { data: majorCourses } = await supabase
      .from('major_courses')
      .select('course_id')
      .eq('major_id', req.params.id);

    const courseIds = majorCourses?.map(r => r.course_id) || [];

    // get general group for this major
    const { data: generalGroups } = await supabase
      .from('groups')
      .select('id, name, is_general')
      .eq('major_id', req.params.id)
      .eq('is_general', true);

    // get course groups
    const { data: courseGroups } = await supabase
      .from('groups')
      .select('id, name, is_general')
      .in('course_id', courseIds)
      .eq('is_general', false);

    const all = [...(generalGroups || []), ...(courseGroups || [])];
    res.json(all);
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch groups' });
  }
});

// ── GET /groups/:id/messages ───────────────────────────────
router.get('/groups/:id/messages', requireAuth, async (req: Request, res: Response) => {
  try {
    const limit = parseInt(req.query.limit as string) || 50;
    const offset = parseInt(req.query.offset as string) || 0;

    const { data, error } = await supabase
      .from('group_messages')
      .select('id, content, sender_id, created_at, profiles(username)')
      .eq('group_id', req.params.id)
      .order('created_at', { ascending: false })
      .range(offset, offset + limit - 1);

    if (error) throw error;
    res.json(data);
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch messages' });
  }
});

// ── GET /conversations/:id/messages ───────────────────────
router.get('/conversations/:id/messages', requireAuth, async (req: Request, res: Response) => {
  const userId = (req as any).userId;

  try {
    // Verify user is a member of this conversation
    const { data: membership } = await supabase
      .from('conversation_members')
      .select('user_id')
      .eq('conversation_id', req.params.id)
      .eq('user_id', userId)
      .single();

    if (!membership) {
      res.status(403).json({ error: 'Not a member of this conversation' });
      return;
    }

    const limit = parseInt(req.query.limit as string) || 50;
    const offset = parseInt(req.query.offset as string) || 0;

    const { data, error } = await supabase
      .from('messages')
      .select('id, encrypted_content, sender_id, created_at')
      .eq('conversation_id', req.params.id)
      .order('created_at', { ascending: false })
      .range(offset, offset + limit - 1);

    if (error) throw error;
    res.json(data);
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch messages' });
  }
});

// ── POST /conversations ────────────────────────────────────
router.post('/conversations', requireAuth, async (req: Request, res: Response) => {
  const userId = (req as any).userId;
  const { with_user_id } = req.body;

  if (!with_user_id) {
    res.status(400).json({ error: 'Missing with_user_id' });
    return;
  }

  try {
    // Check if conversation already exists
    const { data: existing } = await supabase
      .from('conversation_members')
      .select('conversation_id')
      .eq('user_id', userId);

    if (existing) {
      for (const row of existing) {
        const { data: match } = await supabase
          .from('conversation_members')
          .select('user_id')
          .eq('conversation_id', row.conversation_id)
          .eq('user_id', with_user_id);

        if (match && match.length > 0) {
          res.json({ conversation_id: row.conversation_id, created: false });
          return;
        }
      }
    }

    // Create new conversation
    const { data: conv, error: convError } = await supabase
      .from('conversations')
      .insert({})
      .select()
      .single();

    if (convError || !conv) throw convError;

    await supabase.from('conversation_members').insert([
      { conversation_id: conv.id, user_id: userId },
      { conversation_id: conv.id, user_id: with_user_id },
    ]);

    res.status(201).json({ conversation_id: conv.id, created: true });
  } catch (err) {
    res.status(500).json({ error: 'Failed to create conversation' });
  }
});

// ── GET /users/:id ─────────────────────────────────────────
router.get('/users/:id', requireAuth, async (req: Request, res: Response) => {
  try {
    const { data, error } = await supabase
      .from('profiles')
      .select('id, username, email, public_key, major_id')
      .eq('id', req.params.id)
      .single();

    if (error || !data) {
      res.status(404).json({ error: 'User not found' });
      return;
    }

    res.json(data);
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch user' });
  }
});

export default router;
