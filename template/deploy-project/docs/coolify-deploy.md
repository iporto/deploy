# Deploy em produção

> Onde as imagens deste repositório vão parar, e o que você precisa preencher.

Este projeto **não** sobe por `./deploy`. A esteira do aparato antigo
(rsync + Watchtower + SOPS) serve outra trilha. O scaffold entrega este projeto
apontado para **Coolify** — que é uma opção, não a única.

## O modelo

```
push no repo do app
  └─ versiona (tag + Release) e avisa ESTE repositório por repository_dispatch
       └─ ESTE repositório constrói, com o Dockerfile de .docker/Code/<app>/
            └─ ghcr.io/<owner>/<projeto>-<app>:sha-… · :vX.Y.Z · :prd
                 └─ POST /api/v1/deploy no Coolify
                      └─ o workload puxa :prd e recria o container
```

**O build é centralizado aqui.** O repositório do app não tem Dockerfile: ele
versiona o commit e avisa. Um Dockerfile mudado aqui vale para todos os apps no
mesmo commit, e o contexto de build é inspecionado antes do push — é o que
permite a varredura de segredo em texto puro que o `_build-image.yml` faz antes
de publicar a camada.

O build sai da máquina que roda os containers, e a imagem versionada no registry
funciona como backup fora da VM. No Coolify, cada app é do tipo **Docker Image**
— não Git+Dockerfile.

Um mesmo image serve três papéis, escolhidos por `CONTAINER_ROLE`:

| Papel | `CONTAINER_ROLE` | Processo |
|---|---|---|
| Web (padrão) | *(vazio)* | supervisord → nginx + php-fpm |
| Worker | `worker` | `php artisan horizon` |
| Scheduler | `scheduler` | `php artisan schedule:work` |

---

## O que preencher

1. **Equipar os repos dos apps** com o workflow de aviso:

   ```bash
   deploy-scaffold-app ./code --apply
   ```

2. **Os segredos deste repositório** (*Settings → Secrets and variables →
   Actions*):

   | Segredo | O que é |
   |---|---|
   | `DEPLOY_APP_ID` · `DEPLOY_APP_PRIVATE_KEY` | o GitHub App que cruza os dois repositórios |
   | `COOLIFY_URL` · `COOLIFY_TOKEN` | painel e token da API |
   | `DOCKERHUB_USERNAME` · `DOCKERHUB_TOKEN` | só se a imagem base for privada |

   E, **no repositório de cada app**: `DEPLOY_APP_ID`,
   `DEPLOY_APP_PRIVATE_KEY` e `DEPLOY_REPO` (`org/deploy.meuprojeto.com`).

3. **O `coolify_uuid`** em `.github/workflows/build.<app>.yml`, depois de criar
   o recurso no Coolify. Ele é **versionado, não segredo**: sozinho não autoriza
   nada — quem autoriza é o `COOLIFY_TOKEN`.

   ```yaml
         coolify_uuid: 'abc123'          # vários, separados por vírgula
   ```

   **Vazio, a esteira publica a imagem e não dispara deploy nenhum.** É o estado
   certo antes de o destino existir — e é também a trilha inteira de quem não
   usa Coolify.

---

## Os runbooks

O passo a passo não vive neste arquivo: ele é o mesmo para todos os projetos e
mora na biblioteca, onde é corrigido uma vez só.

| | |
|---|---|
| **Onde isso roda** | `docs/deployment-targets.md` da biblioteca — as três trilhas (VM própria, Coolify, só a imagem), o que um destino precisa saber fazer e como trocar depois |
| **Coolify do zero** | `docs/coolify-setup.md` — criar token, projeto, recurso e envs, no painel **e** por API; de onde sai o `coolify_uuid`; a tabela de sintomas |
| **A esteira** | `docs/production-pipeline.md` — as três tags, o GitHub App passo a passo, rollback |

Online: <https://github.com/iporto/deploy/tree/main/docs>

---

## Específico deste projeto

> Preencha abaixo o que só vale aqui: domínios, quais papéis existem, quais
> serviços gerenciados (banco, cache) e qualquer desvio do padrão. O resto está
> nos runbooks acima.

- Domínios:
- Papéis no ar:
- Banco / cache:
- Desvios do padrão:
