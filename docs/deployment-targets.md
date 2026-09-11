# Onde isso roda

> **Data:** 2026-09-11 · **Decisão:** o destino é intercambiável; a esteira não.
> **Escopo:** o que esta biblioteca garante, onde ela para, e o que um destino
> precisa saber fazer para receber o resultado.

O Coolify aparece muito na documentação desta biblioteca porque é o que os
projetos novos usam. **Ele não é a trilha única.** A esteira termina numa imagem
no registry; quem puxa essa imagem é escolha sua, e a biblioteca suporta três
respostas — inclusive "eu mesmo, na minha VM, sem painel nenhum".

---

## O contrato

A parte que não muda, seja qual for o destino:

```
push no repo do app
  └─ tag SemVer + Release + repository_dispatch  (notify-deploy.yml)
       └─ o repo de deploy constrói com .docker/Code/<app>/Dockerfile
            ├─ varredura de segredo no CONTEXTO   ← antes de existir camada
            ├─ ghcr.io/<owner>/<projeto>-<app>:sha-abc1234
            ├─                                   :v1.4.0
            ├─                                   :prd        ← o ponteiro
            └─ varredura de segredo na IMAGEM     ← antes de publicar
                 ╎
                 ╎  ─────── aqui a biblioteca termina ───────
                 ╎
                 └─▶ o destino puxa :prd e recria o container
```

**Tudo acima da linha é igual nas três trilhas.** Build centralizado, as três
tags, as duas varreduras, o GitHub App — ver
[`production-pipeline.md`](production-pipeline.md).

O que um destino precisa saber fazer, e é só isto:

1. **Autenticar no GHCR** com um token de `read:packages`.
2. **Puxar `:prd`** e recriar o container quando a tag mudar de digest.
3. *(opcional)* **Aceitar um aviso** de que mudou, para não depender de polling.

Qualquer coisa que faça esses três itens serve. O item 3 é o único onde a
biblioteca oferece integração pronta — e só para o Coolify.

---

## As três trilhas

| | VM própria | Coolify | Só a imagem |
|---|---|---|---|
| Quem recria o container | Watchtower ou `./deploy-run` | o Coolify, avisado por HTTP | o que você já usa |
| O que a esteira faz no fim | publica a imagem | publica **e avisa** | publica |
| Painel | nenhum | sim | o seu |
| Configuração vive em | `.env.prd` cifrado, no git | envs do recurso, no painel | você decide |
| Envs chegam por | `deploy-sync` (bind mount) | injeção em runtime | você decide |
| TLS | Traefik que você configura | automático | você decide |
| Verbos usados | `deploy`, `deploy-sync`, `deploy-run`, `deploy-promote`, `envedit`, `deploy-backup` | nenhum | nenhum |
| `coolify_uuid` no `build.<app>.yml` | vazio | preenchido | vazio |

---

## Trilha 1 — VM própria, com os verbos

A trilha original, e a que o Spelt usa em produção. A biblioteca inteira nasceu
dela: `./deploy prd` leva compose, configs e envs decriptados para a VM por rsync
e SSH; o Watchtower observa `:prd` e recria o container quando o digest muda.

**Escolha esta quando:** você quer a configuração versionada e cifrada no git
(SOPS + age), quer o mesmo `docker-compose.prd.yml` que lê em código, ou tem
requisito que painel nenhum atende — catch-all de domínio white-label, por
exemplo, foi o que manteve o Spelt aqui.

**O preço:** você configura Traefik, certificados, backup e firewall. O
`harden-vm` e o `deploy-backup` cobrem parte disso; o resto é seu.

```bash
./deploy prd                  # configuração e envs → VM
./deploy-promote api --now    # move :prd e aplica sem esperar o Watchtower
./deploy-backup prd           # dump dos bancos para ./backups/
```

> A promoção é **manual e separada do build** nesta trilha. Construir não põe no
> ar. É o que permite construir dez vezes e promover uma.

---

## Trilha 2 — Coolify

O destino é um recurso do tipo **Docker Image** num painel Coolify, e o
`_build-image.yml` faz `POST /api/v1/deploy` no fim do build.

**Escolha esta quando:** você não quer operar TLS, proxy e painel de logs à mão,
e aceita que a configuração de produção viva no painel em vez do git.

**O preço:** o estado do destino sai do repositório. O que está configurado no
recurso só existe lá — daí o runbook em [`coolify-setup.md`](coolify-setup.md)
insistir em criar tudo por API, que é a forma de ter o comando versionado.

> [!NOTE]
> **Aqui o build põe no ar.** Não há passo de promoção separado: o push na `main`
> do app vira container novo. Se você quer o intervalo entre construir e liberar,
> ou usa a trilha 1, ou deixa `coolify_uuid` vazio e dispara o deploy à mão.

---

## Trilha 3 — só a imagem

O `_build-image.yml` pula o passo do Coolify quando `coolify_uuid` está vazio:

```yaml
      - name: Disparar deploy no Coolify
        if: env.COOLIFY_APP_UUID != ''
```

Sem uuid, a esteira publica as três tags e termina. **Não é um estado degradado
— é uma trilha.** O destino pode ser um `docker compose pull && up -d` num cron,
um Portainer, um Dokploy, um k8s com `imagePullPolicy: Always`, ou uma pessoa
rodando um comando quando decide.

O que você ganha mesmo assim: build reprodutível fora da máquina de produção, as
duas varreduras de segredo, as três tags e a imagem versionada no registry
servindo de backup fora da VM.

**Para avisar o seu destino**, acrescente um passo ao `build.<app>.yml` — é um
`curl` no lugar do nosso:

```yaml
      - name: Avisar o meu destino
        run: curl -fsS -X POST "$MEU_WEBHOOK" -H "Authorization: Bearer $MEU_TOKEN"
```

---

## Como trocar de trilha

Nenhuma troca exige reconstruir imagem — as tags já publicadas continuam
válidas, porque o que muda é só quem as puxa.

| De → Para | O que fazer |
|---|---|
| Só a imagem → Coolify | Criar o recurso ([`coolify-setup.md`](coolify-setup.md)) e preencher `coolify_uuid` no `build.<app>.yml` |
| Coolify → só a imagem | Esvaziar `coolify_uuid`. O recurso continua no ar com a imagem que tem |
| Coolify → VM própria | `deploy-scaffold-project --adopt` no projeto, escrever o `docker-compose.prd.yml`, mover os envs do painel para `.env.prd` com o `envedit` |
| VM própria → Coolify | Criar os recursos, transcrever os envs, apontar o DNS, esvaziar o Watchtower |

> ⚠️ **O caminho Coolify → git é o trabalhoso**, e é o único que perde
> informação: envs digitados no painel não têm histórico. Se há chance de voltar,
> mantenha o bloco de env do recurso também num arquivo — o runbook mostra como
> aplicá-lo por API a partir de um arquivo, exatamente por isso.

---

## Replicação

Para levar esta decisão a outro projeto:

1. Escolha a trilha **antes** de rodar `deploy-scaffold-project`. Ela não muda o
   scaffold — muda o que você preenche depois.
2. Trilha 1: escreva o `docker-compose.prd.yml` e o `servers.yml`; rode
   `harden-vm --apply` na VM.
3. Trilha 2: siga [`coolify-setup.md`](coolify-setup.md) e preencha
   `coolify_uuid`.
4. Trilha 3: não preencha nada. Acrescente o seu `curl` se quiser aviso.

## Checklist de auditoria

- [ ] `coolify_uuid` preenchido **só** nos projetos da trilha 2
- [ ] Nenhum projeto da trilha 2 tem Watchtower no compose (as duas coisas
      recriando o mesmo container brigam entre si)
- [ ] Nenhum destino aponta para `:latest` — a tag não existe, por decisão
- [ ] Token de `read:packages` válido no destino, seja ele qual for
- [ ] Trilha 1: `.env.prd` cifrado e `deploy-backup` agendado
- [ ] Trilha 2: bloco de env do recurso também guardado fora do painel
