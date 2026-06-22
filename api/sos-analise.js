// /api/sos-analise.js — gera síntese de tema SOS usando Claude Haiku
// Recebe: {titulo, observacoes, anexos:[{name, mime, size}]}
// Devolve: {analise: "..."}

module.exports = async (req, res) => {
  // CORS (não estritamente necessário porque é mesma origem, mas seguro)
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  try {
    const key = process.env.ANTHROPIC_API_KEY;
    if (!key) return res.status(500).json({ error: 'ANTHROPIC_API_KEY não configurada no Vercel' });

    const body = req.body || {};
    const titulo = String(body.titulo || '').trim();
    const observacoes = String(body.observacoes || '').trim();
    const anexos = Array.isArray(body.anexos) ? body.anexos : [];

    const anexosList = anexos.length
      ? anexos.map(a => `- ${a.name || '(sem nome)'} (${a.mime || 'tipo desconhecido'}${a.size ? `, ${Math.round(a.size / 1024)} KB` : ''})`).join('\n')
      : '(sem anexos)';

    const prompt = `És um analista de fiscalização, segurança e gestão de obras em Portugal. Vais analisar uma situação operacional registada num relatório SOS (Situações Operacionais Semanais).

DADOS DA SITUAÇÃO:
Título: ${titulo || '(sem título)'}
Observações: ${observacoes || '(sem observações)'}
Anexos referenciados (não conteúdo, apenas referência):
${anexosList}

Sintetiza esta situação em PT-PT, de forma estruturada e concisa, com este formato exacto:

**Situação**
[1-2 frases descrevendo o problema ou ponto de situação]

**Risco**
[Principal risco operacional, técnico, contratual ou legal. 1-2 frases.]

**Acção recomendada**
[O que fazer a seguir, em 1-3 pontos curtos]

**Próximos passos**
[Prazo sugerido e responsável (se inferível). 1-2 frases.]

Regras:
- Português europeu (PT-PT)
- Concisão: sem preâmbulos nem repetições
- Baseia-te apenas na informação fornecida; não inventes dados
- Se a informação for insuficiente, indica-o explicitamente em "Próximos passos" (ex.: "Solicitar clarificação a X sobre Y")`;

    const apiResp = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'x-api-key': key,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json'
      },
      body: JSON.stringify({
        model: 'claude-haiku-4-5',
        max_tokens: 800,
        messages: [{ role: 'user', content: prompt }]
      })
    });

    if (!apiResp.ok) {
      const txt = await apiResp.text().catch(() => '');
      return res.status(apiResp.status).json({ error: 'Erro Claude API', details: txt.slice(0, 500) });
    }

    const data = await apiResp.json();
    const analise = (data.content && data.content[0] && data.content[0].text) || '';
    return res.status(200).json({ analise });
  } catch (e) {
    return res.status(500).json({ error: e.message || String(e) });
  }
};
