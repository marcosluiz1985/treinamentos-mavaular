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


if __name__ == "__main__":
    if len(sys.argv) < 3 or sys.argv[1] not in ("faltando", "montar"):
        print(__doc__); sys.exit(1)
    (faltando if sys.argv[1] == "faltando" else montar)(sys.argv[2])
