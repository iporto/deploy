# Deploy em produção — Coolify

> Este projeto **não** sobe por `./deploy`. A esteira do aparato antigo
> (rsync + Watchtower + SOPS) serve outra trilha. Aqui a produção é **Coolify**.

## O modelo

```
push no repo do app
  └─ GitHub Actions builda o Dockerfile do próprio repo
       └─ ghcr.io/<owner>/<projeto>-<app>
            └─ POST /api/v1/deploy no Coolify
                 └─ o workload puxa a imagem e recria o container
```

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
8. Configurar o webhook de auto-deploy e guardar o secret no repo do app.
9. Smoke test: HTTPS válido, health check, uma fila processando.
