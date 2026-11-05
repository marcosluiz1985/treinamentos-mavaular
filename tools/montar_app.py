"""Monta site/index.html a partir de tools/app.src.html (insere os logos)."""
import os
R = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
T = os.path.join(R, "tools")
s = open(os.path.join(T, "app.src.html"), encoding="utf-8").read()
s = s.replace("__LOGO__", open(os.path.join(T, "logo.b64")).read().strip()).replace("__LOGO2__", open(os.path.join(T, "logo2.uri")).read().strip())
doc = ('<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">'
       '<style>:root{padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}body{margin:0;font:14px system-ui,sans-serif}img{max-width:100%}[hidden]{display:none!important}</style></head><body>'
       + s + '</body></html>')
open(os.path.join(R, "site", "index.html"), "w", encoding="utf-8").write(doc)
print("site/index.html", len(doc))
