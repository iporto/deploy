# Como este deploy funciona

> Este arquivo explica o **modelo**, não os comandos. Para a referência de cada
> flag, veja o `README.md` ao lado. Para o passo a passo de uma migração, veja
> `docs/migration-guide.md` no projeto.
>
> Ele é compartilhado: mora em `Deploy-Scripts/` e aparece como symlink
> `deploy-readme.md` em cada projeto.

---

## A ideia central: dois canais que não se misturam

Toda mudança que chega em produção vem por **um de dois caminhos**, e confundi-los
é a origem da maioria dos enganos.

```
   CÓDIGO                                    CONFIGURAÇÃO
   (o que a aplicação faz)                   (como ela roda)

   git push na main                          você edita no seu Mac
        │                                         │
        ▼                                         ▼
   GitHub Actions constrói                   ./deploy <ambiente>
   uma IMAGEM imutável                       sincroniza ARQUIVOS
        │                                         │
        ▼                                         ▼
   você promove a tag :prd                   containers reiniciam
        │                                         │
        ▼                                         ▼
   Watchtower recria o container             a mudança vale
```

| Você mudou… | Vai por | Comando |
|---|---|---|
| PHP, Blade, JS, dependências | imagem | `./deploy-promote prd <app>` |
| Segredo, `.env`, `php.ini`, `nginx.conf` | configuração | `./deploy prd --only app` |
| `docker-compose.yml` (porta, volume, imagem) | configuração estrutural | `./deploy prd` |

> ❌ **`./deploy` não publica código novo.** Ele entrega arquivos e reinicia
> containers. Se a imagem não mudou, o código continua o mesmo.
>
> ❌ **Promover não entrega env.** A tag `:prd` só troca qual imagem roda.

---

## Por que o servidor puxa, em vez de o CI empurrar

As VMs não aceitam SSH de entrada do GitHub Actions. Isso poderia ser tratado
como limitação — mas para quem opera muitas máquinas em provedores diferentes é
uma vantagem:

- nenhuma credencial de escrita precisa existir fora da VM;
- não há bastion para manter, nem porta a abrir;
- o mecanismo é **idêntico** em todas as máquinas.

O Watchtower na VM observa a tag `:prd` e compara digests a cada 120 segundos.
Mudou, ele baixa e recria. Ninguém entra na máquina.

> ⚠️ O label `com.centurylinklabs.watchtower.enable=true` é **opt-in**. Container
> sem o label nunca é atualizado — e em alguns casos isso é proposital: os que
> leem código de volume compartilhado não devem ser recriados, porque seriam
> mortos no meio de uma execução sem ganhar nada.

---

## Por que a tag `:prd` e não `:latest`

Com `:latest`, todo build vira deploy. Você perde três coisas ao mesmo tempo:
saber o que está no ar, escolher quando sobe, e conseguir voltar.

A separação resolve as três com uma convenção de nomes:

| Tag | Muda? | Significa |
|---|---|---|
| `sha-a1b2c3d` | nunca | um commit exato — é o alvo de promoção e de rollback |
| `v1.4.2` | nunca | apelido legível do mesmo commit |
| `prd` | sim | **o que está em produção agora** |

Promover é reescrever o manifesto do registry: não constrói, não baixa camada,
leva segundos. **Rollback é a mesma operação apontando para outro SHA.**

---

## Como um segredo viaja

Os envs ficam no git, criptografados com SOPS. O valor em claro existe em três
momentos, e em nenhum deles fica em disco versionado:

```
  seu editor            túnel SSH              disco da VM
      │                     │                      │
  ./envedit  ──cifra──►  git  ──./deploy──►  .envs/api.env (600)
                                                   │
                                            bind mount :ro
                                                   │
                                              container
```

Três consequências que valem entender:

1. **O GitHub Actions não vê segredo nenhum.** Ele só constrói imagem — e a
   imagem não contém `.env`. Se o CI for comprometido, produção não vaza.
2. **A chave de decriptação nunca vai para a VM.** Servidor comprometido entrega
   os segredos *daquela* máquina, não a capacidade de ler o histórico.
3. **Sem dependência de rede.** Nenhum serviço externo participa do deploy.

> ⚠️ O container não lê o arquivo montado diretamente: o entrypoint faz
> `rsync /app/ → volume` no boot, e a aplicação lê a cópia. **Trocar o env exige
> reiniciar o container** — é por isso que `--only app` existe.

---

## Os quatro verbos

Escolher errado aqui é o que causa "mudei e não aconteceu nada" ou uma queda
desnecessária de banco.

### `./deploy-promote <ambiente> <app>`
Libera **código novo** em produção: aponta a tag `:prd` para uma imagem já
construída. Não constrói, não copia arquivo — reescreve o manifesto do registry
e o Watchtower faz o resto.

Ele resolve o SHA a partir de `origin/main`, espera o build terminar se houver
um em andamento, e recusa promover uma tag que não existe.

```bash
./deploy-promote prd api               # o caso normal
./deploy-promote prd api --now         # aplica na hora, sem esperar o Watchtower
./deploy-promote prd api sha-a1b2c3d   # rollback: mesma operação, outro SHA
./deploy-promote prd --status          # o que está no ar vs o que espera
```

Sem `--now`, o Watchtower aplica sozinho em até 120s — é o caminho normal. Com
`--now`, o script espera a promoção concluir e manda recriar os serviços daquele
app na hora, sem você precisar entrar no servidor.

> ⚠️ **Promover não entrega configuração.** A tag só troca qual imagem roda. Se
> você mudou um env, precisa de `--only app`.

### `./deploy <ambiente>`
Sincroniza tudo e **recria todos os containers** (`--force-recreate`), inclusive
banco e cache. Use quando o `docker-compose.yml` mudou.
⚠️ Derruba sessões e reinicia filas. Não é o comando do dia a dia.

### `./deploy <ambiente> --only app`
Sincroniza tudo, mas **reinicia só os serviços de aplicação**. Banco, cache e
proxy nem são tocados. É o comando para trocar segredo ou configuração.

O grupo `app` não é uma lista fixa: é derivado do compose — todo serviço que
monta um env de `.envs/`. Um serviço novo entra sozinho; `mysql` e `redis` ficam
de fora por construção, porque não montam env.

### `./deploy <ambiente> --sync-only`
Entrega arquivos e envs e **para**. Serve quando a ordem importa: por exemplo,
posicionar a senha nova antes de rodá-la no banco, e só então reiniciar.

---

## Como reconhecer os erros mais comuns

| Sintoma | O que é |
|---|---|
| Promoveu e a VM não mudou | Watchtower leva até 120s. Confira com `./deploy-promote <amb> --status` |
| Não sei se posso promover agora | `./deploy-promote <amb> <app> --check` — ou simplesmente promova: tag inexistente é recusada |
| `promote` diz que a tag não existe | O build falhou, ou você leu o SHA do `HEAD` local estando numa branch de PR. Use `origin/main` |
| O log mostra erro diferente do arquivo local | O workflow no GitHub está desatualizado. Push do repo de deploy antes de disparar build |
| Trocou o env e nada mudou | Faltou reiniciar: o container lê a cópia feita no boot |
| Container sobe e o Laravel não acha o `.env` | Rodou `./deploy-run` direto. Quem decripta e entrega os envs é o `./deploy` |
| Um serviço ficou "para trás" nas atualizações | Falta o label do Watchtower — ou a ausência é proposital |
| Todos os builds falham com `403` no `git clone` | O `PERSONAL_ACCESS_TOKEN` está com o token errado (provavelmente o do GHCR). Rode `./deploy-token-check` |

---

## Ferramentas

| Script | Papel |
|---|---|
| `deploy` | Orquestra: lê `servers.yml` e chama o `deploy-sync` por servidor |
| `deploy-promote` | Libera imagem em produção. Espera o build e verifica antes de promover |
| `deploy-sync` | Faz o rsync, decripta e entrega os envs, dispara o pós-sync |
| `deploy-run` | Sobe containers. Com ambiente (`./deploy-run prd env-app`) roda remoto a partir do Mac; sem ambiente, local na VM |
| `deploy-backup` | Dump de banco e cópia de volumes, tudo por dentro do SSH |
| `envedit` | Edita env criptografado. **Use sempre ele**, nunca `sops` cru |
| `harden-vm` | Fecha a superfície de rede da VM. Dry-run por padrão |
| `deploy-audit` | Varre todos os projetos procurando os problemas conhecidos |
| `deploy-token-check` | Diz qual capacidade falta no `PERSONAL_ACCESS_TOKEN`, antes de subi-lo |

---

## `.gitignore` e `.rsyncignore` não são o mesmo arquivo

Parecem iguais e respondem a perguntas opostas:

| | `.gitignore` | `.rsyncignore` |
|---|---|---|
| Pergunta | o que **não** entra no repositório | o que **não** vai para o servidor |
| Erra para o lado de | expor segredo no git | quebrar ou sujar a VM |
| Negação `!padrão` | funciona | **não existe** — vira padrão literal |
| `**/` | igual a qualquer nível | rsync já casa em qualquer nível sem ele |

O que muda na prática: um arquivo pode precisar estar num e não no outro.

- `.envs/*.env.prd` é **versionado** (cifrado) e **sincronizado** → em nenhum dos dois.
- `.envs/*.env` é decriptado: fora do git **e** fora do rsync — o `deploy-sync` o entrega por dentro do SSH, e o `--delete` do rsync o apagaria na VM.
- `backup*/` fora dos dois, por motivos diferentes: no git polui o histórico; no rsync **sobe o dump do banco de volta ao servidor**.
- Os symlinks (`deploy`, `envedit`, …) entram no git normalmente, mas **não** no rsync: o alvo não existe na VM.

> ⚠️ Copiar o `.gitignore` por cima do `.rsyncignore` deixa a VM desprotegida em silêncio — o deploy continua funcionando, só que enviando o que não devia.

---

## Duas armadilhas que já custaram caro

**`ufw` não bloqueia porta publicada pelo Docker.** O Docker escreve na chain
`FORWARD` antes do ufw. Um `-p 3306:3306` continua exposto mesmo com `ufw deny`.
Só a chain `DOCKER-USER` — ou publicar em `127.0.0.1` — resolve de fato.

**`ssh` dentro de `while read` engole a lista.** O ssh lê stdin por padrão e
consome o resto da entrada do laço. O sintoma é sempre o mesmo e sempre
enganoso: processa o primeiro item e reporta sucesso. Já causou backup sem
banco e volumes faltando. Itere sobre array, nunca sobre `while read` com ssh
dentro.
