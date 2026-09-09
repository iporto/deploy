# deploy

Scripts de shell para publicar projetos **Docker Compose** numa VM por SSH e rsync.
Sem agente no servidor, sem painel, sem plataforma: um punhado de scripts que você
lê em uma tarde e um `.env` por ambiente.

```bash
./deploy prd          # sincroniza o projeto com o servidor e sobe os containers
./deploy-backup prd   # traz um dump dos bancos do servidor
./envedit prd         # edita o .env criptografado em texto puro
```

---

## O problema que ele resolve

Um projeto Docker Compose pequeno demais para Kubernetes, mas grande demais para
`scp` e `docker compose up` na unha. Você precisa de coisas chatas e repetitivas:
mandar os arquivos sem sobrescrever o que vive só no servidor, entregar segredos
sem versioná-los em texto puro, subir os containers na ordem certa, tirar backup
antes de mexer, e não deixar o banco exposto na internet.

Este repositório é esse conjunto de tarefas, cada uma num script com uma
responsabilidade só, compartilhado por vários projetos ao mesmo tempo.

**Duas ideias sustentam o desenho:**

1. **Imagem e configuração viajam por caminhos separados.** O CI constrói e publica
   a imagem; o `deploy` entrega compose, configs e envs. Um nunca depende do outro.
2. **O servidor puxa, ninguém empurra.** A VM não precisa aceitar conexão do CI —
   o Watchtower observa o registry. Menos superfície exposta.

O `DEPLOY-README.md` explica esse modelo em detalhe. Este arquivo é a referência
de comandos e flags.

---

## Isto serve para você?

Ele assume um cenário específico. Se algum item não bate, provavelmente não serve:

| Premissa | |
|---|---|
| Aplicação em **Docker Compose** | não Kubernetes, não Swarm |
| Uma ou mais **VMs Linux** com acesso SSH | não PaaS |
| Estação de trabalho **macOS ou Linux** | os scripts rodam no seu computador |
| Configuração por **arquivo `.env` por ambiente** | `dev`, `stg`, `prd` |

---

## Pré-requisitos

| Ferramenta | Propósito | Instalação |
|------------|-----------|-----------|
| `docker` | Gerenciamento de containers | [docker.com](https://docker.com) |
| `docker compose` v2 **ou** `docker-compose` v1 | Orquestração | Incluso no Docker Desktop |
| `rsync` | Transferência de arquivos | `brew install rsync` |
| `ssh` | Acesso remoto | Incluso no macOS |
| `envsubst` | Substituição de variáveis | `brew install gettext` |

---

## Instalação

```bash
git clone https://github.com/iporto/deploy.git ~/.deploy-scripts
```

É só isso — são scripts de shell, não há build. Para instalar em outro caminho,
aponte a variável:

```bash
export DEPLOY_SCRIPTS_HOME=/onde/você/clonou
```

Depois, dentro do seu projeto:

```bash
~/.deploy-scripts/deploy-shim-install . --apply
```

Isso cria os verbos (`./deploy`, `./deploy-sync`, …) na raiz do projeto como
symlinks relativos para um pequeno despachante versionado junto — assim o
repositório do projeto continua funcionando na máquina de qualquer pessoa da
equipe, sem caminho absoluto gravado.

> ❌ **Não crie symlinks com `ln -s` apontando para esta pasta.** Era o modelo antigo:
> o caminho absoluto da máquina de quem criou o projeto ficava gravado no git, e o
> repositório nascia quebrado em qualquer outro computador. O shim resolve a
> biblioteca em runtime — é ele que torna o projeto clonável.

Depois crie o arquivo de conexão do ambiente:

```bash
cat > .env.prd << EOF
REMOTE_HOST=deploy@ip-do-servidor
REMOTE_BASE_PATH=/home/deploy/meu-projeto
BASTION_HOST=          # opcional
SYNC_POST_RUN=true     # executa ./deploy-run no servidor após sync
EOF
```

---

## Os scripts

| Script | O que faz |
|---|---|
| `deploy` | Orquestra o deploy para todas as VMs do ambiente, lendo `servers.yml` |
| `deploy-sync` | Envia o projeto por rsync, entrega os envs decriptados e dispara o `deploy-run` |
| `deploy-run` | Sobe, para e reconstrói os containers — roda no seu Mac ou na VM |
| `deploy-promote` | Promove uma imagem já construída para produção, com rollback por SHA |
| `deploy-backup` | Baixa backup dos bancos do servidor, com retenção |
| `envedit` | Edita envs criptografados com SOPS + age, encapsulando as flags que o formato exige |
| `harden-vm` | Fecha a superfície de rede da VM: ufw, `DOCKER-USER`, fail2ban, SSH por chave |
| `deploy-audit` | Varre vários projetos procurando env em texto puro, porta exposta, `chmod 777` |
| `deploy-token-check` | Diagnostica o token de acesso ao registry |
| `deploy-shim-install` | Instala os verbos num projeto (acima) |
| `deploy-app-scaffold` | Instala os artefatos de build (Dockerfile, `.deploy/`, workflow) num repo de app |
| `deploy-project-scaffold` | Cria o repo `deploy.<projeto>` de um SaaS novo: ambiente de dev + runbook |
| `init-mutagen` | Sobe e diagnostica a sessão do Mutagen, para desenvolvimento com VM remota |

Todo script tem `--help`. `deploy`, `deploy-sync` e `deploy-backup` aceitam `-n`
para simular; `harden-vm` e `deploy-shim-install` **só simulam** até receberem
`--apply`.

---

## Aviso

Estes scripts foram escritos para um conjunto real de projetos e carregam as
opiniões desse contexto. Estão publicados porque podem ser úteis a quem tem um
problema parecido — não como produto. Leia antes de rodar em algo que te importa,
especialmente o `harden-vm`, que mexe em firewall e SSH.

---

## `deploy-run` — Gerenciador de Containers

> 🖥️ **Modo remoto.** Com um ambiente como primeiro argumento, o script conecta
> no servidor por SSH e executa o `deploy-run` de lá — você não precisa entrar
> na máquina:
>
> ```bash
> ./deploy-run prd env-app     # recria só o env-app no servidor de produção
> ./deploy-run prd             # sobe/atualiza tudo no servidor
> ./deploy-run env-app         # na VM: comportamento original, inalterado
> ```
>
> A distinção é o primeiro argumento ser `dev`, `prd` ou `stg`. `REMOTE_HOST` e
> `REMOTE_BASE_PATH` são lidos do `.env.AMBIENTE` — ficam em texto puro mesmo no
> env cifrado, justamente para isso.

Executado **no servidor remoto** (ou localmente em dev). Lê o `.env` do diretório atual e sobe/gerencia os containers do projeto.

### Uso

```bash
./deploy-run [COMANDO|SERVIÇO] [FLAGS]
```

### Comandos

| Comando | Descrição |
|---------|-----------|
| *(nenhum)* | Sobe ou atualiza todos os serviços (`pull` + `up`) |
| `stop` | Para e remove todos os containers do projeto |
| `--fresh` / `-f` | Destrói volumes e recria tudo do zero *(pede confirmação)* |
| `<nome-do-serviço>` | Rebuilda apenas o serviço especificado |

### Flags

| Flag | Descrição |
|------|-----------|
| `--no-pull`, `-P` | Não executa pull de imagens (usa cache local) |
| `--help`, `-h` | Exibe a ajuda |

### Exemplos

```bash
# Sobe tudo
./deploy-run

# Para todos os containers
./deploy-run stop

# Destroi volumes e recria do zero
./deploy-run --fresh

# Rebuilda apenas o serviço 'api' (com pull)
./deploy-run api

# Rebuilda 'worker' sem pull (build local)
./deploy-run worker --no-pull
```

### Variáveis obrigatórias no `.env`

| Variável | Descrição | Exemplo |
|----------|-----------|---------|
| `APP_ENV` | Ambiente do projeto | `production` |
| `APP_PROJECT_NAME` | Nome base do projeto | `meu-projeto` |
| `DOCKER_USER` | Usuário Docker Hub | `minha-conta` |
| `DOCKER_TOKEN` | Token de acesso Docker Hub | `dckr_pat_...` |

### Mapeamento de ambientes

| `APP_ENV` | Compose file | Nome do projeto Docker |
|-----------|--------------|----------------------|
| `development` | `docker-compose.dev.yml` | `<name>-dev` |
| `staging` | `docker-compose.stg.yml` | `<name>-stg` |
| `production` | `docker-compose.prd.yml` *(ou `prod.yml`)* | `<name>-prod` |

O script detecta automaticamente se o arquivo de produção usa o sufixo `prd` ou `prod`.

### O que o script faz internamente

1. Detecta `docker compose` v2 (preferido) ou `docker-compose` v1
2. Verifica se o daemon Docker está rodando
3. Carrega o `.env` do diretório atual
4. Autentica no Docker Hub
5. Cria as redes `external` e `shared` se não existirem (idempotente)
6. Regenera o `config.json` do Watchtower via `envsubst`
7. Executa o comando solicitado

---

## `deploy-sync` — Sincronizador com Servidor Remoto

Executado **localmente**. Usa `rsync` sobre SSH para copiar os arquivos do projeto para o servidor, com suporte a bastion host.

### Uso

```bash
./deploy-sync [AMBIENTE] [OPÇÕES]
```

### Ambientes

| Argumento | Arquivo lido |
|-----------|-------------|
| `prd` | `.env.prd` |
| `dev` | `.env.dev` |
| `stg` | `.env.stg` |
| *(omitido)* | `.env` |

### Opções

| Flag | Descrição |
|------|-----------|
| `-n` | Dry-run: simula sem alterar nada |
| `-v` | Verbose: rsync com progresso detalhado |
| `-p` | Pula a aplicação de permissões (`chown`) |
| `-e` | Pula a cópia do `.env` no servidor |
| `-r` | Pula a execução do pós-sync (`deploy-run`) |
| `-l DIR` | Diretório local a sincronizar (padrão: `.`) |
| `-h HOST` | Override do host remoto |
| `-d DIR` | Override do diretório remoto |
| `-E ENV` | Especifica ambiente via flag (alternativa ao argumento posicional) |
| `--only LISTA` | Reinicia só estes serviços em vez de recriar todos. Aceita nomes separados por espaço/vírgula, ou o grupo `app` (todo serviço do compose que monta env de `.envs/`). Para mudança de **configuração** |
| `--sync-only` | Entrega arquivos e envs e para, sem tocar em container |
| `--help` | Exibe a ajuda |

### Exemplos

```bash
# Sincroniza produção
./deploy-sync prd

# Simula sem executar (dry-run)
./deploy-sync prd -n

# Produção com progresso detalhado
./deploy-sync prd -v

# Sync sem executar deploy-run no servidor
./deploy-sync prd -r

# Staging, só sync (pula permissões e pós-sync)
./deploy-sync stg -p -r
```

### Variáveis no `.env.AMBIENTE` (local)

| Variável | Obrigatório | Descrição | Exemplo |
|----------|-------------|-----------|---------|
| `REMOTE_HOST` | ✅ | Destino SSH | `deploy@192.168.1.10` |
| `REMOTE_BASE_PATH` | ✅ | Caminho no servidor | `/home/deploy/meu-projeto` |
| `BASTION_HOST` | ❌ | Jump host SSH | `user@bastion.empresa.com` |
| `SYNC_POST_RUN` | ❌ | Executa `./deploy-run` após sync | `true` |

### O que o script faz internamente

1. Lê o `.env.AMBIENTE` **sem fazer `source`** (seguro: não expõe variáveis ao shell)
2. Abre **uma única conexão SSH multiplexada** (ControlMaster) reutilizada em todas as operações seguintes
3. Verifica/cria o diretório remoto
4. Executa `rsync` com exclusões padrão e `--delete`
5. Aplica `chown` no diretório remoto
6. Copia `.env.AMBIENTE` → `.env` no servidor
7. Executa `./deploy-run` no servidor (se `SYNC_POST_RUN=true`)
8. Encerra o socket SSH ao sair (trap em `EXIT`/`INT`/`TERM`)

### Arquivos excluídos do rsync

```
code/  Www/  .git/  .vscode/  .idea/  .DS_Store
*.swp  *.swo  *.log  storage/  node_modules/  .cache/
infrastructure/traefik/acme.json
```

---

## `deploy` — Deploy Multi-Servidor

Executado **localmente**. Lê o `servers.yml` do projeto e chama `deploy-sync` para cada servidor definido em ordem. Sem `servers.yml`, equivale a chamar `deploy-sync` diretamente (retrocompatível).

### Uso

```bash
./deploy [AMBIENTE] [SERVIDOR] [OPÇÕES]
```

### Argumentos

| Argumento | Descrição |
|-----------|-----------|
| `AMBIENTE` | `dev`, `prd` ou `stg` |
| `SERVIDOR` | (opcional) Nome do servidor em `servers.yml`. Omitir = todos |

### Opções

| Flag | Descrição |
|------|-----------|
| `-n` | Dry-run (simula sem executar) |
| `-v` | Verbose (rsync com progresso detalhado) |
| `-r` | Pula execução de pós-sync (`deploy-run`) |
| `-p` | Pula aplicação de permissões |
| `-e` | Pula cópia do `.env` remoto |
| `--help` | Exibe a ajuda |

### Exemplos

```bash
# Todos os servidores PRD
./deploy prd

# Só o servidor 'redis'
./deploy prd redis

# Dry-run de todos
./deploy prd -n

# Verbose só do main
./deploy prd main -v
```

### Arquivo `servers.yml` (por projeto)

```yaml
servers:
  prd:
    - name: main
      label: VM Principal
      env_file: .env.prd
    - name: redis
      label: VM Redis
      env_file: .docker-stand-alone/Database/Redis/.env.prd
    - name: supervisor
      label: VM Supervisor
      env_file: .docker-stand-alone/PHP-Supervisord/Media/.env.prd
```

O `env_file` define qual `.env` cada servidor usa. O `deploy` faz `cd` para o diretório do `env_file` antes de chamar `deploy-sync`, portanto o caminho é relativo à raiz do projeto.

---

## `deploy-backup` — Backup por Container

Executado **localmente** (na sua máquina). Conecta ao servidor via SSH, detecta os containers do projeto e cria um backup individual por container. Funciona com o mesmo padrão do `deploy-sync`: lê conexão SSH do `.env.AMBIENTE`.

### Uso

```bash
./deploy-backup [AMBIENTE] [OPÇÕES]
```

### Ambientes

| Argumento | Arquivo lido |
|-----------|-------------|
| `prd` | `.env.prd` |
| `dev` | `.env.dev` |
| `stg` | `.env.stg` |

### Destino do backup

| Flag | Descrição |
|------|-----------|
| `--local`, `-L` | Transfere o backup para esta máquina **(padrão)** |
| `--remote`, `-R` | Salva o backup no servidor (`REMOTE_BASE_PATH/backups/`) |

### Tipos de backup (auto-detectados pela imagem do container)

| Imagem detectada | Estratégia | Arquivo gerado |
|-----------------|------------|----------------|
| `mysql`, `mariadb` | `mysqldump --single-transaction --routines` | `dump.sql.gz` |
| `postgres` | `pg_dumpall` | `dump.sql.gz` |
| `redis` | `BGSAVE` + `docker cp dump.rdb` | `dump.rdb` |
| `mongo` | `mongodump` | `mongodump.tar.gz` |
| Qualquer outro | `docker cp` dos volumes nomeados | `volumes/<vol>.tar.gz` |

Para MySQL e PostgreSQL com `--local`, o dump é transmitido diretamente via SSH pipe (sem arquivo temporário no servidor). Para Redis, MongoDB e volumes, um arquivo temporário é criado no servidor e transferido via rsync.

### Flags

| Flag | Descrição |
|------|-----------|
| `--no-compress`, `-C` | Não comprime os arquivos gerados |
| `--no-generic`, `-G` | Pula containers sem banco reconhecido |
| `--dry-run`, `-n` | Simula sem executar nada |
| `--retain N`, `-k N` | Mantém os N backups mais recentes (padrão: 7) |
| `--dir DIR`, `-o DIR` | Diretório local de saída (padrão: `./backups`) |
| `--help`, `-h` | Exibe a ajuda |

### Exemplos

```bash
# Backup de produção → salva localmente
./deploy-backup prd

# Backup de produção → salva no servidor
./deploy-backup prd --remote

# Backup de dev em modo simulação
./deploy-backup dev -n

# Mantém apenas os 5 mais recentes, salva em ~/backups
./deploy-backup prd -k 5 -o ~/backups

# Pula containers sem banco (nginx, app, etc.)
./deploy-backup prd -G
```

### Estrutura de saída (modo --local)

```
./backups/
  prd/
    2025-06-25_10-30-00/
      projeto-prod_mysql_1/
        dump.sql.gz
      projeto-prod_redis_1/
        dump.rdb
      projeto-prod_api_1/
        volumes/
          vol_uploads.tar.gz
```

### Estrutura de saída (modo --remote)

```
REMOTE_BASE_PATH/backups/
  2025-06-25_10-30-00/
    projeto-prod_mysql_1/
      dump.sql.gz
    ...
```

### Variáveis no `.env.AMBIENTE` (local)

| Variável | Obrigatório | Descrição | Exemplo |
|----------|-------------|-----------|---------|
| `REMOTE_HOST` | ✅ | Destino SSH | `deploy@192.168.1.10` |
| `REMOTE_BASE_PATH` | ✅ | Caminho no servidor | `/home/deploy/meu-projeto` |
| `BASTION_HOST` | ❌ | Jump host SSH | `user@bastion.empresa.com` |

### Variáveis opcionais (ambiente ou `.env.AMBIENTE`)

| Variável | Descrição | Padrão |
|----------|-----------|--------|
| `BACKUP_DIR` | Diretório local de saída | `./backups` |
| `BACKUP_RETENTION` | Número de backups a manter | `7` |
| `SSH_KEY` | Chave SSH específica | *(padrão do sistema)* |

### O que o script faz internamente

1. Lê o `.env.AMBIENTE` **sem fazer `source`** (igual ao `deploy-sync`)
2. Abre uma conexão SSH multiplexada (ControlMaster) reutilizada em todas as operações
3. Lê `APP_PROJECT_NAME` do `.env` remoto para descobrir o nome do projeto Docker
4. Lista os containers em execução do projeto no servidor
5. Para cada container: detecta o tipo pela imagem e executa a estratégia adequada
6. Rotaciona backups antigos no destino (local ou remoto)

### Notas

- Credenciais de banco são lidas das variáveis de ambiente do container (`MYSQL_ROOT_PASSWORD`, `POSTGRES_USER`, etc.) — nenhuma configuração extra necessária
- Redis: dispara `BGSAVE` e aguarda até 30s antes de copiar o arquivo
- MySQL: usa `MYSQL_PWD` em vez de `-p` na CLI (evita warning de segurança)
- `deploy-backup` **não precisa estar no servidor** — toda a lógica executa localmente via SSH
- O socket SSH é encerrado automaticamente ao final (trap em `EXIT`/`INT`/`TERM`)

---

## Como atualizar os scripts

Edite apenas os arquivos canônicos — a mudança propaga para todos os projetos automaticamente:

```bash
code "$DEPLOY_SCRIPTS_HOME/deploy"
code "$DEPLOY_SCRIPTS_HOME/deploy-sync"
code "$DEPLOY_SCRIPTS_HOME/deploy-run"
code "$DEPLOY_SCRIPTS_HOME/deploy-backup"
```

Não edite os verbos dentro de um projeto: eles apontam para o shim, não para o
script. Uma alteração ali mudaria o despachante, não o comando.

---

## `envedit` — Envs criptografados (SOPS + age)

Os arquivos de ambiente ficam versionados, porém cifrados. O `envedit` encapsula
o `sops` com as flags corretas.

> ⚠️ **Nunca use `sops` direto nestes arquivos.** Ele identifica o formato pela
> extensão, e `.env.prd` não é uma que ele conheça: sem `--input-type dotenv` o
> arquivo vira um blob binário e o `unencrypted_regex` é ignorado, quebrando a
> leitura que o `deploy-sync` faz de `REMOTE_HOST`.

```bash
./envedit                 # .env.prd — infra
./envedit dev             # .env.dev
./envedit api             # .envs/api.env.prd
./envedit api dev         # .envs/api.env.dev
./envedit --show api      # imprime decriptado no stdout
./envedit --set K V       # grava uma chave sem abrir editor (rotação em lote)
./envedit --check         # procura segredo em TEXTO PURO e valor hostil ao shell
./envedit --updatekeys    # reaplica os destinatários após mexer no .sops.yaml
./envedit --init          # primeira criptografia dos envs em texto puro
```

⚠️ **Valor com crase ou `$` no `.env.prd` chega diferente no container.** O
`deploy-run` faz `set -o allexport; source .env`, e em bash um valor entre aspas
duplas sofre expansão: crase vira **execução de comando**, `$VAR` vira
substituição. O `envedit` avisa ao salvar e no `--check`. Para segredo e salt,
gere sem pontuação:

```bash
openssl rand -base64 48 | tr -d '=+/' | cut -c1-64
```

Isso **não** vale para `.envs/*.env.prd`: esses vão como arquivo para o
container, e quem interpreta é o dotenv do Laravel, onde `${VAR}` é legítimo.

Aceita nome curto (`api`), nome de arquivo (`api.env.prd`) ou caminho
(`.envs/api.env.prd`).

**Editor:** `export EDITOR="code --wait"` abre no VS Code. O `--wait` é
essencial — sem ele o editor retorna na hora e o SOPS acha que você terminou.

**Chave age no macOS:** fica em `~/Library/Application Support/sops/age/keys.txt`,
**não** em `~/.config`. Errar isso dá "identity did not match any of the recipients".

---

## `harden-vm` — Fecha a superfície de rede da VM

Roda **na VM**. Dry-run por padrão; exige `--apply` para valer.

```bash
./harden-vm                    # mostra o que faria
./harden-vm --apply            # aplica
./harden-vm --apply --allow 1.2.3.4
```

Configura ufw com política default-deny, escreve na chain `DOCKER-USER`, instala
fail2ban e restringe o SSH a chave pública.

> ⚠️ **`ufw` sozinho não bloqueia porta publicada pelo Docker** — ele escreve na
> chain `FORWARD` antes do ufw. Por isso o script também mexe em `DOCKER-USER`, e
> por isso o ideal é publicar em `127.0.0.1` no compose.

Tem guarda anti-lockout: não desliga a senha do SSH se não houver chave
autorizada instalada.

---

## `deploy-shim-install` — Instala o shim de bootstrap

Converte projetos `deploy.*` do modelo antigo (symlink com caminho absoluto) para
o shim. Idempotente e dry-run por padrão.

```bash
./deploy-shim-install                    # dry-run em $DEPLOY_PROJECTS_ROOT
./deploy-shim-install ~/Projetos --apply # converte tudo que encontrar
./deploy-shim-install . --apply          # só o projeto atual
```

O que ele faz em cada projeto:

| Ação | Detalhe |
|---|---|
| Instala `.deploy/bin/shim` | Cópia de `template/shim`, versionada no projeto |
| Converte os verbos | Symlink absoluto → symlink **relativo** para o shim |
| `deploy-readme.md` | Vira ponteiro real — não se executa um markdown |
| `.rsyncignore` | Acrescenta `deploy-run` e `.deploy/`, se o arquivo existir |

> ⚠️ O `deploy-run` precisa existir na VM e **não** pode viajar pelo rsync: com o
> shim, o `-L` copiaria o próprio shim. Ele é entregue por `push_deploy_run()` no
> `deploy-sync`. Por isso o instalador mexe no `.rsyncignore`.

---

## `deploy-project-scaffold` — Cria o repo de um projeto novo

Gera o `deploy.<projeto>` de um SaaS: o **ambiente de desenvolvimento** completo
(compose, nginx, php, hosts, envs, verbos) e o esqueleto do runbook de produção.

```bash
./deploy-project-scaffold meuprojeto.com                      # dry-run
./deploy-project-scaffold meuprojeto.com --ip 192.168.66.99 --apply
./deploy-project-scaffold meuprojeto.com --apps api,platform,www --apply
```

| Opção | Padrão |
|---|---|
| `--slug` | primeiro rótulo do domínio (`meuprojeto`) |
| `--dev-domain` | `<slug>.io` |
| `--ip` | `192.168.66.1` — vai para o arquivo `hosts` |
| `--apps` | `api,platform` (o mínimo); aceita `api,platform,www` |
| `--dir` | `./deploy.<dominio>` |

### O que ele deliberadamente NÃO gera

Produção é **Coolify**, então não há `docker-compose.prd.yml`, `servers.yml` nem
Watchtower — a esteira do aparato antigo não participa desta trilha.

E os artefatos de build (`Dockerfile`, `.deploy/`, workflow) **não ficam aqui**:
vivem em cada repo de app, instalados pelo `deploy-app-scaffold`. Os dois scripts
são as duas metades do mesmo desenho — este cuida do **dev**, aquele cuida do
**build para produção**.

> ⚠️ O ambiente gerado espera uma rede Docker externa chamada `shared`, com
> Traefik e os serviços de apoio (banco, cache, mail) já rodando nela. É a
> topologia que estes scripts assumem; sem ela, ajuste o compose.

---

## `deploy-app-scaffold` — Artefatos de build no repo do app

Entrega `Dockerfile`, `.dockerignore`, `.deploy/` e o workflow de build a partir
de **um template canônico** (`template/php-app`), para que a imagem possa ser
buildada pelo próprio repositório do app.

```bash
./deploy-app-scaffold ~/projetos/api.meuapp.com          # dry-run
./deploy-app-scaffold ~/projetos --apply                 # varre e instala
./deploy-app-scaffold . --apply --force                  # atualiza divergentes
```

### O dilema que ele resolve

Dockerfile **centralizado** no repo de deploy dá um lugar só para editar, mas a
imagem deixa de ser buildável pelo repo do app — o que a trilha Coolify exige, e
o que um starter kit precisa para ser distribuível.

Dockerfile **em cada app** resolve isso, mas espalha a manutenção por N repos.

Este script fica no meio: a fonte é única (aqui), o artefato viaja com o app, e
rodar sem `--apply` responde *quem está defasado*.

| Saída | Significa |
|---|---|
| `=` | idêntico ao template |
| `+` | ausente — `--apply` cria |
| `≠` | **divergiu** do template — `--apply` preserva; só `--force` sobrescreve |

### Tipos

Detectado sozinho, ou forçado com `--type`:

| Tipo | Quando | Diferença |
|---|---|---|
| `api` | sem `vite.config.*` | sem build de frontend |
| `web` | `package.json` + `vite.config.*` | + `npm run build` |

> ⚠️ O template assume a base `iporto99/php-8-3` — a mesma do dev, o que garante
> paridade de runtime. É nela que se muda versão de PHP e extensões, não aqui.

---

## `deploy-audit` — Auditoria multi-projeto

Só lê. Não altera nada, não conecta em servidor.

```bash
./deploy-audit                          # varre $DEPLOY_PROJECTS_ROOT (ou o dir atual)
./deploy-audit /outro/caminho
```

Procura: env em texto puro no git, `.env` copiado para dentro da imagem, porta de
banco publicada em `0.0.0.0`, `.dockerignore` sem `**/`, tag `:latest`,
`chmod 777` e chave privada versionada.

---

## `deploy-token-check` — Valida o `PERSONAL_ACCESS_TOKEN`

Testa uma a uma as quatro capacidades que o pipeline precisa e diz qual falta,
em vez de deixar o build falhar com uma mensagem que não aponta para a causa.

```bash
./deploy-token-check      # cola o token no prompt (não fica no histórico do shell)
```

O dono e os repositórios saem dos remotes do próprio projeto — nada hardcoded.
O token nunca é impresso.

| Teste | O que quebra sem ele |
|---|---|
| Escopos | `read:packages` sozinho = token do GHCR colado no lugar errado |
| Organização | Token criado no dono errado (conta pessoal em vez da org) |
| Ler os repos de `code/` | O checkout falha com `403`/`404` |
| Publicar commit status | O build roda, mas não reporta no commit |
| `repository_dispatch` | O build termina e o deploy nunca é acionado |

⚠️ São **dois** tokens do GitHub, com papéis diferentes: o `REGISTRY_TOKEN`
(`read:packages`, vive no `.env.prd` para o Watchtower puxar do GHCR) e o
`PERSONAL_ACCESS_TOKEN` (secret de Actions, precisa enxergar os repositórios).
Trocar um pelo outro autentica com 200 e derruba todos os builds.

---

## `deploy-promote` — Liberar imagem em produção

Resolve o SHA a partir de `origin/main`, espera o build terminar se houver um em
andamento, confere que a imagem existe no registry e só então promove a tag
`:prd`.

```bash
./deploy-promote prd api               # resolve, espera, promove
./deploy-promote prd api sha-a1b2c3d   # SHA específico — é o rollback
./deploy-promote prd api --check       # só informa, não promove
./deploy-promote prd api --now         # promove e aplica na hora
./deploy-promote prd --all             # todos os apps do compose
./deploy-promote prd --status          # quadro geral
```

### Por que existe

O caminho manual (`gh workflow run promote.yml -f app=… -f sha=…`) tem três
chances de errar:

- ler o SHA do `HEAD` local estando numa branch de PR — o build sai de `main`;
- promover antes de o build terminar;
- digitar o SHA errado.

O script resolve os três. Promover cedo nunca promoveu a imagem errada — o
`promote.yml` recusa tag inexistente — mas o script evita o erro em vez de
depender dele.

### `--status`

```
APP          origin/main em :prd    build        situação
──────────── ────────── ────────── ──────────── ────────
api          a1cb96a    560fd1f1   completed    ✅ em dia
www          6d057d1    0e9b1715   completed    🔸 pronto para promover
```

Responde de relance a pergunta recorrente: *o que está no ar e o que está
esperando para subir?*

### Nada hardcoded

A imagem sai do `docker-compose.<ambiente>.yml` e o repo de código de `code/*`.
Não há registry, organização nem nome de projeto escritos no script.
