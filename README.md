# Treinamentos Mavaular

Site: https://treinamentos-mavaular.netlify.app

- Qualquer pessoa vê a agenda, os treinamentos, os indicadores e baixa os materiais.
- Para cadastrar, fazer a chamada e anexar materiais é preciso entrar com usuário e senha.
- Cada usuário altera só os treinamentos que cadastrou; administradores alteram tudo e gerenciam usuários.

## Estrutura
- `site/index.html` — o site (gerado a partir de `tools/app.src.html` com `python3 tools/montar_app.py`)
- `netlify/functions/api.mjs` — API (login, treinamentos, cadastro, materiais e agenda .ics), dados no Netlify Blobs
- `seed/dados.mjs` — dados migrados do sistema anterior, carregados uma única vez
- `avisador/` e `site/avisador*` — avisador de treinamentos para Windows (lê `/agenda.ics`)

Variáveis de ambiente no Netlify: `SESSION_SECRET` (assinatura das sessões) e `SETUP_CODE` (criação do primeiro administrador).
