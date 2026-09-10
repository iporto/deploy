# Deploy em produção — Coolify

> Este projeto **não** sobe por `./deploy`. A esteira do aparato antigo
> (rsync + Watchtower + SOPS) serve outra trilha. Aqui a produção é **Coolify**.

## O modelo

```
push no repo do app
  └─ versiona (tag + Release) e avisa ESTE repositório por repository_dispatch
       └─ ESTE repositório constrói, com o Dockerfile de .docker/Code/<app>/
            └─ ghcr.io/<owner>/<projeto>-<app>:sha-… e :vX.Y.Z
                 └─ POST /api/v1/deploy no Coolify
                      └─ o workload puxa a imagem e recria o container
```

**O build é centralizado aqui.** O repositório do app não tem Dockerfile: ele
versiona o commit e avisa. Um Dockerfile mudado neste repositório vale para
todos os apps no mesmo commit, e o contexto de build pode ser inspecionado antes
do push — é o que permite a varredura de segredo em texto puro que o
`_build-image.yml` faz antes de publicar a camada.

O build sai da máquina que roda os containers, e a imagem versionada no registry
funciona como backup fora da VM. No Coolify, cada app é do tipo **Docker Image**
— não Git+Dockerfile.

Um mesmo image serve três papéis, escolhidos pela variável `CONTAINER_ROLE`:

| Papel | `CONTAINER_ROLE` | Processo |
|---|---|---|
| Web (padrão) | *(vazio)* | supervisord → nginx + php-fpm |
| Worker | `worker` | `php artisan horizon` |
| Scheduler | `scheduler` | `php artisan schedule:work` |

## Pré-requisitos

- Os repos dos apps equipados com os artefatos de build:
  `deploy-scaffold-app ./code --apply`
- Uma instância do Coolify (control plane) e ao menos um servidor de workload.
- Um registry (GHCR) e um token com `read:packages` para o Coolify puxar.

## O passo a passo

> ⚠️ **Este arquivo é um esqueleto.** O runbook completo — setup do Coolify,
> banco e cache, criação dos recursos, blocos de env por app, DNS, secrets do
> auto-deploy e a lista de gotchas — é específico do produto e vive na
> documentação dele, não nesta biblioteca.
>
> Copie aqui o runbook do projeto de referência mais próximo e adapte.

1. Provisionar os servidores (control plane + workload).
2. Firewall no host — o Coolify remove o `ufw`; use o firewall do provedor.
3. Subir o Coolify e apontar o domínio do painel.
4. Criar banco e cache como recursos gerenciados.
5. Criar um recurso **Docker Image** por papel (web, worker, scheduler) por app.
6. Preencher os envs de cada recurso.
7. DNS dos domínios públicos apontando para o workload.
8. Criar o **GitHub App** e os segredos (abaixo) — é o que liga os dois repos.
9. Smoke test: HTTPS válido, health check, uma fila processando.

---

## O GitHub App e os segredos

O build é centralizado, e isso exige uma credencial que cruze repositórios em
dois sentidos: o app avisa este repositório, e este repositório dá `checkout` no
código do app. O `GITHUB_TOKEN` não serve — ele nunca sai do próprio repo.

Um **GitHub App** faz isso com token de 1 hora, escopado, e que não morre junto
com uma pessoa — ao contrário de um PAT.

**Criar uma vez, na organização:**

1. *Settings → Developer settings → GitHub Apps → New GitHub App*
2. Permissões de repositório: **Contents: Read and write**
3. *Install App* na organização, nos repositórios de app **e** neste de deploy
4. Gerar uma *private key* (`.pem`) e guardar o `App ID`

**Segredos de organização:**

| Segredo | Onde é usado | Para quê |
|---|---|---|
| `DEPLOY_APP_ID` | app e deploy | id do GitHub App |
| `DEPLOY_APP_PRIVATE_KEY` | app e deploy | conteúdo do `.pem` |
| `DEPLOY_REPO` | repo do app | `org/deploy.meuprojeto.com` |
| `COOLIFY_URL` · `COOLIFY_TOKEN` | deploy | API do Coolify |
| `COOLIFY_UUID_<APP>` | deploy | um por app: `COOLIFY_UUID_API`, `COOLIFY_UUID_PLATFORM`. Aceita vários UUIDs separados por vírgula, para os papéis que compartilham a imagem |
| `DOCKERHUB_USERNAME` · `DOCKERHUB_TOKEN` | deploy | só se a imagem base for privada |

> [!TIP]
> Os segredos do Coolify e do Docker Hub ficam **num repositório só** — o de
> deploy. No modelo anterior, cada repo de app precisava do seu.
