// /api/translate.js — Serverless function (Vercel)
// Recebe textos PT, chama Anthropic, devolve traduções EN
// Chave em variável de ambiente ANTHROPIC_API_KEY no Vercel

module.exports = async (req, res) => {
  // CORS
  res.setHeader('Access-Control-Allow-Origin', 'https://sego.aceitar.pt');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    return res.status(500).json({ error: 'API key not configured on Vercel (ANTHROPIC_API_KEY env var)' });
  }

  try {
    const body = typeof req.body === 'string' ? JSON.parse(req.body) : req.body;
    const texts = body && body.texts;
    if (!texts || !Array.isArray(texts)) {
      return res.status(400).json({ error: 'Body must contain "texts" array' });
    }

    const prompt = 'Translate Portuguese (Portugal) texts to English.\n' +
      'Each text is on its own line, indexed as [N].\n' +
      'RULES:\n' +
      '- Keep proper nouns, company names, person names, place names unchanged\n' +
      '- Keep abbreviations unchanged: RSO, RVT, PTQ, PB, PA, PE, QE, AM, TCm, CO\n' +
      '- Keep dates, numbers, percentages, codes (PIC4, 6E04, S25, etc.) unchanged\n' +
      '- Translate descriptions, labels, analysis, observations, headers\n' +
      '- Translate weekdays SEG/TER/QUA/QUI/SEX/SÁB to MON/TUE/WED/THU/FRI/SAT\n' +
      '- Output ONLY translated lines in format "[N] translation", one per line\n' +
      '- No explanations, no extra text, no markdown\n\n' +
      'Texts:\n' +
      texts.map(function(t, i) { return '[' + i + '] ' + t; }).join('\n');

    const anthropicRes = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json'
      },
      body: JSON.stringify({
        model: 'claude-haiku-4-5',
        max_tokens: 4096,
        messages: [{ role: 'user', content: prompt }]
      })
    });

    if (!anthropicRes.ok) {
      const errText = await anthropicRes.text();
      return res.status(anthropicRes.status).json({ error: 'Anthropic API: ' + errText.slice(0, 500) });
    }

    const data = await anthropicRes.json();
    if (!data.content || !data.content[0]) {
      return res.status(500).json({ error: 'Unexpected Anthropic response: ' + JSON.stringify(data).slice(0, 200) });
    }

    const respText = data.content[0].text || '';
    const lines = respText.split('\n').filter(function(l) { return l.trim(); });
    const traducoes = new Array(texts.length).fill(null);
    lines.forEach(function(line) {
      const m = line.match(/^\[(\d+)\]\s*(.*)$/);
      if (m) {
        const idx = parseInt(m[1]);
        if (idx >= 0 && idx < texts.length) traducoes[idx] = m[2];
      }
    });

    return res.status(200).json({ translations: traducoes });
  } catch (err) {
    return res.status(500).json({ error: 'Server error: ' + err.message });
  }
};
