# O ambiente de desenvolvimento — desenho e decisões

> **Data:** 2026-09-09 (rev. 11 — **executado e validado**)
> **Status:** todo o plano foi implementado e o fluxo foi validado duas vezes em VM
> limpa, do clone ao painel logado. O que segue é registro, não pendência.
> **Premissa que guiou tudo:** **se 72 pessoas baixarem o starter kit em 72
> computadores, as 72 sobem o ambiente localmente e desenvolvem.** Docker remoto
> por contexto é conveniência de quem mantém, não requisito.
> **Escopo:** o desenho do ambiente de desenvolvimento desta biblioteca e as
> decisões que o produziram.
> Não cobre a trilha de produção — ela está em
> [`production-pipeline.md`](production-pipeline.md), nesta mesma pasta.

---

## 1. O problema

Hoje um produto do kit (Fábrica de Lead, Try Psst) sobe assim: o `docker-compose.dev.yml`
do `deploy.<projeto>` cria os containers do projeto e os pendura numa rede Docker externa
chamada `shared`, onde já existem um Traefik roteando e os serviços de apoio.

Essa rede e o que vive nela **não estão no repositório do projeto**. Estão em
o repositório de infraestrutura interno, que é privado. Um dev de fora que clonar o kit sobe os
containers e não acontece nada: nada roteia, nada conecta.

### As três camadas

| Camada | Onde morava | Provê | Era público? |
|---|---|---|---|
| 1. Roteamento | repositório de infraestrutura interno | Traefik | ❌ |
| 2. Serviços de apoio | idem | `infra-mysql` (MariaDB), `infra-redis`, `infra-mail` (Mailpit) e outros | ❌ |
| 3. O projeto | `deploy.<projeto>` | nginx, php, php-api, php-console, env-platform, env-www | ✅ |

> ✅ **Resolvido.** As camadas 1 e 2 passaram a viver na biblioteca pública, como
> `infra/` + o comando `deploy-infra` — ver §4.1.

O `nginx` do projeto **não expõe porta** — depende inteiramente do Traefik da camada 1.

---

## 2. Estado — tudo entregue

Na biblioteca `iporto/deploy` (pública):

| Peça | Estado |
|---|---|
| `deploy-infra` (`up`/`createdb`/`status`/`down`/`logs`/`reset`) | ✅ |
| `infra/` — Traefik, MariaDB, Redis, Mailpit + proxy de socket | ✅ |
| `deploy-doctor` — verificação de pré-voo | ✅ |
| `deploy-scaffold-project --from-kit` | ✅ |
| `deploy-scaffold-app` | ✅ |
| `deploy-shim-install --verbs` | ✅ |
| `deploy-run dev` por contexto, com sync condicional | ✅ |

No kit: README com quickstart validado, `dev:token` sem domínio fixo, dois briefs
fictícios de exemplo no lugar dos de produtos reais.

**Ambos os repositórios são públicos e clonáveis.**

### Validação

Fluxo completo executado **duas vezes** em VM restaurada do zero (Ubuntu 24.04,
x86_64, 2 CPUs, 4 GB de RAM), seguindo o README literalmente:

```
clone → doctor → infra up → createdb → scaffold --from-kit → hosts
→ deploy-run dev → migrate → dev:token → dev-login → HTTP 200 <title>Painel
```

**Consumo medido:** 12 GB de disco e 1,0 GB de RAM com tudo no ar. Daí o
requisito de 20 GB no README — 11 GB não bastam, e foi o que travou a primeira
tentativa.

## 3. Decisões tomadas (2026-09-09)

| Tema | Decisão | Por quê |
|---|---|---|
| Camadas 1 e 2 | **vivem na biblioteca**, com o comando `deploy-infra` | Sobe **uma vez por máquina**, não uma por produto — é infra de estação de trabalho, não de projeto. A biblioteca já é pública e já é a dependência comum de todo projeto |
| A topologia interna de quem mantém | **fora do desenho do kit** | Segue existindo à parte; o kit não a referencia nem depende dela |
| Escopo do kit público | **Apps + gerador** | O kit fica enxuto; o `deploy.<projeto>` nasce com o nome do produto do adotante |
| Verbos no projeto gerado | **`deploy-run`, `deploy-sync` e `deploy-mutagen`** | Os outros pertencem ao aparato antigo e não fazem nada na trilha Coolify. O `deploy-mutagen` entra mesmo com o alvo padrão sendo Docker local: quem aponta para daemon remoto precisa dele, e com daemon local ele mesmo avisa que não é necessário |

### Revisão de 2026-09-10 — onde o build acontece

| Tema | Decisão | Por quê |
|---|---|---|
| Build da imagem | **centralizado no repositório de deploy** | Foi revertido: a versão anterior punha o Dockerfile em cada repo de app. Isso tinha entrado junto com a decisão do Coolify **como se fosse consequência dela**, e não era — no Coolify cada app é do tipo *Docker Image*, ele puxa imagem pronta e não se importa com quem construiu. Centralizado, um Dockerfile muda todos os apps num commit, e o contexto pode ser inspecionado antes do push |
| Credencial entre repositórios | **GitHub App**, não PAT | Centralizado precisa cruzar repositórios nos dois sentidos, e o `GITHUB_TOKEN` nunca sai do próprio repo. A escolha real era PAT pessoal ou App: o App emite token de 1 h, escopado, e não morre com uma pessoa |
| Tag que o destino observa | **`:prd`**, ao lado das imutáveis | O Coolify guarda uma `imagem:tag` fixa e re-puxa no webhook — sem ponteiro móvel seria preciso reconfigurá-lo a cada release. Não é `:latest` porque `:latest` é o que o Docker puxa sem se pedir tag |
| Varredura de segredo | **no contexto E na imagem pronta** | A do contexto confere a entrada; a da imagem confere a saída, e é a que pega um `COPY` largo demais. As duas juntas barraram, na estreia real, um `APP_KEY` de produção e uma chave privada do Passport que estavam versionados |

---

## 4. O desenho — e o porquê de cada decisão

> ✅ **Tudo nesta seção foi implementado.** Ela permanece porque registra o
> *raciocínio*: por que o `deploy-run dev` usa contexto e o `prd` não, por que o
> pin de plataforma sai de umas imagens e fica em outras, por que o `www` vive num
> profile. Quem for mexer nisso depois precisa do porquê, não só do quê.

### 4.1 `deploy-infra` — ajustes

```
Deploy-Scripts/
  deploy-infra                  o comando
  infra/docker-compose.yml      Traefik + MariaDB + Redis + Mailpit     ← era dev-infra/
  infra/.env.dev.example        template versionado                     ← era .env.example
  infra/.env.dev                valores locais, gitignored              ← era .env
```

| Mudança | Motivo |
|---|---|
| `dev-infra/` → **`infra/`** | nome mais curto; o "dev" já está implícito no comando |
| `.env.example` → **`.env.dev.example`** | mesma convenção dos projetos |
| `.env` → **`.env.dev`** | idem |
| **novo:** `deploy-infra createdb <nome>` | o dev não precisa saber criar banco e usuário no servidor |

```bash
deploy-infra up                    # sobe a base
deploy-infra createdb acme         # cria database + usuário + senha, e imprime as credenciais
deploy-infra status | down | logs | reset
```

> ✅ **O dev só ajusta o `.env.dev` da infra para subir o servidor base.** Tudo o que
> acontece *dentro* do MySQL — criar database, criar usuário, dar grant — é linha de
> comando. Ele nunca precisa abrir um cliente SQL nem saber a sintaxe.

O `createdb` imprime as credenciais no formato pronto para colar no `.env` do app:

```
DB_HOST=infra-mysql
DB_DATABASE=acme
DB_USERNAME=acme
DB_PASSWORD=<gerada>
```

### 4.2 Tirar o `platform: linux/amd64` — **só das imagens `iporto99/*`**

> 📌 **Nota de arquitetura.** O pin nas imagens de terceiros exige emulação em host arm64.
> Num Mac (Docker Desktop / OrbStack) existe a camada e funciona, mais lento. Numa **VM Linux
> arm64 sem qemu/binfmt**, o container **não sobe**. A VM de teste é x86_64 (mesma máquina do
> a VM de desenvolvimento: Ubuntu 24.04, x86_64), então o pin bate com o nativo — sem risco ali.
> Para devs externos em Apple Silicon o custo é desempenho, que é o trade-off aceito.

O compose fixa `platform: linux/amd64` nos 6 serviços. As duas imagens próprias —
`iporto99/php-8-3` e `iporto99/nginx` — **são multi-arch (amd64 + arm64)**, verificado no
registry. Nelas o pin só força emulação sem ganho.

> ❌ **Não remover das imagens de terceiros.** Decisão por experiência: já houve
> problema com Apple Silicon em imagens de terceiros, e perder desempenho é melhor do que
> perder dias procurando onde o erro mora. O pin fica onde protege.

| Imagem | Pin |
|---|---|
| `iporto99/php-8-3`, `iporto99/nginx` | ❌ remover — multi-arch confirmado |
| `traefik`, `mariadb`, `redis`, `mailpit` e demais terceiros | ✅ manter `linux/amd64` |

### 4.3 `deploy-scaffold-project --from-kit` — instanciar o kit como produto

✅ **Implementado.** Antes, o comando gerava o esqueleto e parava, deixando `code/`
vazio — era a origem de três dos bloqueios do teste real.

```bash
deploy-scaffold-project acme.com --from-kit ~/starter-kit --apply
```

Resultado:

```
deploy.acme.com/
  code/
    api.acme.com/          ← cópia de kit/code/api
    platform.acme.com/     ← cópia de kit/code/platform
    www.acme.com/          ← cópia de kit/code/www
  docker-compose.dev.yml
  .docker/{Nginx,Php}/
  .env.dev.example  .env.dev
  hosts  docs/coolify-deploy.md
  deploy-run  deploy-sync            ← só estes dois verbos (ver abaixo)
```

**Passo 1 — copiar os apps.** Sem `.git`, `vendor`, `node_modules` nem `.env`. São ~2,9 MB.
Os apps do kit são pastas dentro do repo do kit, não repositórios próprios: a cópia é limpa
e o dev inicia os repos dele depois, se quiser.

**Passo 2 — reescrever o `.env.example` de cada app.** É a raiz de dois bloqueios:

| Chave | Hoje no kit | Vira |
|---|---|---|
| `DB_HOST` | `127.0.0.1` | `infra-mysql` |
| `REDIS_HOST` | `127.0.0.1` | `infra-redis` |
| `MAIL_HOST` | — | `infra-mail` |
| `DB_DATABASE` | `starter_kit` | `acme` |
| `APP_URL` | `http://localhost` | `http://api.acme.io` |
| `APP_NAME` | `"Starter Kit API"` | `"Acme API"` |
| `VITE_URL`, `VITE_HMR_HOST` | `platform.spelt.kit` | `platform.acme.io` |

> ⚠️ `DB_HOST=127.0.0.1` é a armadilha silenciosa: dentro do container isso é o **próprio
> container**, não o MySQL. E como o `init-laravel.sh` copia `.env.example` → `.env`
> sozinho, o app sobe apontando para o lugar errado sem ninguém notar.

> ✅ Sensíveis (`DB_PASSWORD`, `REDIS_PASSWORD`) e as do Spelt (`SPELT_API_KEY`,
> `SPELT_WEBHOOK_SECRET`) continuam **vazias**. São do dev.

**Passo 3 — equipar os apps para build.** Rodar o `deploy-scaffold-app` nos apps copiados,
para nascerem com `Dockerfile`, `.deploy/` e `build.yml`.

**Passo 4 — só dois verbos.** Dos 9 que o `deploy-shim-install` instala hoje, 6 são do
aparato antigo (`deploy-promote`, `deploy-backup`, `harden-vm`, `deploy-token-check`,
`envedit`, `deploy-audit`) e não fazem nada na trilha Coolify. Ficam `deploy-run` e
`deploy-sync`. Exige uma flag `--verbs` no instalador.

**Passo 5 — o `www` fica no arquivo, desligado por `profile`.**

O `www` não entra na instalação base, mas precisa de um caminho para ser instalado depois —
um a um, ou todos de novo. Editar o YAML para isso seria cirurgia de texto em 4 lugares
(volume do nginx, alias de rede, regra do Traefik e o bloco `env-www`).

O Compose já resolve isso nativamente, e o compose do projeto **já usa a funcionalidade**
(todos os serviços têm `profiles: ["development"]`):

```yaml
env-www:
  profiles: ["development", "www"]     # inerte até alguém pedir
```

| | Descomentar YAML | `profiles` |
|---|---|---|
| Mecanismo | reescrever o arquivo | nativo |
| Ativar | comando edita o texto | `--profile www` |
| Reverter | recomentar, frágil | não passar a flag |

O volume do nginx e a regra do Traefik para `www` podem ficar sempre ligados: sem o
`www.conf`, o `_default.conf` responde. Instalar o `www` vira **copiar o app + adicionar o
`www.conf` + passar `--profile www`** — nenhuma edição de YAML.

### 4.3.1 🔴 A semântica de `./deploy-run <ambiente>` precisa mudar

✅ **Implementado.** Foi a mudança de maior impacto do plano.

Hoje o primeiro argumento significa *"faça SSH"*, não *"qual ambiente"*:

| Comando | Hoje |
|---|---|
| `./deploy-run` | modo local — lê `.env`, roda no daemon ativo |
| `./deploy-run dev` | modo **remoto** — lê `.env.dev` só para achar `REMOTE_HOST`, faz **SSH** e roda o `deploy-run` de dentro da VM |

O desenho pedido é outro: **o contexto executa, o SSH entrega arquivos.**

| Comando | Passa a ser |
|---|---|
| `./deploy-run dev` | lê **`.env.dev`**, roda `docker compose` no **contexto ativo** — sem SSH |
| `./deploy-sync dev` | leva os arquivos para a VM, quando o contexto é remoto |
| `./deploy-run prd` \| `stg` | **inalterado** — segue com SSH |
| `./deploy-run` (sem argumento) | **inalterado** — é como a VM roda a si mesma, lendo o `.env` entregue |

> ⚠️ **Por que `prd` não muda.** Se produção passasse a usar o contexto ativo, um
> `./deploy-run prd` com o contexto em a VM de desenvolvimento tentaria subir o compose de
> **produção na VM de desenvolvimento**. Produção tem um host definido no `.env.prd`, não
> "o contexto que por acaso está ativo". O SSH ali é proteção, não legado.

> ✅ **Isto também conserta um bug do plano:** o projeto gerado tem `.env.dev` mas não
> `.env`, e o `deploy-run` sem argumento aborta se o `.env` faltar. Com `./deploy-run dev`
> lendo `.env.dev`, o projeto novo funciona sem precisar de um `.env` duplicado.

> 📌 **Consequência para quem usa daemon remoto (não afeta o kit).** Se o contexto remoto exige
> `deploy-sync` para os arquivos chegarem, o loop de desenvolvimento remoto precisa de
> sincronia **contínua** — rodar `deploy-sync` a cada arquivo salvo é inviável. É o papel
> das 19 sessões de Mutagen: **elas continuam no desenho.** Para o kit isso é irrelevante:
> o alvo é Docker local, onde não há sincronia nenhuma.

### 4.3.2 `deploy-run dev` sincroniza antes — só no contexto remoto

**Mutagen não substitui o `deploy-sync`**, por três motivos:

1. Cobre só dev; produção precisa de entrega pontual com env decriptado.
2. **Sincroniza o lugar errado** — as sessões têm alpha em `code/<app>`. Elas não cobrem o
   `docker-compose.dev.yml`, o `.docker/Nginx/`, nem os envs.
3. Contínuo e pontual resolvem problemas diferentes.

O ponto 2 divide o trabalho:

| O que muda | Como chega na VM | Quando |
|---|---|---|
| Código do app | **Mutagen**, contínuo | a cada save |
| Compose, nginx, php.ini, envs | **`deploy-sync`** | quando são editados |

E como o `.rsyncignore` **exclui `code/`**, um `deploy-sync dev` transfere só a configuração:
é pequeno e rápido, e não duplica o trabalho do Mutagen.

**Decisão:**

| Comando | Sincroniza antes? |
|---|---|
| `./deploy-run dev`, contexto **local** | não — não há o que sincronizar |
| `./deploy-run dev`, contexto **remoto** | **sim**, automático — só a config |
| `./deploy-run prd` \| `stg` | **não** |

Com `--no-sync` para pular.

> ⚠️ **Por que produção não sincroniza automaticamente.** `./deploy-run prd env-app` hoje é
> "reinicie este serviço". Se passasse a sincronizar, um comando de reinício publicaria
> arquivos em produção — inclusive alterações em andamento que ninguém pretendia enviar.
> E já existe o caminho encadeado: `deploy prd` faz sync → run na ordem certa.

> ✅ O dev do kit nunca vê isso acontecer: rodando com Docker local, não há sincronia.

### 4.4 O mecanismo: `deploy-run` detecta o contexto Docker

**Este é o coração do desenho, e é pequeno.**

O `docker compose` já respeita o contexto Docker ativo: se o contexto aponta para
`ssh://a VM de desenvolvimento, os containers sobem na VM; se aponta para um socket local, sobem na
máquina. O `deploy-run` não precisa saber de nada disso — ele só chama `docker compose`.

A **única** coisa que quebra é o `REMOTE_BASE_PATH`. Ele não é "o caminho remoto": é **o
caminho do projeto do ponto de vista do daemon Docker**, e é o que os bind mounts usam. Com
daemon local, tem que ser o diretório do projeto na máquina; com daemon remoto, o caminho na VM.

Detectar isso é um comando:

```bash
docker context inspect --format '{{.Endpoints.docker.Host}}'
#   unix:// | npipe://  → daemon LOCAL  → REMOTE_BASE_PATH = $PWD
#   ssh://  | tcp://    → daemon REMOTO → REMOTE_BASE_PATH = o valor do .env
```

No `deploy-run`, logo após o `source .env`:

```bash
case "$(docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null)" in
  unix://*|npipe://*) REMOTE_BASE_PATH="$PWD"; export REMOTE_BASE_PATH ;;
esac
```

Com isso, `./deploy-run dev` funciona nos dois mundos sem o dev configurar nada:

| Contexto ativo | Onde sobe | `REMOTE_BASE_PATH` | Código |
|---|---|---|---|
| `orbstack`, `default`, Docker Desktop | máquina do dev | `$PWD` (automático) | lido direto do disco |
| `ssh://…` | VM | valor do `.env` | precisa de sincronia (`deploy-sync` ou Mutagen) |

> ✅ **Nenhuma mudança no `docker-compose.dev.yml`.** O mesmo arquivo serve aos dois mundos —
> era só a variável que estava mal explicada e sem default para o caso local.

> ⚠️ Ninguém roda assim hoje. O `gardenco` tem `127.0.0.1` no `hosts` mas caminho de VM no
> `REMOTE_BASE_PATH` — inconsistência de legado, não uso local funcionando. **Validar rodando**
> é item de trabalho.

### 4.5 Domínio de dev: o TLD, com os dados na mesa

Três candidatos foram medidos nesta máquina. O critério que mais pesa é o do `.dev`, que já
mordeu no passado: **TLD na lista HSTS preload faz o navegador forçar HTTPS**, e aí dev por
HTTP para de funcionar sem um certificado.

| TLD | HSTS preload | Falha de DNS | Observação |
|---|---|---|---|
| `.dev` | ⚠️ **preloaded** | — | ❌ o problema do certificado. Descartado |
| `.app` | ⚠️ **preloaded** | — | ❌ mesmo problema |
| `.local` | não | **10,1 s** | ❌ roteado para **mDNS/Bonjour**; nome inexistente demora 10s, e a rede local pode anunciar um `acme.local` concorrente |
| `.io` | não | 0,1 s | ⚠️ TLD **real** — sem a linha no `hosts`, o dev cai numa página da internet em vez de tomar erro |
| `.test` | não | 0,1 s | ✅ reservado pela **RFC 6761** para testes; nunca será domínio real, falha limpa |

**Limitações do `.test`** — a pergunta que motivou a comparação:

- **Não é HSTS preloaded.** Não tem o problema do `.dev`.
- **Barra de endereços:** como não é TLD público, o navegador pode tratar `acme.test`
  digitado como busca. Digitar `http://acme.test` resolve. É o atrito real, e é pequeno.
- **Certificado público é impossível** — mas isso vale para qualquer TLD local. Se um dia
  quiser HTTPS em dev, é CA local (`mkcert`), tanto no `.test` quanto no `.io`.

> **Decisão (2026-09-09): o kit usa `.test`; os 15 projetos existentes seguem em `.io`.**
>
> O argumento de consistência não se aplica ao kit: o público dele — devs externos — nunca vê
> os projetos internos de quem mantém, e para eles a falha limpa vale mais. Nada do que
> já existe muda.
> **`.local` descartado** pelos dados acima; **`.dev` e `.app` descartados** pelo HSTS.

### 4.6 O caminho completo — os dois momentos

**Momento 1 — subir.** Termina numa tela funcionando, sem conta no Spelt.

```bash
git clone https://github.com/iporto/deploy.git ~/.deploy-scripts     # a biblioteca
export PATH="$HOME/.deploy-scripts:$PATH"

deploy-infra up                                    # base compartilhada, 1x por máquina
deploy-infra createdb acme --print-env > /tmp/acme-db.env

git clone <url-do-kit> ~/starter-kit
deploy-scaffold-project acme.com --from-kit ~/starter-kit --db-env /tmp/acme-db.env --apply
cd deploy.acme.com

# o comando imprime as linhas do hosts a acrescentar
sudo sh -c 'cat hosts >> /etc/hosts'

./deploy-run dev                                   # 1º up: composer + npm, leva minutos
docker compose exec php-api php artisan migrate
docker compose exec php-api php artisan <token>    # gera o token de dev
# abrir http://platform.acme.test/auth/dev-login?token=…
```

> ✅ **Sem Spelt.** O kit já traz o caminho: `TokenCommand` na API, rota `/auth/dev-login` no
> platform, e a landing mostra a instrução dentro de `@if (app()->isLocal())`. O primeiro
> contato termina no dashboard, não numa parede de login.

**Momento 2 — construir o produto.** O dev duplica o `docs/starter-kit-ideas/TEMPLATE.md`
para o `docs/` do próprio projeto, desenha o produto — e é **aí** que surge a necessidade da
conta no Spelt, das chaves e do catálogo.

> 📌 **Requisito para o scaffold:** copiar o `TEMPLATE.md` do kit para
> `deploy.<projeto>/docs/`. É o ponto de partida do momento 2.

> 📌 **Requisito para todos os comandos:** terminar imprimindo o **próximo passo**. É o que
> substitui documentação que ninguém lê — e cobre o `/etc/hosts`, que nenhum `deploy-doctor`
> consegue verificar quando o navegador está noutra máquina.

### 4.7 Premissas que o kit precisa declarar

- O produto usa o **Spelt como base administrativa** — o adotante precisa de uma conta e das
  chaves (`SPELT_API_KEY`, `SPELT_WEBHOOK_SECRET`). Isso não é opcional: é o que o kit é.
- Produção assume **Coolify**. Outra plataforma exige adaptar o a spec do produto.

---

### 4.8 `deploy-doctor` — diagnosticar o ambiente

Se o alvo são 72 devs em 72 máquinas, cada um que travar vira uma conversa. O `deploy-doctor`
verifica o ambiente e diz o que falta, em vez de deixar o dev adivinhar:

| Verifica | Sintoma que evita |
|---|---|
| Docker acessível e qual o contexto (local/remoto) | subir na máquina errada |
| Rede `shared` existe | containers sobem e nada roteia |
| `infra-traefik`, `infra-mysql`, `infra-redis`, `infra-mail` no ar | erro de conexão sem causa aparente |
| Portas livres (80, 3306, 6379, 1025, 8025) | `up` falha com "port already allocated" |
| `.env.dev` presente e sem chave sensível vazia | container sobe e morre no boot |
| Linhas do `./hosts` no `/etc/hosts` | **cai numa página aleatória da internet** (§4.5) |
| Database do projeto existe no MySQL | `migrate` falha |
| Apps em `code/` com `.env` apontando para `infra-*` | app sobe apontando para si mesmo |
| Imagens `iporto99/*` disponíveis para a arquitetura da máquina | emulação silenciosa ou pull falhando |

Só lê e reporta — nunca conserta sozinho. Cada item aponta o comando que resolve.

---

### 4.9 Revisão antes de publicar o kit

O kit vira público. Antes disso, uma varredura como a que foi feita na biblioteca:

| Verificar | Por quê |
|---|---|
| Segredos no working tree e **no histórico** | `.env` dos apps estão gitignored e nunca entraram — confirmado. Reconferir o resto |
| Chaves, tokens, `.pem`, `.key` | mesma varredura da biblioteca |
| Dados de cliente nos `docs/starter-kit-ideas/` | há arquivos de produtos reais (Fábrica de Lead, Try Psst) — decidir o que fica |
| Caminhos e e-mails pessoais | caminho de home, endereço de e-mail |
| O que a arquitetura do Spelt expõe | fluxo de SSO, validação de webhook, modelo de entitlement — risco aceito, mas consciente |
| E-mail nos commits | o histórico do kit fica público |

---

## 5. O que NÃO será feito

| Item | Por quê |
|---|---|
| Mover o dev para caminhos locais (`./code`) no compose | Desnecessário: o `REMOTE_BASE_PATH` já resolve os dois mundos via contexto |
| Publicar a topologia interna como está | Ela tem 8 serviços e premissas próprias; o `infra/` é o subconjunto portátil |
| Gerar `docker-compose.prd.yml`, `servers.yml`, Watchtower | Produção é Coolify |
| Tornar o runbook completo do Coolify público | É específico da integração com o Spelt e pertence à doc do produto |

---

## 6. Multi-computador, multi-dev

Com o mecanismo da §4.4, quase tudo se resolve sozinho:

| # | Cenário | Estado |
|---|---|---|
| A | 1 dev, Docker local, 1 produto | ✅ `infra-dev up` + `./deploy-run dev` |
| B | 1 dev, Docker local, N produtos | ✅ containers isolados por `${APP_PROJECT_NAME}`; infra sobe **uma vez** |
| C | 1 dev, Docker remoto por contexto | ✅ o `deploy-run` detecta e usa o caminho da VM |
| D | **N devs, cada um na sua máquina** | ✅ **o alvo real** — 72 devs, 72 máquinas, 72 infras |
| E | N devs, **mesmo Docker remoto** | 🚫 fora do escopo — ninguém compartilha daemon |

O prefixo `${APP_PROJECT_NAME}` já isola os containers do produto. A camada de infra é única
por máquina de propósito — porta 80, `infra-mysql`, `infra-redis` são nomes globais.

### Questões fechadas (2026-09-09)

**Dados para o dev novo.** Não há seed nem dump para distribuir: **o produto do kit tem os
próprios migrations**, e o dev **cria as próprias credenciais**. `migrate` monta o schema; o
`.env.dev.example` já nasce com os valores sensíveis vazios, para o dev preencher com senhas
locais dele. Isso encaixa no modelo de env que já foi adotado — nada novo a construir.

**Chaves do Spelt.** São **do dev, não do kit**. Quem adota configura as próprias
`SPELT_API_KEY` e `SPELT_WEBHOOK_SECRET`. O kit não distribui credencial nem mantém sandbox
compartilhado; documenta quais chaves são necessárias e onde obtê-las.

**"Multi-dev" significa 72 máquinas, não um Docker compartilhado.** O cenário E está
**fora do escopo** — ninguém compartilha daemon. Cada dev roda a própria infra na própria
máquina, e é por isso que os nomes fixos (`infra-mysql`, `infra-redis`) e a rede `shared`
não colidem: são únicos **por máquina**, e cada máquina tem um dono só.

> ✅ **Consequência de desenho:** o caminho **local é o principal**, e o contexto remoto é a
> variação. O quickstart, os defaults e a documentação devem assumir local; o remoto entra
> como "se você usar Docker remoto, o `deploy-run` detecta sozinho".

### Riscos

| Risco | Mitigação |
|---|---|
| Porta 80 ocupada na máquina do dev | Porta do Traefik configurável por env |
| Nome fixo (`infra-mysql`) colide com algo que o dev já tem | Documentar; os nomes são previsíveis para os `.env` dos apps não mudarem |
| `.localhost` não resolver em Linux/WSL | Verificar; manter o `hosts` como alternativa documentada |
| Infra do kit divergir da topologia interna | Independentes por decisão; anotar a relação nos dois lados |
| Kit público expõe a arquitetura do Spelt | Premissa aceita ao publicar; nenhuma credencial viaja |

## 7. O que o teste real encontrou

**Doze defeitos, nenhum deles visível em teste de mesa.** Estão aqui porque o
padrão importa mais que a lista: quase todos vinham de uma diferença entre a
máquina de quem escreve e a de quem usa.

### Ambiente diferente do de origem

| # | Defeito | Por que escapou |
|---|---|---|
| 1 | `sed -i ''` é sintaxe BSD; o GNU trata o `''` como nome de arquivo | a biblioteca era testada só no macOS |
| 2 | Traefik fala a API Docker v1.24; o Docker 29 exige 1.44+ | a VM de origem tinha Docker mais antigo. **Nenhuma rota era descoberta e tudo dava 404**, sem erro fora do log |
| 3 | Compose não lia o `.env.dev` (faltava `--env-file`) | na máquina de origem o `.env` antigo ainda existia |
| 4 | Disco de 11 GB não comporta o stack | o instalador do Ubuntu aloca metade do grupo de volumes |

### Suposições sobre o próprio produto

| # | Defeito | Por que escapou |
|---|---|---|
| 5 | Config do Watchtower gerada incondicionalmente | a trilha Coolify não tem Watchtower |
| 6 | 4 arquivos do `php-console` faltando no template | o Docker **cria diretório vazio** no lugar do bind mount ausente, e o erro fala de "tipo de arquivo", não de arquivo faltando |
| 7 | `dev:token` imprimia um domínio fixo do kit | funcionava no ambiente de origem |

### Introduzidos por mudanças nossas

| # | Defeito | Por que escapou |
|---|---|---|
| 8 | Senha do root lida **com as aspas** | a padronização `KEY="valor"` corrigiu o guard e esqueceu a leitura |
| 9 | `--print-env` imprimia o cabeçalho de contexto | só aparece ao redirecionar de verdade |
| 10 | Ordem das regras do rsync engolia o `.env.example` | o rsync aplica a **primeira** regra que casa |

### Só o passo a passo literal encontraria

| # | Defeito | Por que escapou |
|---|---|---|
| 11 | `createdb` rodava antes do MySQL aceitar conexão | eu sempre esperava antes de rodar |
| 12 | `docker compose exec …` do README não funciona | o compose chama-se `docker-compose.dev.yml` e o `working_dir` não é o do app. **Era o último passo do quickstart** |

> 📌 **A lição operacional.** Os defeitos 1 a 4 só apareceram porque o teste rodou
> numa máquina que **não era a de quem escreveu o código**. Os 11 e 12, porque o
> README foi executado **literalmente**, sem improviso. Nenhuma revisão de código
> teria encontrado qualquer um dos doze.

Corrigido de passagem um defeito latente e anterior: o `_read` do `deploy-run`
fazia `grep` sem tolerar ausência, e o `set -e` matava o script dentro da
substituição de comando — `deploy-run prd` com `.env.prd` malformado saía em
**silêncio, com exit 0**.

---

## 8. Checklist — verificado

- [x] `git clone` numa máquina limpa traz tudo (ambos os repositórios públicos)
- [x] `deploy-doctor` roda antes de qualquer instalação e reporta o que falta
- [x] `deploy-infra up` cria a rede `shared` e sobe os 6 serviços
- [x] `deploy-infra createdb` cria database, usuário e senha — e espera o MySQL
- [x] `--from-kit` cria os apps renomeados, sem `.env` vazado do kit
- [x] Nenhum `.env.example` de app aponta para `127.0.0.1`
- [x] Projeto gerado tem exatamente 2 verbos
- [x] `./deploy-run dev` sobe e `migrate` conclui
- [x] `platform.acme.test` responde e o `dev-login` chega ao painel **sem Spelt**
- [x] `docs/TEMPLATE.md` presente no projeto gerado
- [x] Cada comando termina dizendo o próximo passo
- [x] Nenhum identificador pessoal ou de cliente no que é público

---

## 9. Auditoria da biblioteca (2026-09-09)

3.268 linhas úteis em 14 scripts, revisadas antes de executar o plano.

### Removido

**`init-mutagen` (459 linhas)** — o segundo maior script da biblioteca. Ele lê um
`mutagen.yml` da raiz do projeto, e **nenhum dos 15 projetos tem esse arquivo**: ele não
rodava em lugar nenhum. As 19 sessões de Mutagen ativas foram criadas por fora e não dependem
dele. Nenhum projeto o tinha como verbo. ✅ **Removido.**

### Restrição documentada no `deploy-run`

O `deploy-run` é o único script que roda **dentro da VM**, e chega lá sozinho: o
`push_deploy_run()` copia aquele arquivo, e só ele, pela conexão SSH.

> ❌ **Não extrair `lib.sh` do `deploy-run`.** A duplicação de `print_*`, cores e
> `_scripts_dir()` é real — 9 scripts repetem — e a tentação de centralizar é legítima. Mas
> o `deploy-run` não teria a lib na VM, e **o erro só apareceria no primeiro deploy** depois
> da mudança. O aviso está agora no cabeçalho do próprio script, onde quem for "limpar" vai
> tropeçar nele. Se a lib for extraída um dia, o `push_deploy_run()` tem de entregá-la junto.

### Duplicação — real, mas segura de mexer só fora do `deploy-run`

| Repetido em | O quê |
|---|---|
| 13 scripts | definições de cor |
| 9 scripts | `print_error`, `print_info` |
| 8 scripts | `print_success`, `print_warning` |
| 6 scripts | `_scripts_dir()` |

### Presos à trilha antiga — não saem, mas não entram em projeto novo

`deploy-promote` (198) e `deploy-token-check` (92) servem ao ciclo `:prd` + Watchtower. Na
trilha Coolify não têm função. Os 15 projetos atuais dependem deles; projetos novos não
devem recebê-los — é o que a decisão dos 2 verbos (§4.3, passo 4) já garante.

### `deploy` — usado por 3 de 15

O wrapper existe para ler `servers.yml` e chamar o `deploy-sync` por VM. Só 3 projetos têm
`servers.yml`; nos outros 12 ele avisa e repassa a chamada. Fica — o multi-servidor é real
onde existe — mas convém saber que 80% das invocações são um passe adiante.

---
