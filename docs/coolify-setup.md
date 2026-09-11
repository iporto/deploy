# Coolify — do zero ao primeiro deploy

> **Data:** 2026-09-11 · **Escopo:** criar o destino da trilha 2 de
> [`deployment-targets.md`](deployment-targets.md). Cada passo aparece **no
> painel e por API**, lado a lado.
>
> Se você ainda não escolheu a trilha, leia
> [`deployment-targets.md`](deployment-targets.md) primeiro — Coolify é uma
> opção, não o caminho obrigatório.

Este é o pedaço do processo que mais erra na mão, porque é clicar em seis telas
e sair de lá com um identificador copiado da barra de endereços. **A API faz
tudo isso, e devolve o identificador em vez de você copiar.** Use o painel para
entender o que está montando; use a API para montar de verdade.

---

## O mapa dos identificadores

Metade da confusão é não saber quantos uuid diferentes existem. São cinco, e
**só um deles vai para o seu repositório**:

| Identificador | O que é | Onde vive depois |
|---|---|---|
| **token da API** | credencial sua no Coolify | segredo `COOLIFY_TOKEN` no repo de deploy |
| **URL do painel** | ex. `https://coolify.meudominio.com` | segredo `COOLIFY_URL` |
| `project_uuid` | o projeto (a pasta que agrupa os apps) | em lugar nenhum — só no momento da criação |
| `server_uuid` | o servidor que roda os containers | em lugar nenhum |
| **`uuid` da application** | **o recurso de um app** | ⭐ `coolify_uuid` no `build.<app>.yml` |

> ⚠️ **Só a última linha é o "COOLIFY_UUID" de que a esteira fala.** É a que as
> pessoas erram: copiam o uuid do *projeto*, o deploy responde 404 e o erro não
> diz qual uuid estava errado.

E um sexto que aparece só em servidor com mais de uma rede: `destination_uuid`.
Com um servidor e uma rede, você não precisa dele.

---

## Antes de começar

- [ ] Uma instância do Coolify no ar, com domínio e HTTPS no painel.
- [ ] Ao menos um servidor conectado (pode ser o próprio host do Coolify).
- [ ] A imagem **já publicada** no GHCR. Rode o build uma vez com
      `coolify_uuid: ''` — ele publica e não tenta deploy. Sem imagem no
      registry, o recurso nasce quebrado e você depura duas coisas ao mesmo tempo.
- [ ] O DNS do domínio público apontando para o IP do servidor de workload.
      Faça isso **antes**: a emissão do certificado acontece no primeiro deploy.

Confira que a imagem existe antes de continuar:

```bash
docker manifest inspect ghcr.io/<owner>/<projeto>-<app>:prd >/dev/null \
  && echo "imagem no ar"
```

---

## 1. O token da API

**Painel:** canto inferior esquerdo → *Keys & Tokens* → *API tokens* → *Create
New Token*. Marque as permissões de **read**, **write** e **deploy** — cada
endpoint exige a sua, e um token só de leitura falha no `POST` com uma mensagem
que parece de autenticação.

O token aparece **uma vez**. Guarde-o direto nos segredos do repositório de
deploy, como `COOLIFY_TOKEN`, junto de `COOLIFY_URL` (a URL do painel, **sem
barra no fim** — com barra, as chamadas viram `//api/v1/...` e dão 404).

Daqui em diante os exemplos assumem:

```bash
export COOLIFY_URL="https://coolify.meudominio.com"    # sem barra no fim
export COOLIFY_TOKEN="…"

# api <método> <caminho> [corpo-json]
api() {
  local m="$1" path="$2" body="${3-}"
  if [ -n "$body" ]; then
    curl -fsS -X "$m" "${COOLIFY_URL}/api/v1${path}" \
      -H "Authorization: Bearer ${COOLIFY_TOKEN}" \
      -H "Content-Type: application/json" -d "$body"
  else
    curl -fsS -X "$m" "${COOLIFY_URL}/api/v1${path}" \
      -H "Authorization: Bearer ${COOLIFY_TOKEN}"
  fi
}
```

> Precisa de **`jq`** daqui para baixo (`brew install jq` · `apt install jq`).
> Montar e ler JSON com `sed` funciona até o primeiro valor com vírgula dentro.

Teste antes de seguir — se isto falhar, nada adiante funciona:

```bash
api GET /servers | head -c 200
```

---

## 2. O projeto e o ambiente

Um **projeto** agrupa os apps de um produto; dentro dele há **ambientes**
(`production` é o que vem por padrão).

**Painel:** *Projects* → *+ Add* → nome do produto.

**API:**

```bash
api GET /projects          # ver os que existem
api POST /projects '{"name":"meuprojeto","description":"SaaS do cliente X"}'
```

Guarde o `uuid` que voltar:

```bash
PROJECT_UUID="…"
ENVIRONMENT="production"
```

---

## 3. O servidor

**Painel:** *Servers* — se você instalou o Coolify numa VM só, já existe um
chamado `localhost`.

**API:**

```bash
api GET /servers    # devolve uuid, name e ip de cada um
SERVER_UUID="…"
```

> Escolha pelo **ip**, não pelo nome. "localhost" num painel que você acessa de
> fora é o host do próprio Coolify — o que costuma estar certo em instalação
> pequena e errado em instalação com workload separado.

---

## 4. Deixar o servidor puxar do GHCR

O recurso vai apontar para `ghcr.io/...`. Se o pacote for **privado**, o
servidor precisa de credencial — e este é o passo que falha depois, no deploy,
com `manifest unknown` ou `denied`, que não menciona autenticação.

O caminho que funciona em qualquer versão, **no servidor de workload**:

```bash
echo "$GHCR_TOKEN" | docker login ghcr.io -u <seu-usuario> --password-stdin
```

Use um token com **apenas** `read:packages`.

> Dependendo da versão, o painel também oferece um cadastro de registry privado.
> Se a sua tiver, use — é o mesmo efeito com o segredo guardado no painel em vez
> de no `~/.docker/config.json` do servidor.

Alternativa sem credencial nenhuma: tornar o pacote público em
*GitHub → Packages → Package settings → Change visibility*. A imagem é pública,
o código não — mas qualquer um passa a poder baixar o build. Decisão sua.

---

## 5. Criar o recurso — onde nasce o `coolify_uuid`

**Este é o passo que o título deste documento promete.**

**Painel:** dentro do projeto → *+ New Resource* → **Docker Image** (não
*Public Repository*, não *Dockerfile* — a imagem já está pronta, o Coolify não
constrói nada). Preencha a imagem, a tag `prd`, a porta e o domínio. Depois
copie o uuid **da barra de endereços**: é o último segmento da URL do recurso.

**API — e aqui você não copia nada, ele devolve:**

```bash
APP_UUID=$(api POST /applications/dockerimage "$(cat <<JSON
{
  "project_uuid": "${PROJECT_UUID}",
  "server_uuid": "${SERVER_UUID}",
  "environment_name": "${ENVIRONMENT}",
  "name": "www",
  "docker_registry_image_name": "ghcr.io/<owner>/<projeto>-www",
  "docker_registry_image_tag": "prd",
  "ports_exposes": "80",
  "domains": "https://www.meudominio.com",
  "is_force_https_enabled": true,
  "instant_deploy": false
}
JSON
)" | jq -r '.uuid')

echo "      coolify_uuid: '${APP_UUID}'"      # a linha pronta para o build.<app>.yml
```

O que cada campo decide:

| Campo | Nota |
|---|---|
| `docker_registry_image_tag` | **`prd`**, sempre. Não fixe uma `sha-` aqui: é isso que quebra o rollback — ver [`production-pipeline.md`](production-pipeline.md#voltar-atrás) |
| `ports_exposes` | a porta **dentro** do container. Nas imagens desta biblioteca é `80` (nginx). Errar aqui dá 502 no proxy, não erro no deploy |
| `domains` | com `https://` e sem caminho. Vários, separados por vírgula |
| `instant_deploy` | `false` — os envs ainda não existem. Suba no passo 9 |

---

## 6. Os envs

**Painel:** aba *Environment Variables* do recurso.

**API, a partir de um arquivo** — é o formato que deixa o bloco de env versionado
fora do painel, que é o ponto fraco desta trilha:

```bash
# envs.prd — uma linha KEY=VALUE por variável. NÃO commite este arquivo.
api PATCH "/applications/${APP_UUID}/envs/bulk" "$(
  jq -nR --rawfile f envs.prd '{data: ($f
    | split("\n")
    | map(select(test("^[A-Za-z_][A-Za-z0-9_]*=")))
    | map(capture("^(?<key>[^=]+)=(?<value>.*)$") + {is_preview:false}))}'
)"
```

Confira o que subiu — e note que a API **devolve os valores**, então não jogue
isso num log:

```bash
api GET "/applications/${APP_UUID}/envs" | jq -r '.[].key'
```

> ⚠️ **`APP_KEY` e companhia entram aqui, não no repositório.** É o mesmo motivo
> da varredura do build: env em texto puro no git é o vazamento mais comum desta
> casa. Gere o `APP_KEY` na hora (`php artisan key:generate --show` dentro de um
> container) e cole só aqui.

Variáveis de build do Vite (`VITE_*`) **não** vão aqui: elas precisam existir no
momento do `npm run build`, que acontece no GitHub Actions. Ver o
`.env.build` em [`production-pipeline.md`](production-pipeline.md).

---

## 7. Papéis que dividem a mesma imagem

A imagem da API serve três processos, escolhidos por `CONTAINER_ROLE`:

| Papel | `CONTAINER_ROLE` | Processo |
|---|---|---|
| Web | *(vazio)* | supervisord → nginx + php-fpm |
| Worker | `worker` | `php artisan horizon` |
| Scheduler | `scheduler` | `php artisan schedule:work` |

São **três recursos**, mesma imagem, `CONTAINER_ROLE` diferente. Worker e
scheduler não expõem porta nem domínio.

Os três uuid vão juntos no mesmo campo, separados por vírgula — o build avisa os
três no mesmo push:

```yaml
      coolify_uuid: 'abc123,def456,ghi789'
```

---

## 8. Colar o uuid no repositório

No repositório de **deploy**, em `.github/workflows/build.<app>.yml`:

```yaml
      coolify_uuid: 'abc123'
```

Commit e push. **Não é segredo** — sozinho ele não autoriza nada; quem autoriza
é o `COOLIFY_TOKEN`. Versionado, você vê num `git log` quando o destino de um app
mudou, que é a pergunta que ninguém consegue responder quando isso vive em
*Settings → Secrets*.

---

## 9. O primeiro deploy

```bash
api POST "/deploy?uuid=${APP_UUID}&force=false"
```

Ou, o que a esteira faz sozinha a partir de agora: um push na `main` do repo do
app.

Confira, nesta ordem — cada item falha por um motivo diferente:

- [ ] O deploy aparece na aba *Deployments* do recurso e termina verde
- [ ] `docker ps` no servidor mostra o container com a imagem `:prd`
- [ ] O domínio responde em **HTTPS**, com certificado válido
- [ ] Uma fila processa (se houver worker) e o `schedule:work` está vivo
- [ ] `docker logs` sem erro de env faltando no boot

---

## O script inteiro

Junta os passos 2 a 5 e imprime a linha pronta para colar no `build.<app>.yml`:

```bash
#!/usr/bin/env bash
set -euo pipefail
: "${COOLIFY_URL:?defina a URL do painel}" "${COOLIFY_TOKEN:?defina o token}"
OWNER="$1" PROJETO="$2" APP="$3" DOMINIO="$4"

api() {
  local m="$1" path="$2" body="${3-}"
  if [ -n "$body" ]; then
    curl -fsS -X "$m" "${COOLIFY_URL}/api/v1${path}" \
      -H "Authorization: Bearer ${COOLIFY_TOKEN}" \
      -H "Content-Type: application/json" -d "$body"
  else
    curl -fsS -X "$m" "${COOLIFY_URL}/api/v1${path}" \
      -H "Authorization: Bearer ${COOLIFY_TOKEN}"
  fi
}

# ⚠️ Pega o PRIMEIRO servidor. Com mais de um, troque por
#    jq -r --arg ip "1.2.3.4" '.[] | select(.ip==$ip) | .uuid'
SERVER_UUID=$(api GET /servers | jq -r '.[0].uuid')

PROJECT_UUID=$(api GET /projects | jq -r --arg n "$PROJETO" \
                 'first(.[] | select(.name==$n) | .uuid) // empty')
[ -n "$PROJECT_UUID" ] || PROJECT_UUID=$(
  api POST /projects "$(jq -nc --arg n "$PROJETO" '{name:$n}')" | jq -r '.uuid')

APP_UUID=$(api POST /applications/dockerimage "$(jq -nc \
    --arg p "$PROJECT_UUID" --arg s "$SERVER_UUID" --arg a "$APP" \
    --arg img "ghcr.io/${OWNER}/${PROJETO}-${APP}" --arg d "https://${DOMINIO}" '
  { project_uuid: $p, server_uuid: $s, environment_name: "production",
    name: $a, docker_registry_image_name: $img, docker_registry_image_tag: "prd",
    ports_exposes: "80", domains: $d, is_force_https_enabled: true,
    instant_deploy: false }')" | jq -r '.uuid')

echo "      coolify_uuid: '${APP_UUID}'"
```

> Ele **não é idempotente**: rodar duas vezes cria dois recursos. Confira em
> *Projects* antes de repetir.

---

## Armadilhas

| Sintoma | Causa |
|---|---|
| `404` no `POST /deploy` | uuid do **projeto** no lugar do uuid da **application** |
| `404` em toda chamada | `COOLIFY_URL` com barra no fim → `//api/v1/...` |
| `This endpoint has changed to a POST request` | chamada com `GET`; a partir da v4.2.0 os endpoints que mudam estado são POST-only |
| `manifest unknown` / `denied` no pull | pacote privado e servidor sem `docker login ghcr.io` |
| `image ... not found` | recurso apontando para `:latest`, que **não publicamos** por decisão |
| 502 no domínio, deploy verde | `ports_exposes` diferente da porta que o container escuta |
| Certificado não emite | DNS não apontava para o servidor no momento do primeiro deploy |
| Deploy verde, código velho | dois recursos com o mesmo domínio, ou `coolify_uuid` de outro app |
| Container recriando sozinho | Watchtower **e** Coolify no mesmo container — escolha um |
| `401` só nos `POST` | token criado sem permissão de write/deploy |

---

## Replicação

Para o próximo app do mesmo projeto: passos 5, 6 e 8 — o projeto, o servidor e o
token já existem.

Para o próximo projeto: tudo, trocando `PROJECT_UUID`. O `COOLIFY_URL` e o
`COOLIFY_TOKEN` são por instância, não por projeto: repita os **segredos** em
cada repositório de deploy.

## Checklist de auditoria

- [ ] Nenhum recurso com tag fixa `sha-…` — todos em `:prd`
- [ ] Nenhum recurso apontando para `:latest`
- [ ] `coolify_uuid` no `build.<app>.yml` bate com o recurso certo
- [ ] Token da API com escopo mínimo, e rotacionado quando alguém sai do time
- [ ] Bloco de env de cada recurso guardado também fora do painel
- [ ] Servidor de workload com `docker login ghcr.io` válido (ou pacote público)
- [ ] Compose do projeto **sem** Watchtower nesta trilha
