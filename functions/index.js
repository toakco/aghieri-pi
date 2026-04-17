/**
 * Aghieri — Firebase Cloud Functions
 * TOAKCO LLC / DS-483 Capstone
 *
 * Functions:
 *   processInstruction  — parse uploaded file and extract tasks via Claude
 *   analyzePortfolio    — generate UI suggestions from interaction data
 *   rateLimit           — sliding window rate limiter (100 req/min per uid)
 *   checkIncompleteTasks — end-of-day: flag incomplete tasks for rescheduling
 */

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const Anthropic = require("@anthropic-ai/sdk");
const axios = require("axios");
const crypto = require("crypto");

admin.initializeApp();
const db = admin.firestore();

// ── OAuth config — client IDs are public, secrets live in Secret Manager ────
const SPOTIFY_CLIENT_ID = "a7a04450126d42e193f0482c1c075df1";
const NOTION_CLIENT_ID  = "345d872b-594c-8144-adf8-0037e7ef3f13";
const AGHIERI_WEB_ORIGIN = "https://aghieri-7a8ce.web.app";
const SPOTIFY_REDIRECT = `${AGHIERI_WEB_ORIGIN}/auth/spotify/callback`;
const NOTION_REDIRECT  = `${AGHIERI_WEB_ORIGIN}/auth/notion/callback`;
const SPOTIFY_SCOPES = [
  "user-read-private", "user-read-email",
  "user-read-playback-state", "user-modify-playback-state",
  "user-read-currently-playing", "playlist-read-private",
  "streaming",
].join(" ");

// ── Rate Limiter ─────────────────────────────────────────────────────────────
const RATE_LIMIT = 100;      // requests per window
const WINDOW_MS  = 60_000;   // 1 minute

exports.rateLimit = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Login required.");
  }
  const uid = context.auth.uid;
  const now = Date.now();
  const windowStart = now - WINDOW_MS;

  const ref = db.collection("rate_limits").doc(uid);
  const doc = await ref.get();

  let requests = doc.exists ? doc.data().requests || [] : [];
  // Keep only requests within the current window
  requests = requests.filter(ts => ts > windowStart);

  if (requests.length >= RATE_LIMIT) {
    throw new functions.https.HttpsError(
      "resource-exhausted",
      `Rate limit exceeded. Max ${RATE_LIMIT} requests per minute.`
    );
  }

  requests.push(now);
  await ref.set({ requests }, { merge: true });
  return { ok: true, remaining: RATE_LIMIT - requests.length };
});


// ── Process Instruction Upload ────────────────────────────────────────────────
exports.processInstruction = functions
  .runWith({ memory: "512MB", timeoutSeconds: 120, secrets: ["ANTHROPIC_KEY"] })
  .storage.object()
  .onFinalize(async (object) => {
    const filePath = object.name;
    const uid = filePath.split("/")[1];  // uploads/{uid}/{fileName}

    if (!filePath.startsWith("uploads/")) return;

    const bucket = admin.storage().bucket(object.bucket);
    const [fileContent] = await bucket.file(filePath).download();
    const text = fileContent.toString("utf-8");

    if (!text.trim()) return;

    const client = new Anthropic.default({
      apiKey: functions.config().anthropic?.key || process.env.ANTHROPIC_KEY,
    });

    let tasks = [];
    try {
      const resp = await client.messages.create({
        model: "claude-haiku-4-5-20251001",
        max_tokens: 2000,
        messages: [{
          role: "user",
          content: `Extract all actionable tasks from this document. Return JSON array: [{"title": "short title (under 6 words)", "steps": ["step 1", "step 2"], "estimated_minutes": 30}]. Only JSON.\n\n${text.slice(0, 6000)}`,
        }],
      });

      let content = resp.content[0].text.trim();
      if (content.startsWith("```")) {
        content = content.split("```")[1];
        if (content.startsWith("json")) content = content.slice(4);
      }
      tasks = JSON.parse(content);
    } catch (e) {
      console.error("Claude extraction error:", e);
      return;
    }

    // Write tasks to Firestore
    const batch = db.batch();
    for (const task of tasks) {
      const ref = db.collection("tasks").doc();
      batch.set(ref, {
        uid,
        title: task.title || "Untitled",
        steps: (task.steps || []).map((s, i) => ({ id: `s${i}`, text: s, completed: false })),
        color: null,       // App assigns color
        status: "pending",
        source: "upload",
        created_at: new Date().toISOString(),
        due_date: null,
        estimated_minutes: task.estimated_minutes || 60,
      });
    }
    await batch.commit();
    console.log(`Created ${tasks.length} tasks for user ${uid}`);
  });


// ── Analyze Portfolio & Generate Suggestions ──────────────────────────────────
exports.analyzePortfolio = functions
  .runWith({ secrets: ["ANTHROPIC_KEY"] })
  .https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Login required.");
  }

  const uid = context.auth.uid;

  // Fetch last 100 interactions — anonymized (no PII sent to Claude)
  const interactionsSnap = await db
    .collection("portfolio")
    .doc(uid)
    .collection("interactions")
    .orderBy("timestamp", "desc")
    .limit(100)
    .get();

  const interactions = interactionsSnap.docs.map(d => d.data());
  if (interactions.length < 10) {
    return { suggestions: [] };
  }

  // Aggregate pattern data
  const hourCounts = {};
  const typeCounts = {};
  for (const i of interactions) {
    const h = i.hour_of_day || 12;
    const t = i.type || "unknown";
    hourCounts[h] = (hourCounts[h] || 0) + 1;
    typeCounts[t] = (typeCounts[t] || 0) + 1;
  }

  const peakHour = Object.entries(hourCounts).sort(([,a],[,b]) => b-a)[0]?.[0] || 12;
  const topType  = Object.entries(typeCounts).sort(([,a],[,b]) => b-a)[0]?.[0] || "task";

  // Fetch user interests (non-PII)
  const userDoc = await db.collection("users").doc(uid).get();
  const interests = userDoc.exists ? (userDoc.data().interests || []) : [];

  const client = new Anthropic.default({
    apiKey: functions.config().anthropic?.key || process.env.ANTHROPIC_KEY,
  });

  // TRIBE v2 analysis framework applied here
  const prompt = `Analyze interaction patterns using TRIBE v2 framework.

Data:
- Peak activity hour: ${peakHour}:00
- Most common interaction: ${topType}
- Total interactions: ${interactions.length}
- User interests: ${interests.join(", ") || "not specified"}
- Type breakdown: ${JSON.stringify(typeCounts)}

Generate 1-2 short, practical UI suggestions for a calm ADHD productivity app.
Rules: no judgment, no performance framing, practical and specific.
Format: JSON array [{"suggestion": "...", "reason": "..."}]. Only JSON.`;

  try {
    const resp = await client.messages.create({
      model: "claude-sonnet-4-6",
      max_tokens: 600,
      messages: [{ role: "user", content: prompt }],
    });

    let content = resp.content[0].text.trim();
    if (content.startsWith("```")) {
      content = content.split("```")[1];
      if (content.startsWith("json")) content = content.slice(4);
    }
    const suggestions = JSON.parse(content);

    // Store suggestions in Firestore
    await db.collection("users").doc(uid).update({
      ui_suggestions: suggestions,
      suggestions_generated_at: new Date().toISOString(),
    });

    return { suggestions };
  } catch (e) {
    console.error("Portfolio analysis error:", e);
    return { suggestions: [] };
  }
});


// ── Voice Command Proxy (Claude) — bypasses CORS for web ────────────────────
exports.voiceCommand = functions
  .runWith({
    memory: "256MB",
    timeoutSeconds: 30,
    minInstances: 1,
    secrets: ["ANTHROPIC_KEY"],
  })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Login required.");
    }

    // Accept either full message history or single transcript
    let messages = data.messages;
    if (!messages && data.transcript) {
      messages = [{ role: "user", content: data.transcript }];
    }
    if (!messages || !Array.isArray(messages) || messages.length === 0) {
      throw new functions.https.HttpsError("invalid-argument", "messages or transcript required.");
    }

    // Server-side key is authoritative. Client key (if any) is ignored.
    const apiKey = functions.config().anthropic?.key
      || process.env.ANTHROPIC_KEY
      || data.claudeKey;
    if (!apiKey) {
      throw new functions.https.HttpsError("failed-precondition", "No Claude API key configured on the server.");
    }

    const client = new Anthropic.default({ apiKey });

    try {
      const today = new Date().toISOString().substring(0, 10);
      const systemPrompt = `You are Aghieri — a calm, grounded ADHD productivity companion. Not an AI assistant, not a chatbot. You speak like a steady friend who has known the user a while: warm, unhurried, quietly confident, present.

VOICE RULES (always):
- Keep every reply short. Two sentences maximum unless you are creating a task.
- Natural spoken rhythm. Contractions. Concrete language. No filler.
- Never say "as an AI", "I'm just a program", "I apologize", or "sorry for the confusion".
- No exclamation points. No hype words. No urgency ("quickly", "right away", "asap").
- No emoji. No bullet points in spoken replies.
- If you don't know, say so in one short sentence and offer a next step.
- Address the user directly ("you"), not "the user".

TASK CREATION RULES:
1. If the user already gave a title, use it. Do NOT re-ask.
2. Ask only ONE follow-up question at a time for missing fields: type, due date, or time.
3. Valid types: homework, project, study, meeting, lab, reading, exam, personal, work.
4. If the user says "skip", "no", "none", "that's it", or similar, move on immediately.
5. After 3 exchanges max (or sooner with title + type), CREATE the task.
6. To create, output ONLY this JSON with no other text:
{"action":"create_task","title":"...","taskType":"...","dueDate":"YYYY-MM-DD","scheduledTime":"HH:mm"}
7. Omit dueDate/scheduledTime if not provided. Default taskType to "personal" if unclear.
8. Be decisive — create the task quickly rather than looping questions.
Today is ${today}.

For anything that is not task creation, respond in-character as Aghieri in one or two short sentences.`;

      const resp = await client.messages.create({
        model: "claude-haiku-4-5-20251001",
        max_tokens: 100,
        system: systemPrompt,
        messages,
      });

      const text = resp.content?.[0]?.text || "";
      return { response: text };
    } catch (e) {
      console.error("voiceCommand Claude error:", e);
      throw new functions.https.HttpsError("internal", "Claude API call failed.");
    }
  });


// ── Task Step Breakdown (Claude) — web-safe, used by focus screen ──────────
exports.breakdownTask = functions
  .runWith({ memory: "256MB", timeoutSeconds: 30, secrets: ["ANTHROPIC_KEY"] })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Login required.");
    }

    const content = (data.content || "").toString().trim();
    if (!content) {
      throw new functions.https.HttpsError("invalid-argument", "content required.");
    }

    const apiKey = process.env.ANTHROPIC_KEY;
    if (!apiKey) {
      throw new functions.https.HttpsError("failed-precondition", "No Claude key configured.");
    }

    const client = new Anthropic.default({ apiKey });

    try {
      const resp = await client.messages.create({
        model: "claude-haiku-4-5-20251001",
        max_tokens: 800,
        messages: [{
          role: "user",
          content: `Break this task into 3-6 concrete, actionable steps a person with ADHD can follow. Each step should be one sentence, start with a verb, and be small enough to start in 2 minutes.

Return ONLY this JSON shape, no other text:
[{"title":"short task title (under 6 words)","steps":["step 1","step 2","step 3"],"estimated_minutes":30}]

Input:
${content.slice(0, 2000)}`,
        }],
      });

      let text = (resp.content?.[0]?.text || "").trim();
      if (text.startsWith("```")) {
        text = text.split("```")[1] || text;
        if (text.startsWith("json")) text = text.slice(4);
        text = text.trim();
      }

      let tasks = [];
      try {
        tasks = JSON.parse(text);
      } catch (e) {
        console.error("breakdownTask parse error:", e, "raw:", text);
        throw new functions.https.HttpsError("internal", "Could not parse step breakdown.");
      }

      return { tasks };
    } catch (e) {
      if (e.code) throw e; // Re-throw HttpsError
      console.error("breakdownTask Claude error:", e);
      throw new functions.https.HttpsError("internal", "Claude API call failed.");
    }
  });


// ── Text-to-Speech Proxy (ElevenLabs) — bypasses CORS for web ──────────────
exports.textToSpeech = functions
  .runWith({
    memory: "512MB",
    timeoutSeconds: 30,
    minInstances: 1,
    secrets: ["ELEVENLABS_API_KEY"],
  })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Login required.");
    }

    const text = data.text;
    const voiceId = data.voiceId || "iLVmqjzCGGvqtMCk6vVQ";

    // Server-side key is authoritative. Client key is only a last-resort fallback.
    const elevenLabsKey = functions.config().elevenlabs?.key
      || process.env.ELEVENLABS_API_KEY
      || data.elevenLabsKey;

    if (!text || typeof text !== "string") {
      throw new functions.https.HttpsError("invalid-argument", "text required.");
    }
    if (!elevenLabsKey) {
      throw new functions.https.HttpsError("failed-precondition", "No ElevenLabs API key configured on the server.");
    }

    try {
      // eleven_flash_v2_5 — ~75ms first-byte latency vs ~250ms for turbo.
      const resp = await fetch(
        `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}?optimize_streaming_latency=4&output_format=mp3_22050_32`,
        {
          method: "POST",
          headers: {
            "xi-api-key": elevenLabsKey,
            "Content-Type": "application/json",
            "Accept": "audio/mpeg",
          },
          body: JSON.stringify({
            text,
            model_id: "eleven_flash_v2_5",
            voice_settings: {
              stability: 0.65,
              similarity_boost: 0.80,
              style: 0.05,
              use_speaker_boost: true,
            },
          }),
        }
      );

      if (!resp.ok) {
        const errText = await resp.text();
        console.error("ElevenLabs TTS error:", resp.status, errText);
        throw new functions.https.HttpsError("internal", `ElevenLabs error ${resp.status}`);
      }

      const arrayBuf = await resp.arrayBuffer();
      const base64Audio = Buffer.from(arrayBuf).toString("base64");
      return { audio: base64Audio };
    } catch (e) {
      if (e instanceof functions.https.HttpsError) throw e;
      console.error("textToSpeech error:", e);
      throw new functions.https.HttpsError("internal", "ElevenLabs TTS call failed.");
    }
  });


// ── End-of-Day Incomplete Task Check ──────────────────────────────────────────
// Runs daily at 9pm EST — checks for incomplete due tasks
exports.checkIncompleteTasks = functions
  .runWith({ secrets: ["ANTHROPIC_KEY"] })
  .pubsub
  .schedule("0 21 * * *")
  .timeZone("America/New_York")
  .onRun(async () => {
    const today = new Date().toISOString().split("T")[0];

    // Find all tasks due today that are still pending
    const tasksSnap = await db.collection("tasks")
      .where("due_date", "==", today)
      .where("status", "in", ["pending", "active"])
      .get();

    const client = new Anthropic.default({
      apiKey: functions.config().anthropic?.key || process.env.ANTHROPIC_KEY,
    });

    for (const doc of tasksSnap.docs) {
      const task = doc.data();
      const uid = task.uid;
      if (!uid) continue;

      // Mark as needing reschedule (app will prompt user)
      await doc.ref.update({
        status: "needs_reschedule",
        reschedule_prompted: false,
      });

      // Write a notification document for the app to pick up
      await db.collection("users").doc(uid)
        .collection("notifications").add({
          type: "reschedule_prompt",
          task_id: doc.id,
          task_title: task.title,
          message: `${task.title} didn't make it today — want to find it a spot?`,
          created_at: new Date().toISOString(),
          read: false,
        });
    }

    console.log(`Incomplete task check: flagged ${tasksSnap.size} tasks.`);
  });

// ── OAuth: Spotify ───────────────────────────────────────────────────────────

exports.spotifyAuthStart = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Login required.");
  }
  const uid = context.auth.uid;
  const state = crypto.randomBytes(24).toString("hex");

  await db.collection("oauth_states").doc(state).set({
    uid,
    provider: "spotify",
    created_at: admin.firestore.FieldValue.serverTimestamp(),
  });

  const url = "https://accounts.spotify.com/authorize"
    + `?client_id=${encodeURIComponent(SPOTIFY_CLIENT_ID)}`
    + "&response_type=code"
    + `&redirect_uri=${encodeURIComponent(SPOTIFY_REDIRECT)}`
    + `&scope=${encodeURIComponent(SPOTIFY_SCOPES)}`
    + `&state=${state}`
    + "&show_dialog=true";

  return { url, state };
});

exports.spotifyAuthCallback = functions
  .runWith({ secrets: ["SPOTIFY_CLIENT_SECRET"] })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Login required.");
    }
    const uid = context.auth.uid;
    const code  = data?.code;
    const state = data?.state;
    if (!code || !state) {
      throw new functions.https.HttpsError("invalid-argument", "Missing code or state.");
    }

    const stateRef = db.collection("oauth_states").doc(state);
    const stateDoc = await stateRef.get();
    if (!stateDoc.exists) {
      throw new functions.https.HttpsError("permission-denied", "Invalid or expired state.");
    }
    const stateData = stateDoc.data();
    if (stateData.uid !== uid || stateData.provider !== "spotify") {
      throw new functions.https.HttpsError("permission-denied", "State mismatch.");
    }
    await stateRef.delete();

    const secret = process.env.SPOTIFY_CLIENT_SECRET;
    const basic = Buffer.from(`${SPOTIFY_CLIENT_ID}:${secret}`).toString("base64");

    let tokenResp;
    try {
      tokenResp = await axios.post(
        "https://accounts.spotify.com/api/token",
        new URLSearchParams({
          grant_type: "authorization_code",
          code,
          redirect_uri: SPOTIFY_REDIRECT,
        }).toString(),
        {
          headers: {
            "Authorization": `Basic ${basic}`,
            "Content-Type": "application/x-www-form-urlencoded",
          },
        }
      );
    } catch (err) {
      console.error("Spotify token exchange failed:", err.response?.data || err.message);
      throw new functions.https.HttpsError("internal", "Spotify token exchange failed.");
    }

    const { access_token, refresh_token, expires_in, scope, token_type } = tokenResp.data;

    let profile = {};
    try {
      const me = await axios.get("https://api.spotify.com/v1/me", {
        headers: { "Authorization": `Bearer ${access_token}` },
      });
      profile = {
        id: me.data.id,
        display_name: me.data.display_name,
        email: me.data.email,
        product: me.data.product,
      };
    } catch (err) {
      console.warn("Spotify /me lookup failed:", err.response?.data || err.message);
    }

    await db.collection("users").doc(uid)
      .collection("integrations").doc("spotify").set({
        provider: "spotify",
        access_token,
        refresh_token,
        token_type,
        scope,
        expires_at: Date.now() + (expires_in * 1000),
        profile,
        connected_at: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

    return { connected: true, profile };
  });

// ── OAuth: Notion ────────────────────────────────────────────────────────────

exports.notionAuthStart = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Login required.");
  }
  const uid = context.auth.uid;
  const state = crypto.randomBytes(24).toString("hex");

  await db.collection("oauth_states").doc(state).set({
    uid,
    provider: "notion",
    created_at: admin.firestore.FieldValue.serverTimestamp(),
  });

  const url = "https://api.notion.com/v1/oauth/authorize"
    + `?client_id=${encodeURIComponent(NOTION_CLIENT_ID)}`
    + "&response_type=code"
    + "&owner=user"
    + `&redirect_uri=${encodeURIComponent(NOTION_REDIRECT)}`
    + `&state=${state}`;

  return { url, state };
});

exports.notionAuthCallback = functions
  .runWith({ secrets: ["NOTION_CLIENT_SECRET"] })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Login required.");
    }
    const uid = context.auth.uid;
    const code  = data?.code;
    const state = data?.state;
    if (!code || !state) {
      throw new functions.https.HttpsError("invalid-argument", "Missing code or state.");
    }

    const stateRef = db.collection("oauth_states").doc(state);
    const stateDoc = await stateRef.get();
    if (!stateDoc.exists) {
      throw new functions.https.HttpsError("permission-denied", "Invalid or expired state.");
    }
    const stateData = stateDoc.data();
    if (stateData.uid !== uid || stateData.provider !== "notion") {
      throw new functions.https.HttpsError("permission-denied", "State mismatch.");
    }
    await stateRef.delete();

    const secret = process.env.NOTION_CLIENT_SECRET;
    const basic = Buffer.from(`${NOTION_CLIENT_ID}:${secret}`).toString("base64");

    let tokenResp;
    try {
      tokenResp = await axios.post(
        "https://api.notion.com/v1/oauth/token",
        {
          grant_type: "authorization_code",
          code,
          redirect_uri: NOTION_REDIRECT,
        },
        {
          headers: {
            "Authorization": `Basic ${basic}`,
            "Content-Type": "application/json",
            "Notion-Version": "2022-06-28",
          },
        }
      );
    } catch (err) {
      console.error("Notion token exchange failed:", err.response?.data || err.message);
      throw new functions.https.HttpsError("internal", "Notion token exchange failed.");
    }

    const {
      access_token,
      token_type,
      bot_id,
      workspace_id,
      workspace_name,
      workspace_icon,
      owner,
      duplicated_template_id,
    } = tokenResp.data;

    await db.collection("users").doc(uid)
      .collection("integrations").doc("notion").set({
        provider: "notion",
        access_token,
        token_type,
        bot_id,
        workspace_id,
        workspace_name,
        workspace_icon,
        owner,
        duplicated_template_id,
        connected_at: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

    return {
      connected: true,
      workspace_name,
      workspace_icon,
    };
  });
