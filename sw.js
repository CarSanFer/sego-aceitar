/* SEGO — Service Worker (v26.11.05)
   Regra: NÃO guarda a aplicação nem dados em cache. Só intervém nas navegações (abrir a página):
   tenta sempre a rede (versão mais recente do Vercel) e, se não houver ligação, mostra um aviso.
   Supabase, EmailJS, CDN, /api, uploads e downloads passam ao lado, exatamente como no browser. */
const SW_VER = 'sego-sw-1';
const OFFLINE_HTML = `<!doctype html><html lang="pt"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>SEGO — Sem ligação</title>
<style>body{margin:0;font-family:Carlito,Calibri,Arial,sans-serif;font-size:13px;background:#F4F6F9;color:#1E3A5F;display:flex;min-height:100vh;align-items:center;justify-content:center}
.c{background:#fff;border-top:3px solid #C99628;border-radius:6px;padding:28px 26px;max-width:340px;text-align:center;box-shadow:0 2px 10px rgba(0,0,0,.08)}
b{display:block;margin-bottom:8px}button{margin-top:16px;background:#1E3A5F;color:#fff;border:0;border-radius:4px;padding:8px 18px;font:inherit;font-weight:700;cursor:pointer}</style></head>
<body><div class="c"><b>Sem Ligação à Internet</b>O SEGO precisa de rede para consultar e gravar os dados da obra.<br>Verifique a ligação e tente de novo.<br><button onclick="location.reload()">Tentar de Novo</button></div></body></html>`;

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil((async () => {
  const ks = await caches.keys();
  await Promise.all(ks.filter(k => k.startsWith('sego-') && k !== SW_VER).map(k => caches.delete(k)));
  await self.clients.claim();
})()));
self.addEventListener('fetch', e => {
  const r = e.request;
  if (r.method !== 'GET' || r.mode !== 'navigate') return; // tudo o resto: comportamento normal do browser
  e.respondWith(fetch(r).catch(() => new Response(OFFLINE_HTML, { headers: { 'Content-Type': 'text/html; charset=utf-8' } })));
});
