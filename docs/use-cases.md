# Casos de uso

> Cada cenário abaixo é uma situação real, com os comandos na ordem em que
> resolvem. Se o seu caso não estiver aqui, o [README](../README.md) tem a
> referência de cada comando.
>
> **Convenção:** `acme.com` é o domínio do seu produto. Troque em todos os
> comandos — o domínio determina o nome dos containers, o diretório dos apps e
> as linhas do `/etc/hosts`. Trocar pela metade gera erro que não aponta para a
> causa.

---

## Índice

| | Situação |
|---|---|
| [1](#1-um-projeto-meu-sem-o-kit) | Tenho um projeto Laravel meu e quero só a base de Docker |
| [2](#2-um-saas-novo-a-partir-do-kit) | Quero um SaaS novo, com API e painel já prontos |
| [3](#3-um-segundo-produto-na-mesma-máquina) | Já tenho um produto rodando e quero um segundo |
| [4](#4-já-tenho-o-código-falta-a-base) | Já tenho o `code/` com meus apps e falta o Docker em volta |
| [5](#5-entrei-num-projeto-que-já-existe) | Alguém me passou um projeto e preciso subir |
| [6](#6-desenvolvo-contra-uma-vm) | Meu Docker roda numa VM, não na minha máquina |
| [7](#7-projeto-da-trilha-antiga) | Projeto com Traefik + Watchtower, deploy por `./deploy prd` |

---

## Antes de tudo: a biblioteca

Todos os cenários assumem a biblioteca instalada e no `PATH`:

```bash
git clone https://github.com/iporto/deploy.git ~/.deploy-scripts
export PATH="$HOME/.deploy-scripts:$PATH"     # ponha no seu .bashrc/.zshrc
```

> [!TIP]
> Em equipe, fixe a versão: `git clone --branch v2.2.0 --depth 1 …`. Sem isso,
> duas pessoas que clonam com uma semana de diferença rodam código diferente.

---

## 1. Um projeto meu, sem o kit

**Você tem:** um produto Laravel seu, ou a intenção de começar um.
**Você quer:** a base de Docker do ambiente de desenvolvimento — compose, nginx,
php-fpm, supervisord, cron, envs, hosts — sem herdar código de ninguém.

```bash
mkdir -p ~/Projects/deploy.acme.com && cd $_

deploy-doctor                                   # a máquina dá conta?
deploy-infra up                                 # base compartilhada, 1x por máquina
deploy-scaffold-project acme.com --dir . --apply
```

`code/` nasce **vazio**. Clone ali os seus apps, com o nome que o compose espera
(`code/api.acme.com`, `code/platform.acme.com`), e equipe-os com os artefatos de
build:

```bash
deploy-scaffold-app ./code --apply              # Dockerfile, .deploy/, workflow
deploy-infra createdb acme                      # banco + usuário + senha
sudo sh -c 'cat hosts >> /etc/hosts'            # na máquina do NAVEGADOR
./deploy-run dev
```

> [!NOTE]
> O `deploy-scaffold-app` reconhece um app por `composer.json` **e** `artisan`.
> Um diretório sem os dois é ignorado — rode-o depois de clonar os apps de
> verdade, não sobre diretórios vazios.

> [!NOTE]
> O template é **PHP/Laravel**: nginx + php-fpm + supervisord. Se o seu produto
> for Node, Go ou Python, o compose gerado não serve — nesse caso escreva o seu
> `docker-compose.dev.yml` e veja o [cenário 4](#4-já-tenho-o-código-falta-a-base).

---

## 2. Um SaaS novo, a partir do kit

**Você tem:** uma máquina limpa.
**Você quer:** um SaaS rodando — API, painel, login, assinatura, créditos e
webhooks já resolvidos.

O caminho curto é o assistente. Ele faz os passos do cenário 1 e mais a
instanciação do kit, mostrando cada comando antes de executar:

```bash
deploy-wizard
```

Ele pergunta o domínio, detecta o que já existe, sobe a infra, cria o banco,
gera o projeto e oferece gravar a biblioteca no `PATH` do seu shell.

Ao terminar, faltam três passos que ele imprime — as dependências ainda estão
instalando quando ele devolve o prompt:

```bash
deploy-doctor ~/deploy.acme.com                 # já terminou o composer?
docker exec acme-php-api sh -c 'cd api.acme.com && php artisan migrate --force'
docker exec acme-php-api sh -c 'cd api.acme.com && php artisan dev:token'
```

O último imprime um link que abre o painel **sem conta no Spelt**.

---

## 3. Um segundo produto na mesma máquina

**Você tem:** um produto rodando, a infra compartilhada no ar.
**Você quer:** um segundo produto ao lado, reusando a mesma base.

A infra é compartilhada — **não suba outra**. Só o banco novo e o projeto novo:

```bash
deploy-infra status                             # confirme que está no ar
deploy-infra createdb outro --print-env > /tmp/outro-db.env

deploy-scaffold-project outro.com \
  --from-kit ~/starter-kit \
  --dir ~/deploy.outro.com \
  --db-env /tmp/outro-db.env \
  --apply
```

> [!WARNING]
> **Se você reclonou `~/.deploy-scripts`, pare aqui.** O `infra/.env.dev` não é
> versionado: reclonar apaga as senhas, e o MySQL guarda a do **primeiro boot**
> dentro do volume. As duas divergem e todo `createdb` passa a responder
> *Access denied* — culpando uma credencial que parece certa no arquivo.
>
> `deploy-doctor` detecta isso antes: procure a linha
> *"a senha do root NÃO abre o MySQL"*.

---

## 4. Já tenho o código, falta a base

**Você tem:** um diretório com `code/` cheio dos seus apps.
**Você quer:** o Docker montado em volta, sem tocar em nada do que já existe.

```bash
cd ~/Projects/deploy.acme.com
deploy-scaffold-project acme.com --dir . --adopt --apply
```

`--adopt` **não sobrescreve nada**. Arquivo que já existe é preservado e
reportado com `=`; só o que falta é criado. `code/` não é tocado em nenhuma
hipótese, e rodar duas vezes não muda nada.

Para puxar **um** arquivo atualizado do template por cima do seu, apague o local
primeiro — veja antes o que perderia:

```bash
git diff .docker/Php/conf/php-ini/php.ini
rm .docker/Php/conf/php-ini/php.ini
deploy-scaffold-project acme.com --dir . --adopt --apply
```

---

## 5. Entrei num projeto que já existe

**Você tem:** a URL do repositório de deploy que um colega criou.
**Você quer:** o ambiente dele rodando na sua máquina.

Um produto são **vários repositórios**: o de deploy, com a infraestrutura, e um
por app. O `.gitignore` do projeto ignora `/code/*` de propósito.

```bash
git clone <url-do-deploy> deploy.acme.com && cd deploy.acme.com

mkdir -p code
git clone <url> code/api.acme.com               # só os que você tem acesso
git clone <url> code/platform.acme.com

cp .env.dev.example .env.dev                    # e preencha o banco
deploy-infra up                                 # a sua infra local
deploy-infra createdb acme                      # o seu banco local

deploy-doctor .
./deploy-run dev
```

> [!TIP]
> O projeto traz `docs/onboarding.md` com esses passos **já preenchidos** com os
> nomes reais dos apps. Prefira ele a este bloco genérico.

O nome do diretório importa: o compose monta `./code/<nome>` por caminho. Clonar
com outro nome sobe o container com um diretório vazio dentro.

---

## 6. Desenvolvo contra uma VM

**Você tem:** o contexto Docker apontando para uma VM (`ssh://…`), não para a
sua máquina.
**Você quer:** editar local e ver rodando lá.

O trabalho se divide em dois canais:

| O que muda | Como chega na VM | Quando |
|---|---|---|
| Código dos apps | **Mutagen**, contínuo | a cada save |
| Compose, nginx, php.ini, envs | **`deploy-sync`** | quando são editados |

```bash
./deploy-mutagen status                         # o que está sincronizando
./deploy-mutagen start                          # inicia as sessões paradas
./deploy-run dev                                # sincroniza a config e sobe
```

O `./deploy-run dev` chama o `deploy-sync` sozinho quando o daemon é remoto —
`--no-sync` pula. E antes de subir ele confere, **na VM**, se as origens dos bind
mounts existem: sem o Mutagen rodando, `code/<app>` não existe lá, o Docker cria
um diretório vazio no lugar e o container quebra depois, longe da causa.

> [!WARNING]
> **O namespace de sessão do Mutagen é global.** Dois projetos que declarem o
> mesmo nome no `mutagen.yml` disputam a mesma sessão, e quem perde sincroniza
> o diretório do outro — calado, porque a sessão existe e está `Watching`.
> O `./deploy-mutagen status` compara e denuncia.

---

## 7. Projeto da trilha antiga

**Você tem:** um projeto com `docker-compose.prd.yml`, Traefik e Watchtower.
**Você quer:** operar produção.

Esta trilha é diferente da do kit: aqui a configuração viaja pelo `./deploy` e a
imagem é liberada por promoção de tag.

```bash
./deploy prd -n                                 # dry-run: o que iria
./deploy prd                                    # configs e envs para a VM
./deploy prd --only "php supervisor"            # só reiniciar serviços

./envedit prd                                   # editar env criptografado
./envedit --show                                # ver decriptado

./deploy-promote prd api --check                # o que está no ar
./deploy-promote prd api                        # liberar a imagem
./deploy-promote prd api sha-a1b2c3d            # rollback

./deploy-backup prd                             # dump dos bancos
```

> [!CAUTION]
> `./deploy-run prd` **não** sincroniza, de propósito: ele significa "reinicie
> este serviço". Se sincronizasse, um comando de reinício publicaria arquivos em
> produção, inclusive alterações em andamento. Quem quer os dois é `./deploy prd`.

---

## Quando algo não sobe

```bash
deploy-doctor .            # no projeto: hosts, envs, deps, binds
deploy-infra status        # a base compartilhada
./deploy-run dev status    # os containers deste projeto
deploy-infra logs          # o que a base está dizendo
```

O `deploy-doctor` é o primeiro: ele cobre os erros que **não** se anunciam — o
`/etc/hosts` sem entrada (o navegador não erra, vai para a internet), o
`vendor/` ainda instalando, a senha do root que não abre o MySQL.
