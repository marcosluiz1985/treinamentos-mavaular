// API do sistema de Treinamentos Mavaular
// - Leitura pública dos treinamentos, materiais e agenda
// - Alterações só com login (usuário e senha); cada usuário altera só o que cadastrou, administrador altera tudo
import { getStore } from "@netlify/blobs";
import crypto from "node:crypto";
import { promisify } from "node:util";
import { SEED, MATERIAIS } from "../../seed/dados.mjs";

const scrypt = promisify(crypto.scrypt);
const STORE = "treinamentos-mavaular";
const SITE_URL = "https://treinamentos-mavaular.netlify.app";
const SESSAO_HORAS = 12;
const PARTE_MAX = 4 * 1024 * 1024;      // por requisição de envio
const MATERIAL_MAX = 20 * 1024 * 1024;  // limite de download pelas funções do Netlify
const env = (k) => (globalThis.Netlify?.env?.get?.(k) ?? process.env[k] ?? "");
const loja = () => getStore({ name: STORE, consistency: "strong" });

// ---------- utilidades ----------
const json = (dados, status = 200, extra = {}) =>
  new Response(JSON.stringify(dados), { status, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...extra } });
const erro = (msg, status = 400) => json({ erro: msg }, status);
const b64u = (buf) => Buffer.from(buf).toString("base64url");
const limpaLogin = (s) => String(s || "").trim().toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^a-z0-9._-]/g, "");
const idValido = (s) => /^[A-Za-z0-9_-]{1,80}$/.test(String(s || ""));
const txt = (v, max = 2000) => String(v ?? "").slice(0, max);

async function hashSenha(senha, sal = crypto.randomBytes(16)) {
  const h = await scrypt(String(senha), sal, 64, { N: 16384, r: 8, p: 1 });
  return { sal: b64u(sal), hash: b64u(h) };
}
async function confere(senha, u) {
  const { hash } = await hashSenha(senha, Buffer.from(u.sal, "base64url"));
  return crypto.timingSafeEqual(Buffer.from(hash), Buffer.from(u.hash));
}
function assinar(payload) {
  const corpo = b64u(JSON.stringify(payload));
  const sig = b64u(crypto.createHmac("sha256", env("SESSION_SECRET")).update(corpo).digest());
  return corpo + "." + sig;
}
function verificarToken(tok) {
  if (!tok || !env("SESSION_SECRET")) return null;
  const [corpo, sig] = String(tok).split(".");
  if (!corpo || !sig) return null;
  const esperado = b64u(crypto.createHmac("sha256", env("SESSION_SECRET")).update(corpo).digest());
  if (sig.length !== esperado.length || !crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(esperado))) return null;
  try { const p = JSON.parse(Buffer.from(corpo, "base64url").toString()); return p.exp > Date.now() ? p : null; } catch { return null; }
}
function lerCookie(req, nome) {
  const c = req.headers.get("cookie") || "";
  for (const parte of c.split(";")) { const [k, ...v] = parte.trim().split("="); if (k === nome) return v.join("="); }
  return null;
}
const cookieSessao = (tok, maxAge) => `sessao=${tok}; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=${maxAge}`;

// ---------- dados ----------
async function usuario(login) { return login ? await loja().get("usuarios/" + login, { type: "json" }) : null; }
async function listarUsuarios() {
  const st = loja(); const { blobs } = await st.list({ prefix: "usuarios/" });
  return (await Promise.all(blobs.map((b) => st.get(b.key, { type: "json" })))).filter(Boolean);
}
async function listarTreinamentos() {
  const st = loja(); const { blobs } = await st.list({ prefix: "treinamentos/" });
  return (await Promise.all(blobs.map((b) => st.get(b.key, { type: "json" })))).filter(Boolean);
}
async function eu(req) {
  const p = verificarToken(lerCookie(req, "sessao"));
  if (!p) return null;
  const u = await usuario(p.l);
  if (!u || u.versao !== p.v) return null;
  return u;
}

// Na primeira vez, carrega os dados migrados do sistema anterior
async function semear() {
  const st = loja();
  if (await st.get("sistema/semeado")) return;
  for (const t of SEED.treinamentos || []) {
    if (!(await st.get("treinamentos/" + t.id))) await st.setJSON("treinamentos/" + t.id, t);
  }
  for (const [chave, b64] of Object.entries(MATERIAIS || {})) {
    if (!(await st.get(chave))) await st.set(chave, Buffer.from(b64, "base64"));
  }
  if (SEED.colaboradores && !(await st.get("cadastro/colaboradores"))) await st.setJSON("cadastro/colaboradores", SEED.colaboradores);
  await st.set("sistema/semeado", new Date().toISOString());
}

function formaPublica(t, logado) {
  const base = { ...t };
  if (!logado) {
    base.participantes = (t.participantes || []).map((p) => ({ nome: p.nome, setor: p.setor }));
    base.chamada = (t.participantes || []).map((p) => ({ setor: p.setor, presenca: p.presenca ?? null }));
  }
  base.materiais = (t.materiais || []).map((m) => ({ id: m.id, nome: m.nome, tipo: m.tipo, tamanho: m.tamanho, enviadoEm: m.enviadoEm }));
  return base;
}
function normalizarTreinamento(b) {
  return {
    nome: txt(b.nome, 200), tipo: txt(b.tipo, 120), assunto: txt(b.assunto, 300), data: /^\d{4}-\d{2}-\d{2}$/.test(b.data) ? b.data : "",
    hora: /^\d{2}:\d{2}$/.test(b.hora || "") ? b.hora : "", cargaHoraria: txt(b.cargaHoraria, 60), local: txt(b.local, 200),
    publico: txt(b.publico, 200), facilitador: txt(b.facilitador, 200), conteudo: txt(b.conteudo, 4000),
    participantes: (Array.isArray(b.participantes) ? b.participantes : []).slice(0, 500).map((p) => ({
      nome: txt(p.nome, 120), setor: txt(p.setor, 80), presenca: p.presenca === "presente" || p.presenca === "falta" ? p.presenca : null,
    })),
  };
}

// ---------- agenda (.ics) ----------
const icsEsc = (t) => String(t || "").replace(/\\/g, "\\\\").replace(/;/g, "\\;").replace(/,/g, "\\,").replace(/\r/g, "").replace(/\n/g, "\\n");
function dobrar(l) {
  const out = []; let b = Buffer.from(l);
  while (b.length > 74) { let c = 74; while ((b[c] & 0xc0) === 0x80) c--; out.push(b.subarray(0, c).toString()); b = Buffer.concat([Buffer.from(" "), b.subarray(c)]); }
  out.push(b.toString()); return out.join("\r\n");
}
function duracaoMin(c) {
  const s = String(c || "").toLowerCase().replace(",", ".");
  const h = s.match(/(\d+(?:\.\d+)?)\s*h/), m = s.match(/(\d+)\s*min/);
  const tot = (h ? parseFloat(h[1]) * 60 : 0) + (m ? parseInt(m[1]) : 0);
  return tot > 0 ? Math.round(tot) : 60;
}
const pad = (n) => String(n).padStart(2, "0");
function vevent(t, carimbo) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(t.data || "")) return [];
  const ev = ["BEGIN:VEVENT", `UID:${t.id}@treinamentos-mavaular`, `DTSTAMP:${carimbo}`, `SUMMARY:${icsEsc("Treinamento: " + (t.nome || ""))}`];
  let alarmes;
  if (/^\d{2}:\d{2}$/.test(t.hora || "")) {
    const [y, mo, d] = t.data.split("-").map(Number), [hh, mm] = t.hora.split(":").map(Number);
    const ini = new Date(Date.UTC(y, mo - 1, d, hh, mm)), fim = new Date(ini.getTime() + duracaoMin(t.cargaHoraria) * 60000);
    const f = (x) => `${x.getUTCFullYear()}${pad(x.getUTCMonth() + 1)}${pad(x.getUTCDate())}T${pad(x.getUTCHours())}${pad(x.getUTCMinutes())}00`;
    ev.push(`DTSTART;TZID=America/Sao_Paulo:${f(ini)}`, `DTEND;TZID=America/Sao_Paulo:${f(fim)}`);
    alarmes = [["-PT1H", "Treinamento em 1 hora"], ["-P1D", "Treinamento amanhã"]];
  } else {
    const [y, mo, d] = t.data.split("-").map(Number); const fim = new Date(Date.UTC(y, mo - 1, d + 1));
    ev.push(`DTSTART;VALUE=DATE:${t.data.replace(/-/g, "")}`, `DTEND;VALUE=DATE:${fim.getUTCFullYear()}${pad(fim.getUTCMonth() + 1)}${pad(fim.getUTCDate())}`);
    alarmes = [["-PT15H", "Treinamento amanhã"]];
  }
  if (t.local) ev.push(`LOCATION:${icsEsc(t.local)}`);
  const desc = [t.assunto && `Assunto: ${t.assunto}`, t.publico && `Público: ${t.publico}`, t.facilitador && `Facilitador: ${t.facilitador}`,
    t.cargaHoraria && `Carga horária: ${t.cargaHoraria}`, `Detalhes e materiais: ${SITE_URL}/#t-${t.id}`].filter(Boolean).join("\n");
  ev.push(`DESCRIPTION:${icsEsc(desc)}`, `URL:${SITE_URL}/#t-${t.id}`);
  for (const [g, m] of alarmes) ev.push("BEGIN:VALARM", "ACTION:DISPLAY", `TRIGGER:${g}`, `DESCRIPTION:${icsEsc(m + ": " + (t.nome || ""))}`, "END:VALARM");
  ev.push("END:VEVENT"); return ev;
}
function calendario(ts) {
  const now = new Date();
  const carimbo = `${now.getUTCFullYear()}${pad(now.getUTCMonth() + 1)}${pad(now.getUTCDate())}T${pad(now.getUTCHours())}${pad(now.getUTCMinutes())}${pad(now.getUTCSeconds())}Z`;
  const linhas = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Mavaular//Treinamentos//PT", "CALSCALE:GREGORIAN", "METHOD:PUBLISH",
    "X-WR-CALNAME:Treinamentos Mavaular", "X-WR-TIMEZONE:America/Sao_Paulo", "REFRESH-INTERVAL;VALUE=DURATION:PT1H", "X-PUBLISHED-TTL:PT1H",
    "BEGIN:VTIMEZONE", "TZID:America/Sao_Paulo", "BEGIN:STANDARD", "DTSTART:19700101T000000", "TZOFFSETFROM:-0300", "TZOFFSETTO:-0300",
    "TZNAME:-03", "END:STANDARD", "END:VTIMEZONE", ...ts.flatMap((t) => vevent(t, carimbo)), "END:VCALENDAR"];
  return linhas.map(dobrar).join("\r\n") + "\r\n";
}
const respIcs = (corpo) => new Response(corpo, { headers: { "content-type": "text/calendar; charset=utf-8", "cache-control": "no-cache" } });

// ---------- tentativas de login ----------
async function bloqueado(login) {
  const f = await loja().get("falhas/" + login, { type: "json" });
  return f && f.ate > Date.now();
}
async function registrarFalha(login) {
  const st = loja(); const f = (await st.get("falhas/" + login, { type: "json" })) || { n: 0 };
  f.n = (f.n || 0) + 1; if (f.n >= 8) { f.ate = Date.now() + 15 * 60000; f.n = 0; }
  await st.setJSON("falhas/" + login, f);
}

// ---------- rotas ----------
export default async (req) => {
  try {
    await semear();
    const url = new URL(req.url);
    const caminho = url.pathname.replace(/\/+$/, "");
    const metodo = req.method;
    const st = loja();

    // Agenda
    if (caminho === "/agenda.ics") return respIcs(calendario(await listarTreinamentos()));
    let m = caminho.match(/^\/agenda\/([A-Za-z0-9_-]+)\.ics$/);
    if (m) { const t = await st.get("treinamentos/" + m[1], { type: "json" }); return t ? respIcs(calendario([t])) : erro("Treinamento não encontrado", 404); }

    // Proteção contra envio de formulários de outros sites
    if (metodo !== "GET" && req.headers.get("x-treinamentos") !== "1") return erro("Requisição inválida", 403);

    const user = await eu(req);
    const sessao = user ? { login: user.login, nome: user.nome, admin: !!user.admin } : null;

    if (caminho === "/api/dados" && metodo === "GET") {
      const [ts, cad, us] = await Promise.all([listarTreinamentos(), st.get("cadastro/colaboradores", { type: "json" }), listarUsuarios()]);
      const nomes = Object.fromEntries(us.map((u) => [u.login, u.nome]));
      return json({
        eu: sessao, configurado: us.length > 0,
        treinamentos: ts.map((t) => ({ ...formaPublica(t, !!user), autorNome: nomes[t.autor] || "" })),
        colaboradores: user ? (cad || { lista: [] }) : { lista: [] },
      });
    }

    if (caminho === "/api/setup" && metodo === "POST") {
      if ((await listarUsuarios()).length) return erro("O sistema já foi configurado.", 409);
      const b = await req.json(); const codigo = env("SETUP_CODE");
      if (!codigo || String(b.codigo || "").trim() !== codigo) return erro("Código de configuração incorreto.", 403);
      const login = limpaLogin(b.login); if (!login || String(b.senha || "").length < 8) return erro("Informe um usuário e uma senha com pelo menos 8 caracteres.");
      const u = { login, nome: txt(b.nome, 80) || login, admin: true, versao: 1, ...(await hashSenha(b.senha)) };
      await st.setJSON("usuarios/" + login, u, { onlyIfNew: true });
      // os treinamentos migrados passam a pertencer ao administrador
      for (const t of await listarTreinamentos()) if (!t.autor) await st.setJSON("treinamentos/" + t.id, { ...t, autor: login });
      return json({ eu: { login, nome: u.nome, admin: true } }, 200, { "set-cookie": cookieSessao(assinar({ l: login, v: 1, exp: Date.now() + SESSAO_HORAS * 3600e3 }), SESSAO_HORAS * 3600) });
    }

    if (caminho === "/api/login" && metodo === "POST") {
      const b = await req.json(); const login = limpaLogin(b.login);
      if (!login) return erro("Informe o usuário.");
      if (await bloqueado(login)) return erro("Muitas tentativas. Aguarde 15 minutos e tente de novo.", 429);
      const u = await usuario(login);
      if (!u || !(await confere(b.senha || "", u))) { await registrarFalha(login); return erro("Usuário ou senha incorretos.", 401); }
      await st.delete("falhas/" + login);
      return json({ eu: { login, nome: u.nome, admin: !!u.admin } }, 200, { "set-cookie": cookieSessao(assinar({ l: login, v: u.versao, exp: Date.now() + SESSAO_HORAS * 3600e3 }), SESSAO_HORAS * 3600) });
    }
    if (caminho === "/api/logout" && metodo === "POST") return json({ ok: true }, 200, { "set-cookie": cookieSessao("", 0) });

    // ----- daqui para baixo: leitura de materiais é pública; o resto exige login -----
    m = caminho.match(/^\/api\/materiais\/([A-Za-z0-9_-]+)\/([A-Za-z0-9_-]+)$/);
    if (m && metodo === "GET") {
      const t = await st.get("treinamentos/" + m[1], { type: "json" });
      const mat = t && (t.materiais || []).find((x) => x.id === m[2]);
      if (!mat) return erro("Material não encontrado", 404);
      const partes = mat.partes || 1; const chaves = Array.from({ length: partes }, (_, i) => `materiais/${m[1]}/${m[2]}/${i}`);
      const corpo = new ReadableStream({
        async start(ctrl) {
          for (const k of chaves) { const d = await st.get(k, { type: "arrayBuffer" }); if (d) ctrl.enqueue(new Uint8Array(d)); }
          ctrl.close();
        },
      });
      const nome = mat.nome || "material";
      return new Response(corpo, { headers: {
        "content-type": mat.tipo || "application/octet-stream",
        "content-disposition": `attachment; filename="${nome.replace(/[^\x20-\x7e]/g, "_").replace(/"/g, "")}"; filename*=UTF-8''${encodeURIComponent(nome)}`,
        "cache-control": "no-store" } });
    }

    if (!user) return erro("Entre com seu usuário e senha para fazer alterações.", 401);
    const podeAlterar = (t) => user.admin || t.autor === user.login;

    if (caminho === "/api/senha" && metodo === "POST") {
      const b = await req.json();
      if (!(await confere(b.atual || "", user))) return erro("A senha atual está incorreta.", 403);
      if (String(b.nova || "").length < 8) return erro("A nova senha precisa ter pelo menos 8 caracteres.");
      const u = { ...user, versao: (user.versao || 1) + 1, ...(await hashSenha(b.nova)) };
      await st.setJSON("usuarios/" + user.login, u);
      return json({ ok: true }, 200, { "set-cookie": cookieSessao(assinar({ l: u.login, v: u.versao, exp: Date.now() + SESSAO_HORAS * 3600e3 }), SESSAO_HORAS * 3600) });
    }

    // Usuários (só administrador)
    if (caminho === "/api/usuarios" && metodo === "GET") {
      if (!user.admin) return erro("Só o administrador gerencia usuários.", 403);
      return json({ usuarios: (await listarUsuarios()).map((u) => ({ login: u.login, nome: u.nome, admin: !!u.admin })) });
    }
    if (caminho === "/api/usuarios" && metodo === "POST") {
      if (!user.admin) return erro("Só o administrador gerencia usuários.", 403);
      const b = await req.json(); const login = limpaLogin(b.login);
      if (!login) return erro("Informe o usuário (letras e números, sem espaços).");
      if (String(b.senha || "").length < 8) return erro("A senha precisa ter pelo menos 8 caracteres.");
      const u = { login, nome: txt(b.nome, 80) || login, admin: !!b.admin, versao: 1, ...(await hashSenha(b.senha)) };
      const r = await st.setJSON("usuarios/" + login, u, { onlyIfNew: true });
      if (r && r.modified === false) return erro("Já existe um usuário com esse nome.", 409);
      return json({ ok: true });
    }
    m = caminho.match(/^\/api\/usuarios\/([a-z0-9._-]+)$/);
    if (m) {
      if (!user.admin) return erro("Só o administrador gerencia usuários.", 403);
      const alvo = await usuario(m[1]); if (!alvo) return erro("Usuário não encontrado.", 404);
      if (metodo === "DELETE") {
        if (alvo.login === user.login) return erro("Você não pode excluir o próprio usuário.");
        await st.delete("usuarios/" + alvo.login); return json({ ok: true });
      }
      if (metodo === "PUT") {
        const b = await req.json(); const novo = { ...alvo };
        if (b.nome != null) novo.nome = txt(b.nome, 80) || alvo.login;
        if (b.admin != null && alvo.login !== user.login) novo.admin = !!b.admin;
        if (b.senha) {
          if (String(b.senha).length < 8) return erro("A senha precisa ter pelo menos 8 caracteres.");
          Object.assign(novo, await hashSenha(b.senha)); novo.versao = (alvo.versao || 1) + 1;
        }
        await st.setJSON("usuarios/" + alvo.login, novo); return json({ ok: true });
      }
    }

    // Cadastro de colaboradores (só administrador)
    if (caminho === "/api/colaboradores" && metodo === "PUT") {
      if (!user.admin) return erro("Só o administrador altera o cadastro de colaboradores.", 403);
      const b = await req.json();
      const lista = (Array.isArray(b.lista) ? b.lista : []).slice(0, 3000).map((p) => ({ id: txt(p.id, 80), nome: txt(p.nome, 120), setor: txt(p.setor, 80) }));
      await st.setJSON("cadastro/colaboradores", { lista, origem: txt(b.origem, 200), atualizadoEm: new Date().toISOString().slice(0, 10) });
      return json({ ok: true });
    }

    // Treinamentos
    m = caminho.match(/^\/api\/treinamentos\/([A-Za-z0-9_-]+)$/);
    if (m && metodo === "PUT") {
      if (!idValido(m[1])) return erro("Identificador inválido.");
      const atual = await st.get("treinamentos/" + m[1], { type: "json" });
      if (atual && !podeAlterar(atual)) return erro("Só quem cadastrou este treinamento (ou o administrador) pode alterá-lo.", 403);
      const b = await req.json(); const novo = normalizarTreinamento(b);
      if (!novo.nome || !novo.data) return erro("Informe nome e data do treinamento.");
      const t = { id: m[1], ...novo, autor: atual ? atual.autor : user.login, materiais: atual ? atual.materiais || [] : [],
        criadoEm: atual ? atual.criadoEm : new Date().toISOString(), alteradoEm: new Date().toISOString(), alteradoPor: user.login };
      await st.setJSON("treinamentos/" + m[1], t);
      return json({ treinamento: { ...formaPublica(t, true), autorNome: (await usuario(t.autor))?.nome || "" } });
    }
    if (m && metodo === "DELETE") {
      const atual = await st.get("treinamentos/" + m[1], { type: "json" });
      if (!atual) return json({ ok: true });
      if (!podeAlterar(atual)) return erro("Só quem cadastrou este treinamento (ou o administrador) pode excluí-lo.", 403);
      const { blobs } = await st.list({ prefix: `materiais/${m[1]}/` });
      await Promise.all(blobs.map((b) => st.delete(b.key)));
      await st.delete("treinamentos/" + m[1]);
      return json({ ok: true });
    }

    // Materiais: envio em partes de até 4 MB; a última parte registra o material no treinamento
    m = caminho.match(/^\/api\/materiais\/([A-Za-z0-9_-]+)\/([A-Za-z0-9_-]+)\/(\d+)$/);
    if (m && metodo === "POST") {
      const [, tid, mid, idxS] = m; const idx = Number(idxS);
      const t = await st.get("treinamentos/" + tid, { type: "json" });
      if (!t) return erro("Treinamento não encontrado.", 404);
      if (!podeAlterar(t)) return erro("Só quem cadastrou este treinamento (ou o administrador) pode anexar materiais.", 403);
      const total = Number(url.searchParams.get("total") || 1); const tamanho = Number(url.searchParams.get("tamanho") || 0);
      if (!(total >= 1 && total <= 10) || idx >= total || tamanho > MATERIAL_MAX) return erro("Arquivo maior que 20 MB.", 413);
      const dados = await req.arrayBuffer();
      if (dados.byteLength > PARTE_MAX) return erro("Parte grande demais.", 413);
      await st.set(`materiais/${tid}/${mid}/${idx}`, dados);
      if (idx === total - 1) {
        const atual = await st.get("treinamentos/" + tid, { type: "json" });
        const mat = { id: mid, nome: txt(url.searchParams.get("nome") || "material", 200), tipo: txt(url.searchParams.get("tipo") || "application/octet-stream", 120),
          tamanho, partes: total, enviadoEm: new Date().toISOString(), enviadoPor: user.login };
        atual.materiais = [...(atual.materiais || []).filter((x) => x.id !== mid), mat];
        await st.setJSON("treinamentos/" + tid, atual);
        return json({ material: { id: mat.id, nome: mat.nome, tipo: mat.tipo, tamanho: mat.tamanho, enviadoEm: mat.enviadoEm } });
      }
      return json({ ok: true });
    }
    m = caminho.match(/^\/api\/materiais\/([A-Za-z0-9_-]+)\/([A-Za-z0-9_-]+)$/);
    if (m && metodo === "DELETE") {
      const t = await st.get("treinamentos/" + m[1], { type: "json" });
      if (!t) return json({ ok: true });
      if (!podeAlterar(t)) return erro("Só quem cadastrou este treinamento (ou o administrador) pode remover materiais.", 403);
      t.materiais = (t.materiais || []).filter((x) => x.id !== m[2]);
      await st.setJSON("treinamentos/" + m[1], t);
      const { blobs } = await st.list({ prefix: `materiais/${m[1]}/${m[2]}/` });
      await Promise.all(blobs.map((b) => st.delete(b.key)));
      return json({ ok: true });
    }

    return erro("Rota não encontrada.", 404);
  } catch (e) {
    console.error(e);
    return erro("Erro no servidor. Tente de novo em instantes.", 500);
  }
};

export const config = { path: ["/api/*", "/agenda.ics", "/agenda/*"] };
