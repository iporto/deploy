# A esteira de produção

> Como o código de um app vira imagem e chega ao ar. Cobre a **trilha Coolify**,
> que é a dos projetos gerados pelo `deploy-scaffold-project`.
>
> A trilha antiga — Traefik + Watchtower + `./deploy prd` — é outra, e está no
> [`DEPLOY-README.md`](../DEPLOY-README.md).

---

## O modelo em uma tela

```
push na main do repo do APP
  └─ versiona (tag + Release) e avisa o repo de DEPLOY
       │  repository_dispatch, com o SHA EXATO deste commit
       ↓
repo de DEPLOY constrói
  ├─ checkout do código do app        (token do GitHub App)
  ├─ checkout de si mesmo             (Dockerfile e confs)
  ├─ varre o CONTEXTO atrás de env em texto puro
  ├─ build + push no GHCR
  ├─ varre a IMAGEM PRONTA atrás de env e chave privada
  └─ POST /api/v1/deploy no Coolify
       ↓
Coolify puxa a tag :prd e recria o container
```

**O repositório do app não constrói nada.** Ele tem um arquivo de CI —
`notify-deploy.yml` — que versiona e avisa. Os Dockerfiles vivem no repositório
de deploy, em `.docker/Code/<app>/`.

### Por que centralizado

Um Dockerfile por app, num lugar só: mudar a base do PHP em cinco apps é um
commit, não cinco. E o contexto de build pode ser inspecionado antes do push —
é o que torna possível a varredura de segredo, que numa esteira distribuída não
teria onde acontecer.

O custo é precisar de uma credencial que cruze repositórios. É o assunto do
GitHub App, abaixo.

---

## As três tags

Cada build publica três, com papéis diferentes:

| Tag | Muda? | Para quê |
|---|---|---|
| `sha-a1b2c3d` | nunca | responde *"que código exatamente é este?"* |
| `v1.4.2` | nunca | a mesma coisa, em linguagem de gente |
| `:prd` | **sim** | o ponteiro que o Coolify observa |

> [!IMPORTANT]
> O Coolify guarda **uma** `imagem:tag` na configuração e re-puxa quando recebe
> o webhook — ele não muda a tag sozinho. Sem um ponteiro móvel, você teria que
> reconfigurar o app a cada release.
>
> A tag móvel só é aceitável porque as imutáveis existem ao lado: o digest de
> `:prd` sempre bate com alguma `sha-` publicada. Sozinha, ela impediria saber o
> que está em produção.

**Não é `:latest` de propósito.** `:latest` é o que o Docker puxa quando você não
pede tag nenhuma — um `docker pull <imagem>` na máquina de alguém traria
produção sem ninguém ter pedido.

---

## O GitHub App

O build centralizado precisa cruzar repositórios em **dois sentidos**:

| Sentido | Para quê | Permissão |
|---|---|---|
| app → deploy | disparar o `repository_dispatch` | Contents: write |
| deploy → app | `checkout` do código | Contents: read |

> [!NOTE]
> **O `GITHUB_TOKEN` não serve.** Ele é escopado ao próprio repositório, por
> construção. A escolha real é entre um PAT pessoal e um GitHub App.

Um App emite token que **vive 1 hora**, é escopado aos repositórios onde foi
instalado e **não morre junto com uma pessoa**. Um PAT é pessoal: expira, precisa
de rotação e quebra se quem o criou sair da organização.

### Criar — uma vez por organização

1. **Settings da org → Developer settings → GitHub Apps → New GitHub App**
   *(na conta pessoal também funciona; veja a ressalva no fim)*
2. **Nome:** qualquer um — ele é global no GitHub, então pode acusar duplicado
3. **Homepage URL:** obrigatório e não usado. A URL da org serve
4. **Webhook → desmarque "Active"**
5. **Permissions → Repository → Contents: Read and write** — só essa; `Metadata`
   entra sozinha
6. **Where can this GitHub App be installed:** *Only on this account*
7. Criar → **Generate a private key** (baixa um `.pem`) → anote o **App ID**
8. **Install App** → *Only select repositories* → o repo de **deploy** e os
   repos de **cada app**

> [!WARNING]
> **Desmarcar o Webhook é o passo que mais escapa.** Se ficar marcado, o GitHub
> exige uma URL e não deixa salvar. Nós não usamos webhook do App — o token é
> emitido pelo próprio workflow.

> [!CAUTION]
> O `.pem` só pode ser baixado **uma vez**. Perdeu, gere outra chave e troque o
> segredo; a antiga se revoga na mesma tela.

### Os segredos, por repositório

**No repositório de DEPLOY:**

| Segredo | O que é |
|---|---|
| `DEPLOY_APP_ID` | o número do App |
| `DEPLOY_APP_PRIVATE_KEY` | o `.pem` **inteiro**, com as linhas `-----BEGIN` e `-----END` |
| `COOLIFY_URL` | a URL do painel, sem barra no fim |
| `COOLIFY_TOKEN` | *Keys & Tokens → API tokens* no Coolify |
| `COOLIFY_UUID_<APP>` | um por app: `COOLIFY_UUID_API`, `COOLIFY_UUID_WWW`. Aceita vários uuid separados por vírgula, para papéis que compartilham a imagem |
| `DOCKERHUB_USERNAME` · `DOCKERHUB_TOKEN` | só se a imagem base for privada |

**No repositório de CADA APP:**

| Segredo | O que é |
|---|---|
| `DEPLOY_APP_ID` | o mesmo |
| `DEPLOY_APP_PRIVATE_KEY` | o mesmo |
| `DEPLOY_REPO` | `org/deploy.meuprojeto.com` |

> [!TIP]
> Os dois primeiros ficam duplicados em cada repositório. Segredo de
> **organização** evitaria isso, mas no plano Free ele não alcança repositório
> privado — é a única coisa que o plano pago economizaria aqui.

---

## Voltar atrás

Dispare o build com o ref antigo:

```bash
gh workflow run build.<app>.yml -R org/deploy.meuprojeto.com -f code_ref=<sha-antiga>
```

Ele reconstrói daquele commit, **move o `:prd` de volta** e avisa o Coolify.

> [!WARNING]
> **Não fixe uma `sha-` na configuração do Coolify** para voltar atrás. A partir
> dali o app ignora o `:prd` para sempre: os builds seguintes rodam, publicam e
> disparam o webhook, e **nada muda** — porque a configuração pede uma tag que
> não se move. Parece esteira quebrada, e o sintoma não aponta para a causa.

---

## Quando falha

Sintomas reais, com a causa que estava por trás:

| Sintoma | Causa |
|---|---|
| Run **falha em 0s**, sem log, "workflow file issue" | O arquivo foi recusado na inicialização. Quase sempre o contexto `secrets` usado num `if:` — **não é permitido**; condicione por `env` do job |
| `Segredo em texto puro no contexto de build` | Há `.env` versionado no repo do app. Confira se o `.gitignore` não tem só `.env` — esse padrão **não pega** `.env.default.prd` |
| `A imagem contém .../oauth-private.key` | Chave do Passport versionada. O padrão do Laravel cobre `storage/oauth-*.key`; se ela nasce na raiz, fica de fora |
| Coolify: `image ... not found` | O app está apontado para uma tag que não publicamos, normalmente `:latest`. Aponte para `:prd` |
| Navegador: `ERR_CERT_AUTHORITY_INVALID` | O Let's Encrypt nunca emitiu. Teste `curl -I http://seu.dominio/` — **404 na porta 80** significa que o Traefik não conhece o domínio: falta preencher *Domains* no app, ou o container não está no ar |
| `403` no checkout cruzado | O App não foi instalado **no repositório do código** — só no de deploy |
| `404` no dispatch | `DEPLOY_REPO` errado, ou o App sem `Contents: write` no repo de deploy |

---

## Ressalva sobre a propriedade do App

Criado na **conta pessoal**, ele funciona igual — desde que *"Where can this
GitHub App be installed"* permita instalar na organização. O que se perde é a
propriedade: ele fica atrelado a uma pessoa, que era metade do motivo de trocar
o PAT. Dá para migrar para a organização depois.
