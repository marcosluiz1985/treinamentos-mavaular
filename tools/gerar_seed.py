"""Gera seed/dados.mjs com os dados do sistema anterior (site de gestão no Claude).

Uso: python3 tools/gerar_seed.py <pasta_json_treinamentos> <colaboradores.json> <pasta_anexos>
  - pasta_json_treinamentos: exportação da coleção "treinamentos" (inclui subpastas por pessoa)
  - colaboradores.json: documento cadastro/colaboradores
  - pasta_anexos: arquivos <id do anexo>.<ext> baixados do site antigo (texto base64 ou binário)
"""
import base64, glob, json, os, re, sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main(pasta, cad, anexos):
    ts, mats = [], {}
    for f in sorted(glob.glob(os.path.join(pasta, "**", "*.json"), recursive=True)):
        d = json.load(open(f, encoding="utf-8"))
        if "nome" not in d:
            continue
        tid = os.path.splitext(os.path.basename(f))[0]
        novos = []
        for m in d.get("materiais") or []:
            partes = []
            for pid in m.get("ids") or [m["id"]]:
                achados = glob.glob(os.path.join(anexos, pid + ".*"))
                if not achados:
                    print("AVISO: anexo não encontrado:", pid, m.get("nome"), file=sys.stderr); partes = None; break
                partes.append(open(achados[0], "rb").read())
            if partes is None:
                continue
            dados = b"".join(partes)
            if m.get("enc") == "b64":
                dados = base64.b64decode(re.sub(rb"\s+", b"", dados))
            mats[f"materiais/{tid}/{m['id']}/0"] = base64.b64encode(dados).decode()
            novos.append({"id": m["id"], "nome": m.get("nome"), "tipo": m.get("tipo") or "application/octet-stream",
                          "tamanho": len(dados), "partes": 1, "enviadoEm": m.get("enviadoEm")})
        t = {k: d.get(k, "") for k in ["nome", "tipo", "assunto", "data", "hora", "cargaHoraria", "local", "publico", "facilitador", "conteudo", "criadoEm"]}
        t["id"] = tid
        t["participantes"] = [{"nome": p.get("nome", ""), "setor": p.get("setor", ""), "presenca": p.get("presenca")} for p in d.get("participantes") or []]
        t["materiais"] = novos
        ts.append(t)
    c = json.load(open(cad, encoding="utf-8"))
    c = c.get("data", c) if isinstance(c.get("data"), dict) else c
    colab = {"lista": c.get("lista", []), "origem": c.get("origem", ""), "atualizadoEm": c.get("atualizadoEm", "")}
    os.makedirs(os.path.join(RAIZ, "seed"), exist_ok=True)
    with open(os.path.join(RAIZ, "seed", "dados.mjs"), "w", encoding="utf-8") as out:
        out.write("// Dados migrados do sistema anterior (carregados uma única vez na primeira execução)\n")
        out.write("export const SEED = " + json.dumps({"treinamentos": ts, "colaboradores": colab}, ensure_ascii=False) + ";\n")
        out.write("export const MATERIAIS = " + json.dumps(mats) + ";\n")
    print(f"seed: {len(ts)} treinamentos, {len(colab['lista'])} colaboradores, {len(mats)} anexos")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        print(__doc__); sys.exit(1)
    main(*sys.argv[1:])
