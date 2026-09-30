# Coolify — dimensionar e ajustar as aplicações

Como decidir memória, CPU e as variáveis de PHP de uma aplicação já publicada.

Este documento começa onde o [coolify-setup.md](coolify-setup.md) termina: lá o
Resource nasce e recebe as envs da aplicação; aqui se decide **quanto** dar a ele
e **o que** ajustar quando estiver apertado.

Vale para todo projeto `deploy.*` que usa a imagem PHP padrão. O entrypoint é o
mesmo em todos — entre a iPORTO e a Casa das Brasileirinhas ele difere em duas
linhas, ambas comentário.

---

## A regra que dispensa quase tudo

**`pm.max_children` se ajusta sozinho ao limite de memória do container.** O
entrypoint lê o limite do cgroup no boot e calcula:

```
max_children = (memória do container − 416 MB de reserva) / 64 MB por worker
```

Consequência prática: **o ajuste que move a agulha é o limite de memória da
aplicação no painel do Coolify**, não uma variável de ambiente. Subiu a memória,
o pool acompanha — sem env nova e sem rebuild.

Os 416 MB de reserva não são chute: são o opcache (256 MB no `php.ini` da imagem)
mais nginx, o master do php-fpm e o sistema. O que sobra é o que os workers podem
ocupar.

| memória do container | `max_children` |
|---|---|
| 1 GB | 9 |
| 2 GB | 25 |
| 8 GB | 121 |
| 18 GB | 281 |

Cada boot registra a conta no log. É a primeira coisa a olhar quando o
dimensionamento não parece ter pegado:

```
[entrypoint] php-fpm: max_children=281 start=70 spare=35-140  (cgroup: (18432MB - 416MB reserva) / 64MB por worker)
```

O trecho entre parênteses diz **de onde veio o número**, e são três casos com
comportamentos diferentes:

| origem | quando | piso | teto |
|---|---|---|---|
| `cgroup: ...` | o normal — há limite de memória no Resource | 4 | 512 |
| `env FPM_MAX_CHILDREN` | alguém forçou o valor | 4 | nenhum |
| `default (limite... não legível)` | **o Resource está sem limite de memória** | 4 | 64 |

⚠️ O terceiro caso é um alerta, não um modo de operação. Sem limite de memória o
entrypoint não tem como calcular, cai em 12 workers com teto de 64, e a aplicação
fica muito abaixo do que a máquina aguenta. Se o log disser `default`, **defina o
limite de memória no Coolify** — é isso que ele está pedindo.

Os outros três parâmetros do pool derivam do `max_children` e não se configuram:
`start_servers` = ¼, `min_spare` = ⅛, `max_spare` = ½.

---

## Dimensionar memória e CPU

O método, não um número: cada aplicação tem um perfil.

**1. Meça antes de decidir.** O que importa é o RSS médio por worker e o pico de
memória do container. `docker stats` dá o número real; `memory.current` e
`memory.peak` do cgroup incluem page cache, que é recuperável e infla o valor.

⚠️ Já aconteceu de um app parecer usar 5,6 GB por `memory.peak` e usar 0,9 GB de
verdade. Descontar o cache antes de dimensionar evita provisionar seis vezes o
necessário.

**2. Faça a conta.** Para um app `web`:

```
memória necessária ≈ (workers simultâneos × RSS médio) + 416 MB
```

Para um `worker` (Horizon), o que manda é a soma dos `maxProcesses` de
`config/horizon.php`, não o `max_children`:

```
memória necessária ≈ (soma dos maxProcesses × RSS do maior worker)
```

**3. Deixe ~15% do host livre.** Um limite de container igual à RAM da máquina não
deixa margem para o sistema operacional.

### Os dois sintomas que enganam

**Pool cheio com CPU ociosa.** Se o log traz `server reached pm.max_children` e o
host está com load baixo, os workers estão **esperando**, não calculando — banco,
Redis ou HTTP externo lento. Subir `max_children` trata o sintoma; a causa é uma
consulta ou chamada externa. O slowlog (abaixo) aponta onde.

**Workers mortos sem o container reiniciar.** Com `oom_group_kill = 0`, o kernel
mata workers isolados por falta de memória, o supervisor os recria e o
`RestartCount` do container segue em 0. Nada fica vermelho, e cada morte dessas é
um job interrompido no meio. Confira `oom_kill` no cgroup, não o estado do
container.

---

## As variáveis

Os defaults vivem no `php.ini` e no `php-fpm-pool.conf` da imagem. Estas envs
sobrescrevem **em runtime**, sem rebuild — é o que permite ajustar pelo painel do
Coolify e reimplantar.

| variável | ajusta | default da imagem |
|---|---|---|
| `PHP_MEMORY_LIMIT` | `memory_limit` | `256M` |
| `PHP_UPLOAD_MAX_FILESIZE` | `upload_max_filesize` | `50M` |
| `PHP_POST_MAX_SIZE` | `post_max_size` | `64M` |
| `PHP_MAX_INPUT_VARS` | `max_input_vars` | `5000` |
| `PHP_MAX_EXECUTION_TIME` | `max_execution_time` | `60` |
| `PHP_TIMEZONE` | `date.timezone` | `America/Sao_Paulo` |
| `PHP_OPCACHE_MEMORY` | `opcache.memory_consumption` | `256` |
| `PHP_OPCACHE_ENABLE_CLI` | `opcache.enable_cli` | `0` |
| `FPM_MAX_CHILDREN` | força `pm.max_children`, **ignora o cálculo** | — |
| `FPM_WORKER_MEMORY_MB` | memória por worker **na conta** | `64` |
| `FPM_RESERVE_MEMORY_MB` | reserva **na conta** | `416` |
| `FPM_SLOWLOG_TIMEOUT` | `request_slowlog_timeout`; `0` desliga | `10s` |

⚠️ `FPM_WORKER_MEMORY_MB` e `FPM_RESERVE_MEMORY_MB` mudam **a aritmética**, não o
consumo. Baixar o primeiro não faz o worker ocupar menos memória — faz o
entrypoint achar que cabem mais, e é assim que se estoura a RAM.

⚠️ `PHP_MAX_EXECUTION_TIME` convive com dois outros tetos no pool:
`request_terminate_timeout` (120s) e `php_admin_value[max_execution_time]` (60s).
O `php_admin_value` **não** é sobrescrevível por `ini_set` na aplicação. Se um
script precisa de mais tempo, subir só a env não resolve.

### Diagnóstico: o slowlog

Toda requisição que passa de 10s tem o backtrace despejado em
`/var/log/php-fpm-slow.log`, com 20 níveis. É o caminho mais curto entre "a API
está lenta" e a linha de código responsável. `FPM_SLOWLOG_TIMEOUT` ajusta o
limiar; `0` desliga.

---

## Por papel

A mesma imagem serve três papéis, escolhidos por `CONTAINER_ROLE`. O
dimensionamento e os ajustes mudam com ele.

| papel | executa | o que ajustar |
|---|---|---|
| `web` | supervisord → nginx + php-fpm | memória do container (o pool acompanha) |
| `worker` | `php artisan horizon` | `PHP_MEMORY_LIMIT` maior; `PHP_OPCACHE_ENABLE_CLI=1` |
| `scheduler` | `php artisan schedule:work` | quase nada — costuma ser o mais folgado |

`CONTAINER_ROLE` aceita apelidos: `worker` = `queue` = `horizon`, e
`scheduler` = `command` = `cron`.

**No `worker`, ligue `PHP_OPCACHE_ENABLE_CLI=1`.** O default é `0` porque para CLI
de vida curta o opcache só custa; o Horizon é processo longo, e aí compensa.

**No `worker`, `max_children` não significa nada** — não há php-fpm ali. Quem
define a concorrência é `config/horizon.php`.

⚠️ `CONTAINER_ROLE` **não tem default**, de propósito. Um Resource de worker criado
sem ela abortava o boot com mensagem explícita — antes, subia um container **web**:
nginx no ar, health check verde, e nenhum job processado. A falha só aparecia
horas depois, como fila crescendo, longe da causa.

---

## Stop grace period

No Coolify, em *Advanced* → *Stop grace period*. O padrão do Docker é **10
segundos**, e depois vem SIGKILL. Sem ajustar, **todo deploy mata jobs no meio**.

| papel | valor | por quê |
|---|---|---|
| `worker` | ≥ o job mais longo (1h, 2h se houver vídeo) | o Horizon trata SIGTERM e drena a fila |
| `scheduler` | ~120s | espera o comando em andamento terminar |
| `web` | ~30s | tempo de fechar as requisições em curso |

O entrypoint usa `exec`, então o processo do Laravel é o PID 1 e recebe o SIGTERM
diretamente. O que falta é só dar tempo a ele.

---

## Nem toda aplicação tem PHP

Nada deste documento se aplica a apps que não usam a imagem PHP. Numa SPA
Angular servida por nginx, por exemplo, as `PHP_*` e `FPM_*` são **ignoradas em
silêncio**: ninguém as lê, e configurá-las no painel dá a impressão de um ajuste
que não existe.

Antes de ajustar, confirme que a app tem `.docker/Bin/entrypoint.sh` no
repositório de código. Se não tem, não é a imagem PHP.

---

## Onde está a verdade

O comportamento descrito aqui vem de três arquivos, **no repositório de código de
cada app**:

| arquivo | o que define |
|---|---|
| `.docker/Bin/entrypoint.sh` | quais envs existem e o cálculo do pool |
| `.docker/Php/php.ini` | os defaults de PHP |
| `.docker/Php/php-fpm-pool.conf` | os defaults do pool |

⚠️ Este documento descreve um **contrato**, e o contrato mora lá. Se alguém
acrescentar uma env no entrypoint, ela não aparece aqui sozinha. Ao mexer nesses
arquivos, atualize esta tabela de variáveis junto — é o mesmo cuidado do
`server` em `deploy-destinations.json`.

Para conferir a lista de uma vez, no repositório de código da app:

```bash
grep -oE '\$\{(PHP|FPM)_[A-Z_]+:-' .docker/Bin/entrypoint.sh \
  | sed 's/\${//; s/:-$//' | sort -u \
  | grep -vxF "$(grep -oE '^[A-Z_]+=' .docker/Bin/entrypoint.sh | tr -d '=')"
```

O `:-` seleciona o que é **lido** com default, e o último filtro descarta o que o
script **atribui** — `FPM_WORKER_MB`, `FPM_RESERVE_MB` e `FPM_USER` são variáveis
internas, não envs para configurar no painel. Sem esse filtro elas aparecem na
lista e induzem ao erro.

---

## Armadilhas

- **Resource sem limite de memória.** O cálculo cai no fallback (12 workers, teto
  64) e a app fica muito abaixo do que a máquina aguenta. O log diz `default`.
- **Ajustar `FPM_WORKER_MEMORY_MB` achando que reduz consumo.** Muda a conta, não
  o uso. Reduzir esse número é pedir para estourar a RAM.
- **Subir `PHP_MAX_EXECUTION_TIME` e o script continuar morrendo.** Há
  `php_admin_value[max_execution_time]` no pool, que a aplicação não sobrescreve.
- **Configurar `PHP_*` numa app Angular.** Não faz nada e não avisa.
- **Deploy matando jobs.** *Stop grace period* ainda no padrão de 10s.
- **Fila parada com tudo verde.** Resource de worker sem `CONTAINER_ROLE` não sobe
  mais em silêncio — mas se o boot está abortando, é isso. Veja o log.
