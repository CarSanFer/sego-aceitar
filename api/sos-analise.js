// /api/sos-analise.js — gera síntese de tema SOS, processando conteúdo dos anexos
// Suporta: PDF (nativo Claude), imagens (nativo Claude), .eml (parse via mailparser → texto)
// Recebe: {titulo, observacoes, anexos:[{name, mime, size, url}]}
// Devolve: {analise, processados, naoProcessados, anexosResumo}

const { simpleParser } = require('mailparser');

// Configuração Vercel — aumenta timeout para suportar download + Claude API
module.exports.config = { maxDuration: 60 };

const MAX_ANEXOS = 5;
const MAX_MB = 3;
const MAX_TEXT_PER_EML = 10000; // chars max do body de cada email

async function descarregar(url, maxBytes) {
  const dl = await fetch(url);
  if (!dl.ok) throw new Error(`HTTP ${dl.status}`);
  const ab = await dl.arrayBuffer();
  if (ab.byteLength > maxBytes) throw new Error(`>${MAX_MB}MB (${Math.round(ab.byteLength / 1024 / 1024 * 10) / 10}MB)`);
  return Buffer.from(ab);
}

function inferImageMime(name, mime) {
  if (mime && mime.startsWith('image/')) return mime;
  const l = (name || '').toLowerCase();
  if (l.endsWith('.png')) return 'image/png';
  if (l.endsWith('.gif')) return 'image/gif';
  if (l.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}

async function processarAnexo(a, idx) {
  const name = a.name || '(sem nome)';
  const mime = (a.mime || '').toLowerCase();
  const url = a.url || '';
  if (!url) return { erro: 'sem URL', name };

  const lname = name.toLowerCase();
  const isPDF = mime === 'application/pdf' || lname.endsWith('.pdf');
  const isImg = mime.startsWith('image/') || /\.(png|jpe?g|gif|webp)$/.test(lname);
  const isEml = mime === 'message/rfc822' || lname.endsWith('.eml');

  if (!isPDF && !isImg && !isEml) {
    return { erro: `tipo não suportado (${mime || '?'})`, name };
  }

  let buf;
  try {
    buf = await descarregar(url, MAX_MB * 1024 * 1024);
  } catch (e) {
    return { erro: `falha download: ${e.message}`, name };
  }

  if (isPDF) {
    return {
      ok: true, name,
      block: { type: 'document', source: { type: 'base64', media_type: 'application/pdf', data: buf.toString('base64') } },
      resumo: `[anexo ${idx + 1}] ${name} — PDF (conteúdo abaixo)`
    };
  }
  if (isImg) {
    return {
      ok: true, name,
      block: { type: 'image', source: { type: 'base64', media_type: inferImageMime(name, mime), data: buf.toString('base64') } },
      resumo: `[anexo ${idx + 1}] ${name} — Imagem (conteúdo abaixo)`
    };
  }
  if (isEml) {
    try {
      const parsed = await simpleParser(buf);
      const subj = (parsed.subject || '(sem assunto)').slice(0, 300);
      const from = (parsed.from && parsed.from.text) ? parsed.from.text.slice(0, 200) : '(sem remetente)';
      const to = (parsed.to && parsed.to.text) ? parsed.to.text.slice(0, 200) : '(sem destinatário)';
      const cc = (parsed.cc && parsed.cc.text) ? parsed.cc.text.slice(0, 200) : '';
      const date = parsed.date ? parsed.date.toISOString().slice(0, 19).replace('T', ' ') : '(sem data)';
      // Preferir text plain. Se só html, strip tags básico.
      let body = (parsed.text || '').trim();
      if (!body && parsed.html) {
        body = String(parsed.html).replace(/<style[\s\S]*?<\/style>/gi, '').replace(/<script[\s\S]*?<\/script>/gi, '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
      }
      if (body.length > MAX_TEXT_PER_EML) body = body.slice(0, MAX_TEXT_PER_EML) + '\n... [truncado]';
      const txt = `--- EMAIL [anexo ${idx + 1}]: ${name} ---\nDe: ${from}\nPara: ${to}${cc ? '\nCc: ' + cc : ''}\nData: ${date}\nAssunto: ${subj}\n\n${body || '(corpo vazio)'}\n--- FIM EMAIL ---`;
      return {
        ok: true, name,
        block: { type: 'text', text: txt },
        resumo: `[anexo ${idx + 1}] ${name} — Email (${subj.slice(0, 60)})`
      };
    } catch (e) {
      return { erro: `erro parse email: ${e.message}`, name };
    }
  }
}

module.exports = async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  try {
    const key = process.env.ANTHROPIC_API_KEY;
    if (!key) return res.status(500).json({ error: 'ANTHROPIC_API_KEY não configurada' });

    const body = typeof req.body === 'string' ? JSON.parse(req.body) : (req.body || {});
    const titulo = String(body.titulo || '').trim();
    const observacoes = String(body.observacoes || '').trim();
    const anexos = Array.isArray(body.anexos) ? body.anexos : [];

    // Processar até MAX_ANEXOS em paralelo
    const aProcessar = anexos.slice(0, MAX_ANEXOS);
    const naoProcessados = anexos.slice(MAX_ANEXOS).map(a => `${a.name} (excedeu limite de ${MAX_ANEXOS})`);
    const results = await Promise.all(aProcessar.map((a, i) => processarAnexo(a, i)));

    const contentBlocks = [];
    const anexosResumo = [];
    results.forEach(r => {
      if (r.ok) {
        contentBlocks.push(r.block);
        anexosResumo.push(r.resumo);
      } else {
        naoProcessados.push(`${r.name} (${r.erro})`);
      }
    });

    const prompt = `És um analista sénior de fiscalização, segurança e gestão de projectos de construção em Portugal. Vais analisar uma situação operacional registada num relatório SOS (Situações Operacionais Semanais) com base no conteúdo dos anexos.

DADOS DA SITUAÇÃO:
Título: ${titulo || '(sem título)'}
Observações: ${observacoes || '(sem observações)'}

Anexos processados (conteúdo nos blocos acima):
${anexosResumo.length ? anexosResumo.join('\n') : '(nenhum)'}
${naoProcessados.length ? '\nAnexos NÃO processados: ' + naoProcessados.join('; ') : ''}

INSTRUÇÕES:
- A informação concreta está sobretudo no conteúdo dos anexos (emails, PDFs, imagens). Lê tudo com atenção.
- Identifica partes envolvidas (empresas, pessoas), datas, valores, referências contratuais, marcos temporais, e quem disse o quê.
- Constrói um ponto de situação CONCRETO baseado no que está escrito, não em generalidades.

Sintetiza em PT-PT, com este formato exacto (usa Markdown apenas para os títulos a bold):

**Situação**
[2-4 frases com FACTOS dos anexos: quem está envolvido, o que aconteceu, quando, onde se encontra a situação actualmente. Refere partes, datas e valores concretos.]

**Risco**
[Principal risco operacional, técnico, contratual, financeiro ou de prazo. 2-3 frases com base no que leste, não em conjecturas.]

**Acção recomendada**
[2-4 pontos curtos e accionáveis. Cita responsáveis ou interlocutores específicos sempre que possível.]

**Próximos passos**
[Prazo sugerido, responsável principal, e que decisão precisa de ser tomada e por quem. 2-3 frases.]

REGRAS RÍGIDAS:
- PT-PT, sem brasileirismos
- Concretude > generalidade. Nomes de empresas, datas, valores, referências contratuais — sempre que disponíveis nos anexos
- Se a informação for genuinamente insuficiente para uma secção, escreve "Não foi possível inferir a partir dos anexos disponíveis" e diz o que falta
- Sem preâmbulos. Sem repetir o título.`;

    contentBlocks.push({ type: 'text', text: prompt });

    const apiResp = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'x-api-key': key,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json'
      },
      body: JSON.stringify({
        model: 'claude-haiku-4-5',
        max_tokens: 2000,
        messages: [{ role: 'user', content: contentBlocks }]
      })
    });

    if (!apiResp.ok) {
      const txt = await apiResp.text().catch(() => '');
      return res.status(apiResp.status).json({ error: 'Erro Claude API', details: txt.slice(0, 800) });
    }

    const data = await apiResp.json();
    const analise = (data.content && data.content[0] && data.content[0].text) || '';
    return res.status(200).json({
      analise,
      processados: results.filter(r => r.ok).length,
      naoProcessados,
      anexosResumo
    });
  } catch (e) {
    return res.status(500).json({ error: e.message || String(e), stack: (e.stack || '').slice(0, 500) });
  }
};
