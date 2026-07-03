// Cloudflare Worker — Player API
// D1 binding name: DB

const H = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
};

function json(data, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: H });
}

export default {
  async fetch(req, env) {
    if (req.method === 'OPTIONS') return new Response(null, { headers: H });

    const path = new URL(req.url).pathname;

    try {
      // GET /sponsors — لیست اسپانسرهای فعال
      if (path === '/sponsors' && req.method === 'GET') {
        const { results } = await env.DB.prepare(
          'SELECT * FROM sponsors WHERE active=1 ORDER BY sort_order ASC'
        ).all();
        return json(results);
      }

      // GET /config — تنظیمات اپ (نسخه، آپدیت)
      if (path === '/config' && req.method === 'GET') {
        const { results } = await env.DB.prepare('SELECT key,value FROM config').all();
        const obj = Object.fromEntries(results.map(r => [r.key, r.value]));
        return json(obj);
      }

      // GET /announce — اعلان فعال
      if (path === '/announce' && req.method === 'GET') {
        const now = new Date().toISOString();
        const { results } = await env.DB.prepare(
          `SELECT * FROM announcements
           WHERE active=1 AND (expires_at IS NULL OR expires_at > ?)
           ORDER BY id DESC LIMIT 1`
        ).bind(now).all();
        return json(results[0] ?? null);
      }

      // POST /stats — ارسال آمار
      if (path === '/stats' && req.method === 'POST') {
        const b = await req.json().catch(() => ({}));
        await env.DB.prepare(
          `INSERT INTO stats (uuid,app_version,android_version,event,value)
           VALUES (?,?,?,?,?)`
        ).bind(
          b.uuid ?? 'unknown',
          b.app_version ?? '',
          b.android_version ?? '',
          b.event ?? 'open',
          b.value ?? ''
        ).run();
        return json({ ok: true });
      }

      // GET /master-half — Server Half برای ساخت Master Key
      if (path === '/master-half' && req.method === 'GET') {
        const { results } = await env.DB.prepare(
          "SELECT value FROM config WHERE key='server_half'"
        ).all();
        if (!results.length) return json({ error: 'server_half not set in D1' }, 500);
        return json({ server_half: results[0].value });
      }

      // GET /opensubtitles-key — کلید API OpenSubtitles (قابل تغییر از D1 بدون نیاز به آپدیت اپ)
      if (path === '/opensubtitles-key' && req.method === 'GET') {
        const { results } = await env.DB.prepare(
          "SELECT value FROM config WHERE key='opensubtitles_api_key'"
        ).all();
        if (!results.length) return json({ error: 'opensubtitles_api_key not set in D1' }, 500);
        return json({ api_key: results[0].value });
      }

      // POST /translate-srt — ترجمه یک batch از خطوط SRT
      // client خودش batch می‌کنه (۳۰ خط per request) — Worker فقط همون batch رو ترجمه می‌کنه
      if (path === '/translate-srt' && req.method === 'POST') {
        const body = await req.json();
        const lines = body.lines ?? [];
        const targetLang = body.target_lang ?? 'Persian';
        const sourceLang = body.source_lang ?? 'auto';

        if (!lines.length) return json({ lines: [] });

        const numbered = lines.map((l, idx) => `[${idx + 1}] ${l}`).join('\n');
        const sourceLine = sourceLang !== 'auto' ? `- Source language: ${sourceLang}` : '';
        const prompt = `You are a professional subtitle translator. Translate the following subtitle lines to ${targetLang}.
Rules:
- Translate ONLY the text content
- Preserve ALL emojis, symbols, punctuation, and special characters exactly as they are
- Keep numbers that are part of the text unchanged
- Do NOT add explanations, notes, or extra text
- Return ONLY the translated lines, each prefixed with its original number like [1], [2], etc.
- Do not change the order
${sourceLine}

Lines:
${numbered}`;

        const response = await env.AI.run('@cf/meta/llama-3.1-8b-instruct-fast', {
          messages: [{ role: 'user', content: prompt }],
          max_tokens: 2048,
        });

        const raw = response.response ?? '';
        const result = new Array(lines.length).fill('');
        const lineRegex = /\[(\d+)\]\s*(.+)/g;
        let match;
        while ((match = lineRegex.exec(raw)) !== null) {
          const idx = parseInt(match[1]) - 1;
          if (idx >= 0 && idx < lines.length) result[idx] = match[2].trim();
        }
        // fallback: خط ترجمه‌نشده → همون متن اصلی
        for (let j = 0; j < lines.length; j++) {
          if (!result[j]) result[j] = lines[j];
        }
        return json({ lines: result });
      }

      return json({ error: 'not found' }, 404);
    } catch (e) {
      return json({ error: e.message }, 500);
    }
  }
};
