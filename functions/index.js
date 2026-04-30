/**
 * Aghieri — Firebase Cloud Functions (v2 API)
 * TOAKCO LLC / DS-483 Capstone
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onObjectFinalized }  = require("firebase-functions/v2/storage");
const { onSchedule }         = require("firebase-functions/v2/scheduler");
const admin    = require("firebase-admin");
const Anthropic = require("@anthropic-ai/sdk");
const axios    = require("axios");
const crypto   = require("crypto");

// ── Weather (OpenWeatherMap) ──────────────────────────────────────────────────
exports.getWeather = onCall(
  { secrets: ["OPENWEATHER_API_KEY"] },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
    const { lat, lon } = request.data;
    if (!lat || !lon) throw new HttpsError("invalid-argument", "lat and lon required.");

    const key = process.env.OPENWEATHER_API_KEY;
    if (!key) throw new HttpsError("failed-precondition", "No weather API key configured.");

    try {
      const resp = await axios.get("https://api.openweathermap.org/data/2.5/weather", {
        params: { lat, lon, appid: key, units: "imperial" },
      });
      const d = resp.data;
      const tempF = d.main.temp;
      const tempC = ((tempF - 32) * 5) / 9;

      return {
        condition: d.weather[0].main,
        tempF: Math.round(tempF),
        tempC: Math.round(tempC),
        humidity: d.main.humidity,
        icon: d.weather[0].icon,
        city: d.name,
        summary: `${d.weather[0].description}, ${Math.round(tempF)}°F`,
      };
    } catch (e) {
      console.error("Weather fetch error:", e.response?.data || e.message);
      throw new HttpsError("internal", "Could not fetch weather.");
    }
  }
);

// ── Morning Briefing ──────────────────────────────────────────────────────────
// Called by client on wake, or by scheduled function at user's wake time.
// Generates a short AI briefing: weather + tasks + motivational framing.
exports.getMorningBriefing = onCall(
  { secrets: ["ANTHROPIC_KEY", "OPENWEATHER_API_KEY"] },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
    const uid = request.auth.uid;
    const { lat, lon } = request.data || {};

    // Fetch today's tasks
    const today = new Date().toISOString().split("T")[0];
    const tasksSnap = await db.collection("tasks")
      .where("uid", "==", uid)
      .where("status", "in", ["pending", "active"])
      .limit(5)
      .get();
    const tasks = tasksSnap.docs.map(d => d.data().title).filter(Boolean);

    // Fetch user profile for name
    const userDoc = await db.collection("users").doc(uid).get();
    const name = userDoc.exists ? (userDoc.data().preferredName || userDoc.data().name || "") : "";

    // Weather (optional — skip if no location)
    let weatherSummary = "";
    if (lat && lon && process.env.OPENWEATHER_API_KEY) {
      try {
        const w = await axios.get("https://api.openweathermap.org/data/2.5/weather", {
          params: { lat, lon, appid: process.env.OPENWEATHER_API_KEY, units: "imperial" },
        });
        const d = w.data;
        weatherSummary = `${d.weather[0].description}, ${Math.round(d.main.temp)}°F`;
      } catch (_) {}
    }

    const client = new Anthropic.default({ apiKey: process.env.ANTHROPIC_KEY });

    const prompt = `You are Aghieri, a calm ADHD productivity companion. Generate a short morning briefing (2-3 sentences max) for ${name || "the user"}.

Today: ${today}
${weatherSummary ? `Weather: ${weatherSummary}` : ""}
${tasks.length > 0 ? `Today's tasks: ${tasks.join(", ")}` : "No tasks scheduled yet."}

Rules:
- Warm and grounded, not cheerful or performative
- Mention the weather naturally if available
- Reference 1-2 tasks at most, gently
- End with one short grounding sentence
- Never use exclamation points or hype words`;

    try {
      const resp = await client.messages.create({
        model: "claude-haiku-4-5-20251001",
        max_tokens: 150,
        messages: [{ role: "user", content: prompt }],
      });
      return { briefing: resp.content[0].text.trim(), weather: weatherSummary, tasks };
    } catch (e) {
      console.error("Morning briefing error:", e);
      throw new HttpsError("internal", "Could not generate briefing.");
    }
  }
);

admin.initializeApp();
const db = admin.firestore();

// ── OAuth config — client IDs are public, secrets live in Secret Manager ────
const SPOTIFY_CLIENT_ID  = "a7a04450126d42e193f0482c1c075df1";
const NOTION_CLIENT_ID   = "345d872b-594c-8144-adf8-0037e7ef3f13";
const AGHIERI_WEB_ORIGIN = "https://aghieri-7a8ce.web.app";
const SPOTIFY_REDIRECT   = `${AGHIERI_WEB_ORIGIN}/auth/spotify/callback`;
const NOTION_REDIRECT    = `${AGHIERI_WEB_ORIGIN}/auth/notion/callback`;
const SPOTIFY_SCOPES = [
  "user-read-private", "user-read-email",
  "user-read-playback-state", "user-modify-playback-state",
  "user-read-currently-playing", "playlist-read-private",
  "streaming",
].join(" ");

// ── Rate Limiter ─────────────────────────────────────────────────────────────
const RATE_LIMIT = 100;
const WINDOW_MS  = 60_000;

exports.rateLimit = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
  const uid = request.auth.uid;
  const now = Date.now();
  const windowStart = now - WINDOW_MS;

  const ref = db.collection("rate_limits").doc(uid);
  const doc = await ref.get();
  let requests = doc.exists ? doc.data().requests || [] : [];
  requests = requests.filter(ts => ts > windowStart);

  if (requests.length >= RATE_LIMIT) {
    throw new HttpsError("resource-exhausted", `Rate limit exceeded. Max ${RATE_LIMIT} req/min.`);
  }

  requests.push(now);
  await ref.set({ requests }, { merge: true });
  return { ok: true, remaining: RATE_LIMIT - requests.length };
});


// ── Process Instruction Upload ────────────────────────────────────────────────
exports.processInstruction = onObjectFinalized(
  { memory: "512MiB", timeoutSeconds: 120, secrets: ["ANTHROPIC_KEY"], region: "us-east1" },
  async (event) => {
    const object   = event.data;
    const filePath = object.name;
    const uid      = filePath.split("/")[1];

    if (!filePath.startsWith("uploads/")) return;

    const bucket = admin.storage().bucket(object.bucket);
    const [fileContent] = await bucket.file(filePath).download();
    const text = fileContent.toString("utf-8");
    if (!text.trim()) return;

    const client = new Anthropic.default({ apiKey: process.env.ANTHROPIC_KEY });

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

    const batch = db.batch();
    for (const task of tasks) {
      const ref = db.collection("tasks").doc();
      batch.set(ref, {
        uid,
        title: task.title || "Untitled",
        steps: (task.steps || []).map((s, i) => ({ id: `s${i}`, text: s, completed: false })),
        color: null,
        status: "pending",
        source: "upload",
        created_at: new Date().toISOString(),
        due_date: null,
        estimated_minutes: task.estimated_minutes || 60,
      });
    }
    await batch.commit();
    console.log(`Created ${tasks.length} tasks for user ${uid}`);
  }
);


// ── Analyze Portfolio & Generate Suggestions ──────────────────────────────────
exports.analyzePortfolio = onCall(
  { secrets: ["ANTHROPIC_KEY"] },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
    const uid = request.auth.uid;

    const interactionsSnap = await db
      .collection("portfolio").doc(uid).collection("interactions")
      .orderBy("timestamp", "desc").limit(100).get();

    const interactions = interactionsSnap.docs.map(d => d.data());
    if (interactions.length < 10) return { suggestions: [] };

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

    const userDoc   = await db.collection("users").doc(uid).get();
    const interests = userDoc.exists ? (userDoc.data().interests || []) : [];

    const client = new Anthropic.default({ apiKey: process.env.ANTHROPIC_KEY });

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

      await db.collection("users").doc(uid).update({
        ui_suggestions: suggestions,
        suggestions_generated_at: new Date().toISOString(),
      });

      return { suggestions };
    } catch (e) {
      console.error("Portfolio analysis error:", e);
      return { suggestions: [] };
    }
  }
);


// ── Voice Command Proxy (Claude) ─────────────────────────────────────────────
exports.voiceCommand = onCall(
  { memory: "256MiB", timeoutSeconds: 30, minInstances: 1, secrets: ["ANTHROPIC_KEY"] },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");

    let messages = request.data.messages;
    if (!messages && request.data.transcript) {
      messages = [{ role: "user", content: request.data.transcript }];
    }
    if (!messages || !Array.isArray(messages) || messages.length === 0) {
      throw new HttpsError("invalid-argument", "messages or transcript required.");
    }

    const apiKey = process.env.ANTHROPIC_KEY || request.data.claudeKey;
    if (!apiKey) throw new HttpsError("failed-precondition", "No Claude API key configured.");

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
      throw new HttpsError("internal", "Claude API call failed.");
    }
  }
);


// ── Task Step Breakdown ──────────────────────────────────────────────────────
exports.breakdownTask = onCall(
  { memory: "256MiB", timeoutSeconds: 30, secrets: ["ANTHROPIC_KEY"] },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");

    const content = (request.data.content || "").toString().trim();
    if (!content) throw new HttpsError("invalid-argument", "content required.");

    const apiKey = process.env.ANTHROPIC_KEY;
    if (!apiKey) throw new HttpsError("failed-precondition", "No Claude key configured.");

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
        throw new HttpsError("internal", "Could not parse step breakdown.");
      }

      return { tasks };
    } catch (e) {
      if (e.code) throw e;
      console.error("breakdownTask Claude error:", e);
      throw new HttpsError("internal", "Claude API call failed.");
    }
  }
);


// ── Text-to-Speech Proxy (ElevenLabs) ────────────────────────────────────────
exports.textToSpeech = onCall(
  { memory: "512MiB", timeoutSeconds: 30, minInstances: 1, secrets: ["ELEVENLABS_API_KEY"] },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");

    const text    = request.data.text;
    const voiceId = request.data.voiceId || "iLVmqjzCGGvqtMCk6vVQ";
    const elevenLabsKey = process.env.ELEVENLABS_API_KEY || request.data.elevenLabsKey;

    if (!text || typeof text !== "string") {
      throw new HttpsError("invalid-argument", "text required.");
    }
    if (!elevenLabsKey) {
      throw new HttpsError("failed-precondition", "No ElevenLabs API key configured.");
    }

    try {
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
        throw new HttpsError("internal", `ElevenLabs error ${resp.status}`);
      }

      const arrayBuf  = await resp.arrayBuffer();
      const base64Audio = Buffer.from(arrayBuf).toString("base64");
      return { audio: base64Audio };
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      console.error("textToSpeech error:", e);
      throw new HttpsError("internal", "ElevenLabs TTS call failed.");
    }
  }
);


// ── End-of-Day Incomplete Task Check ─────────────────────────────────────────
exports.checkIncompleteTasks = onSchedule(
  { schedule: "0 21 * * *", timeZone: "America/New_York", secrets: ["ANTHROPIC_KEY"] },
  async () => {
    const today = new Date().toISOString().split("T")[0];

    const tasksSnap = await db.collection("tasks")
      .where("due_date", "==", today)
      .where("status", "in", ["pending", "active"])
      .get();

    for (const doc of tasksSnap.docs) {
      const task = doc.data();
      const uid  = task.uid;
      if (!uid) continue;

      await doc.ref.update({ status: "needs_reschedule", reschedule_prompted: false });

      await db.collection("users").doc(uid).collection("notifications").add({
        type: "reschedule_prompt",
        task_id: doc.id,
        task_title: task.title,
        message: `${task.title} didn't make it today — want to find it a spot?`,
        created_at: new Date().toISOString(),
        read: false,
      });
    }

    console.log(`Incomplete task check: flagged ${tasksSnap.size} tasks.`);
  }
);


// ── OAuth: Spotify ───────────────────────────────────────────────────────────
exports.spotifyAuthStart = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
  const uid   = request.auth.uid;
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

exports.spotifyAuthCallback = onCall(
  { secrets: ["SPOTIFY_CLIENT_SECRET"] },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
    const uid   = request.auth.uid;
    const code  = request.data?.code;
    const state = request.data?.state;
    if (!code || !state) throw new HttpsError("invalid-argument", "Missing code or state.");

    const stateRef = db.collection("oauth_states").doc(state);
    const stateDoc = await stateRef.get();
    if (!stateDoc.exists) throw new HttpsError("permission-denied", "Invalid or expired state.");

    const stateData = stateDoc.data();
    if (stateData.uid !== uid || stateData.provider !== "spotify") {
      throw new HttpsError("permission-denied", "State mismatch.");
    }
    await stateRef.delete();

    const secret = process.env.SPOTIFY_CLIENT_SECRET;
    const basic  = Buffer.from(`${SPOTIFY_CLIENT_ID}:${secret}`).toString("base64");

    let tokenResp;
    try {
      tokenResp = await axios.post(
        "https://accounts.spotify.com/api/token",
        new URLSearchParams({
          grant_type: "authorization_code",
          code,
          redirect_uri: SPOTIFY_REDIRECT,
        }).toString(),
        { headers: { "Authorization": `Basic ${basic}`, "Content-Type": "application/x-www-form-urlencoded" } }
      );
    } catch (err) {
      console.error("Spotify token exchange failed:", err.response?.data || err.message);
      throw new HttpsError("internal", "Spotify token exchange failed.");
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
  }
);


// ── OAuth: Notion ─────────────────────────────────────────────────────────────
exports.notionAuthStart = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
  const uid   = request.auth.uid;
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

exports.notionAuthCallback = onCall(
  { secrets: ["NOTION_CLIENT_SECRET"] },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Login required.");
    const uid   = request.auth.uid;
    const code  = request.data?.code;
    const state = request.data?.state;
    if (!code || !state) throw new HttpsError("invalid-argument", "Missing code or state.");

    const stateRef = db.collection("oauth_states").doc(state);
    const stateDoc = await stateRef.get();
    if (!stateDoc.exists) throw new HttpsError("permission-denied", "Invalid or expired state.");

    const stateData = stateDoc.data();
    if (stateData.uid !== uid || stateData.provider !== "notion") {
      throw new HttpsError("permission-denied", "State mismatch.");
    }
    await stateRef.delete();

    const secret = process.env.NOTION_CLIENT_SECRET;
    const basic  = Buffer.from(`${NOTION_CLIENT_ID}:${secret}`).toString("base64");

    let tokenResp;
    try {
      tokenResp = await axios.post(
        "https://api.notion.com/v1/oauth/token",
        { grant_type: "authorization_code", code, redirect_uri: NOTION_REDIRECT },
        { headers: { "Authorization": `Basic ${basic}`, "Content-Type": "application/json", "Notion-Version": "2022-06-28" } }
      );
    } catch (err) {
      console.error("Notion token exchange failed:", err.response?.data || err.message);
      throw new HttpsError("internal", "Notion token exchange failed.");
    }

    const { access_token, token_type, bot_id, workspace_id, workspace_name, workspace_icon, owner, duplicated_template_id } = tokenResp.data;

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

    return { connected: true, workspace_name, workspace_icon };
  }
);


// ── Push Notifications ────────────────────────────────────────────────────────

exports.sendTaskReminder = onCall(async (request) => {
  const { uid, taskId, taskTitle, minutesBefore = 15 } = request.data;
  if (!uid || !taskId) return { sent: false };

  const userDoc = await db.collection("users").doc(uid).get();
  const profile = userDoc.exists ? userDoc.data() : {};
  const tokens  = (profile.devices || []).filter(d => d.fcm_token).map(d => d.fcm_token);

  if (tokens.length === 0) return { sent: false };

  const result = await admin.messaging().sendEachForMulticast({
    notification: { title: `Starting in ${minutesBefore} min`, body: taskTitle || "Task coming up" },
    data: { type: "task", id: taskId },
    tokens,
  });
  return { sent: true, successCount: result.successCount };
});

exports.sendStatsUpdate = onCall(async (request) => {
  const { uid } = request.data;
  if (!uid) return { sent: false };

  const userDoc = await db.collection("users").doc(uid).get();
  const tokens  = ((userDoc.exists ? userDoc.data() : {}).devices || [])
    .filter(d => d.fcm_token).map(d => d.fcm_token);

  if (tokens.length === 0) return { sent: false };

  await admin.messaging().sendEachForMulticast({
    notification: { title: "Your focus stats are in", body: "See how your week looked →" },
    data: { type: "stats", id: uid },
    tokens,
  });
  return { sent: true };
});

exports.sendAlarmNotification = onCall(async (request) => {
  const { uid, alarmId, alarmLabel, deviceIds = [] } = request.data;
  if (!uid) return { sent: false };

  const userDoc    = await db.collection("users").doc(uid).get();
  const allDevices = (userDoc.exists ? userDoc.data() : {}).devices || [];

  const targets = deviceIds.length > 0
    ? allDevices.filter(d => deviceIds.includes(d.id) && d.fcm_token)
    : allDevices.filter(d => d.fcm_token);

  const tokens = targets.map(d => d.fcm_token);
  if (tokens.length === 0) return { sent: false };

  await admin.messaging().sendEachForMulticast({
    notification: { title: alarmLabel || "Alarm", body: "Tap to open Aghieri" },
    android: { priority: "high" },
    apns: {
      payload: { aps: { sound: "default", contentAvailable: true } },
      headers: { "apns-priority": "10" },
    },
    data: { type: "alarm", id: alarmId || "" },
    tokens,
  });
  return { sent: true };
});
