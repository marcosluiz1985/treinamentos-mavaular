"""Atualiza o Portal de Treinamentos (pasta site/) a partir dos dados do site de gestão.

Passos (rodados por uma sessão do Claude, que tem acesso às ferramentas do artifact):
  1. Baixe a coleção "treinamentos" do site de gestão para uma pasta (um JSON por treinamento).
  2. python3 tools/atualizar.py faltando <pasta_json>
       -> lista os ids de anexos que ainda não estão em site/materiais/
  3. Para cada id listado, baixe o anexo do site de gestão para tools/_baixados/<id>.<ext do arquivo baixado>
  4. python3 tools/atualizar.py montar <pasta_json>
       -> decodifica anexos .pptx/.docx/.xlsx, gera PDF com LibreOffice, remove anexos que não existem mais
          e regera site/index.html
"""
import base64, datetime, glob, json, os, re, shutil, subprocess, sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.path.join(RAIZ, "tools")
SITE = os.path.join(RAIZ, "site")
MATS = os.path.join(SITE, "materiais")
BAIXADOS = os.path.join(TOOLS, "_baixados")
OFFICE = {"pptx", "docx", "xlsx"}


def carregar(pasta):
    ts = []
    for f in sorted(glob.glob(os.path.join(pasta, "**", "*.json"), recursive=True)):
        d = json.load(open(f, encoding="utf-8"))
        if isinstance(d.get("data"), dict) and "nome" not in d:  # formato {id, data:{...}}
            tid, d = d.get("id"), d["data"]
        else:
            tid = os.path.splitext(os.path.basename(f))[0]
        if "nome" in d:
            ts.append((tid, d))
    return ts


def ext_de(nome):
    return (str(nome).rsplit(".", 1)[-1] if "." in str(nome) else "bin").lower()


def faltando(pasta):
    os.makedirs(MATS, exist_ok=True)
    for tid, t in carregar(pasta):
        for m in t.get("materiais") or []:
            e = ext_de(m.get("nome"))
            alvo = f"{m['id']}.{e}"
            if not os.path.exists(os.path.join(MATS, alvo)):
                ids = m.get("ids") or [m["id"]]
                print(f"{m['id']}\t{e}\t{'b64' if m.get('enc') == 'b64' else 'direto'}\t{','.join(ids)}\t{m.get('nome')}")


def montar(pasta):
    os.makedirs(MATS, exist_ok=True)
    ts = carregar(pasta)
    usados = set()
    for tid, t in ts:
        for m in t.get("materiais") or []:
            e = ext_de(m.get("nome")); mid = m["id"]
            alvo = os.path.join(MATS, f"{mid}.{e}")
            usados.add(f"{mid}.{e}")
            if e in OFFICE: usados.add(f"{mid}.pdf")
            if not os.path.exists(alvo):
                ids = m.get("ids") or [mid]
                partes = []
                for i in ids:
                    achados = glob.glob(os.path.join(BAIXADOS, i + ".*"))
                    if not achados:
                        print(f"AVISO: anexo {i} ({m.get('nome')}) não foi baixado; pulando", file=sys.stderr); partes = None; break
                    partes.append(open(achados[0], "rb").read())
                if partes is None: continue
                dados = b"".join(partes)
                if m.get("enc") == "b64":
                    dados = base64.b64decode(re.sub(rb"\s+", b"", dados))
                open(alvo, "wb").write(dados)
            if e in OFFICE and not os.path.exists(os.path.join(MATS, f"{mid}.pdf")):
                subprocess.run(["soffice", "--headless", "--convert-to", "pdf", "--outdir", MATS, alvo],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=600)
    for fn in os.listdir(MATS):
        if fn not in usados:
            os.remove(os.path.join(MATS, fn))
    shutil.rmtree(BAIXADOS, ignore_errors=True)

    disp = set(os.listdir(MATS))
    saida = []
    for tid, t in ts:
        parts = t.get("participantes") or []
        mats = []
        for m in t.get("materiais") or []:
            e = ext_de(m.get("nome")); mid = m["id"]
            item = {"nome": m.get("nome"), "tamanho": m.get("tamanho"), "enviadoEm": m.get("enviadoEm"), "tipo": m.get("tipo")}
            if e == "pdf":
                item["pdf"] = item["arquivo"] = f"materiais/{mid}.pdf" if f"{mid}.pdf" in disp else None
            else:
                item["pdf"] = f"materiais/{mid}.pdf" if f"{mid}.pdf" in disp else None
                if f"{mid}.{e}" in disp:
                    item["orig"] = f"materiais/{mid}.{e}"
                    if e not in OFFICE and not item["pdf"]: item["pdf"] = item["orig"]
            mats.append(item)
        saida.append({"id": tid, **{k: t.get(k, "") for k in ["nome", "tipo", "assunto", "data", "hora", "cargaHoraria", "local", "publico", "facilitador", "conteudo"]},
                      "participantes": [{"nome": p.get("nome", ""), "setor": p.get("setor", "")} for p in parts],
                      "chamada": sorted([{"setor": p.get("setor", ""), "presenca": p.get("presenca")} for p in parts], key=lambda x: (x["setor"], str(x["presenca"]))),
                      "materiais": mats})

    gerar_ics(ts)
    agora = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=-3))).strftime("%d/%m/%Y %H:%M")
    snap = json.dumps({"geradoEm": agora, "treinamentos": saida}, ensure_ascii=False).replace("</", "<\\/")
    src = open(os.path.join(TOOLS, "page.src.html"), encoding="utf-8").read()
    page = src.replace("__LOGO__", open(os.path.join(TOOLS, "logo.b64")).read().strip()).replace("__LOGO2__", open(os.path.join(TOOLS, "logo2.uri")).read().strip())
    page = page.replace("<script>\nconst LOGO", f"<script>window.__SNAP={snap};</script>\n<script>\nconst LOGO", 1)
    page = page.replace("<title>Treinamentos Mavaular</title>", "<title>Portal de Treinamentos</title>", 1)
    page = re.sub(r'<script src="https://cdnjs\.cloudflare\.com/ajax/libs/jspdf/[^"]+"></script>\n?', "", page)
    doc = ('<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">'
           '<style>:root{padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}body{margin:0;font:14px system-ui,sans-serif}img{max-width:100%}[hidden]{display:none!important}</style></head><body>'
           + page + '</body></html>')
    open(os.path.join(SITE, "index.html"), "w", encoding="utf-8").write(doc)
    print(f"ok: {len(saida)} treinamentos, {sum(len(t['materiais']) for t in saida)} materiais, atualizado em {agora}")


PORTAL_URL = "https://treinamentos-mavaular.netlify.app"
VTZ = ["BEGIN:VTIMEZONE", "TZID:America/Sao_Paulo", "BEGIN:STANDARD", "DTSTART:19700101T000000",
       "TZOFFSETFROM:-0300", "TZOFFSETTO:-0300", "TZNAME:-03", "END:STANDARD", "END:VTIMEZONE"]


def _esc(t):
    return str(t or "").replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace("\r", "").replace("\n", "\\n")


def _fold(linha):
    b = linha.encode("utf-8"); out = []
    while len(b) > 74:
        corte = 74
        while (b[corte] & 0xC0) == 0x80: corte -= 1
        out.append(b[:corte].decode("utf-8")); b = b" " + b[corte:]
    out.append(b.decode("utf-8"))
    return "\r\n".join(out)


def _duracao_min(carga):
    txt = str(carga or "").lower().replace(",", ".")
    h = re.search(r"(\d+(?:\.\d+)?)\s*h", txt); m = re.search(r"(\d+)\s*min", txt)
    tot = (float(h.group(1)) * 60 if h else 0) + (int(m.group(1)) if m else 0)
    return int(tot) if tot > 0 else 60


def _vevent(tid, t, carimbo):
    data = str(t.get("data") or "")
    if not re.match(r"\d{4}-\d{2}-\d{2}$", data): return []
    d = data.replace("-", ""); hora = str(t.get("hora") or "")
    ev = ["BEGIN:VEVENT", f"UID:{tid}@treinamentos-mavaular", f"DTSTAMP:{carimbo}",
          f"SUMMARY:{_esc('Treinamento: ' + str(t.get('nome', '')))}"]
    if re.match(r"\d{2}:\d{2}$", hora):
        ini = datetime.datetime.strptime(data + hora, "%Y-%m-%d%H:%M")
        fim = ini + datetime.timedelta(minutes=_duracao_min(t.get("cargaHoraria")))
        ev += [f"DTSTART;TZID=America/Sao_Paulo:{ini:%Y%m%dT%H%M%S}", f"DTEND;TZID=America/Sao_Paulo:{fim:%Y%m%dT%H%M%S}"]
        alarmes = [("-PT1H", "Treinamento em 1 hora"), ("-P1D", "Treinamento amanhã")]
    else:
        fim = datetime.date.fromisoformat(data) + datetime.timedelta(days=1)
        ev += [f"DTSTART;VALUE=DATE:{d}", f"DTEND;VALUE=DATE:{fim:%Y%m%d}"]
        alarmes = [("-PT15H", "Treinamento amanhã")]
    if t.get("local"): ev.append(f"LOCATION:{_esc(t['local'])}")
    desc = [f"Assunto: {t['assunto']}" if t.get("assunto") else "", f"Público: {t['publico']}" if t.get("publico") else "",
            f"Facilitador: {t['facilitador']}" if t.get("facilitador") else "", f"Carga horária: {t['cargaHoraria']}" if t.get("cargaHoraria") else "",
            f"Detalhes e materiais: {PORTAL_URL}/#t-{tid}"]
    ev.append(f"DESCRIPTION:{_esc(chr(10).join(x for x in desc if x))}")
    ev.append(f"URL:{PORTAL_URL}/#t-{tid}")
    for gatilho, texto in alarmes:
        ev += ["BEGIN:VALARM", "ACTION:DISPLAY", f"TRIGGER:{gatilho}", f"DESCRIPTION:{_esc(texto + ': ' + str(t.get('nome', '')))}", "END:VALARM"]
    ev.append("END:VEVENT")
    return ev


def _calendario(eventos, nome):
    linhas = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Mavaular//Treinamentos//PT", "CALSCALE:GREGORIAN", "METHOD:PUBLISH",
              f"X-WR-CALNAME:{_esc(nome)}", "X-WR-TIMEZONE:America/Sao_Paulo", "REFRESH-INTERVAL;VALUE=DURATION:PT1H",
              "X-PUBLISHED-TTL:PT1H"] + VTZ + eventos + ["END:VCALENDAR"]
    return "\r\n".join(_fold(l) for l in linhas) + "\r\n"


def gerar_ics(ts):
    carimbo = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    pasta = os.path.join(SITE, "agenda"); shutil.rmtree(pasta, ignore_errors=True); os.makedirs(pasta)
    todos = []
    for tid, t in ts:
        ev = _vevent(tid, t, carimbo)
        if not ev: continue
        todos += ev
        open(os.path.join(pasta, f"{tid}.ics"), "w", encoding="utf-8", newline="").write(_calendario(ev, "Treinamentos Mavaular"))
    open(os.path.join(SITE, "agenda.ics"), "w", encoding="utf-8", newline="").write(_calendario(todos, "Treinamentos Mavaular"))


if __name__ == "__main__":
    if len(sys.argv) < 3 or sys.argv[1] not in ("faltando", "montar"):
        print(__doc__); sys.exit(1)
    (faltando if sys.argv[1] == "faltando" else montar)(sys.argv[2])
