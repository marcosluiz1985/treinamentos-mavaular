# Como atualizar o Portal de Treinamentos

Fonte dos dados: site de gestão https://claude.ai/artifact/FREb37xtySyurUT9eSXUK1
(coleção `treinamentos` do banco do artifact; anexos ficam no armazenamento de arquivos do artifact).

1. `ArtifactData` → action `list`, collection `treinamentos`, `out_dir` = uma pasta temporária (ex.: `/tmp/snap`).
2. `python3 tools/atualizar.py faltando /tmp/snap/treinamentos`
   Cada linha: `<id>  <ext>  <b64|direto>  <ids das partes, separados por vírgula>  <nome>`.
3. Para cada id de parte listado: `Artifact` → action `read`, `url` do site de gestão, `path` = id da parte,
   `out_dir` = `tools/_baixados`. (O arquivo salvo se chama `<id>.<ext>`; o script acha pelo id.)
4. `python3 tools/atualizar.py montar /tmp/snap/treinamentos`
   Decodifica os anexos, gera PDF dos .pptx/.docx/.xlsx com LibreOffice, apaga anexos removidos e regera `site/index.html` e a agenda (`site/agenda.ics` + `site/agenda/<id>.ics`).
5. `git add -A && git commit -m "Atualiza portal" && git push` — o Netlify publica sozinho em ~1 minuto.

Nunca publicar faltas por pessoa no portal: o script já grava só setor+presença (sem nome) para os indicadores.
