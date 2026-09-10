# Template do projeto de deploy

> Este diretório é o **molde** que o `deploy-scaffold-project` copia ao criar um
> projeto. Editar aqui muda o padrão de todos os projetos gerados **a partir de
> agora** — os que já existem receberam cópias, não links.
>
> Este `README.md` **não** é copiado para os projetos. Veja o porquê abaixo.

---

## Os quatro marcadores

Na cópia, o scaffold roda um `sed` trocando estes marcadores. Use-os em qualquer
arquivo novo em vez de escrever um domínio fixo:

| Marcador | Vira | Exemplo |
|---|---|---|
| `__DOMAIN__` | domínio de produção | `xyz.com` |
| `__DEVDOMAIN__` | domínio de desenvolvimento | `xyz.test` |
| `__PROJECT__` | slug — prefixo dos containers | `xyz` |
| `__DEVIP__` | IP para o arquivo `hosts` | `127.0.0.1` |

Nove dos arquivos daqui usam marcador; o resto é copiado literal.

---

## Mudar um padrão

Edite o arquivo e pronto. O próximo `deploy-scaffold-project` já sai com a
mudança.

## Adicionar um arquivo novo

> [!WARNING]
> **Largar o arquivo aqui não basta.** O `deploy-scaffold-project` tem uma lista
> explícita `FILES=()`; o que não está nela é **ignorado em silêncio** — sem
> erro, sem aviso, o arquivo simplesmente não aparece no projeto gerado.

São dois passos:

1. Crie o arquivo aqui, usando os marcadores quando precisar do domínio.
2. Acrescente a linha `origem|destino` ao `FILES=()` no `deploy-scaffold-project`.

```bash
# no deploy-scaffold-project
FILES=(
  # …
  ".docker/Nginx/conf/sites-enabled/admin.conf|.docker/Nginx/conf/sites-enabled/admin.conf"
)
```

Origem e destino são iguais na maioria dos casos — os dois campos existem para
quando o nome precisa mudar na cópia.

Se o arquivo só deve existir em alguns projetos, siga o padrão do `www.conf`,
que entra condicionalmente:

```bash
$WWW && FILES+=(".docker/Nginx/conf/sites-enabled/www.conf|…")
```

---

## Levar uma mudança para um projeto que já existe

Projeto gerado não se atualiza sozinho, e o `--adopt` **preserva** o que já
existe. Para puxar um arquivo do template por cima do antigo, apague o local
primeiro:

```bash
cd ~/Projects/deploy.xyz.com
rm .docker/Php/conf/php-ini/php.ini
deploy-scaffold-project xyz.com --dir . --adopt --apply
```

O `--adopt` cria só o que falta. Tudo o mais fica intacto, inclusive `code/`.

> [!TIP]
> Antes de apagar, veja o que você perderia: `git diff` no projeto mostra o que
> foi ajustado à mão desde a geração.

---

## O que nunca entra aqui

> [!CAUTION]
> Nada de segredo. Este diretório é público e é copiado para todo projeto novo.

- ❌ Chave privada — o `.docker/Ssh/` traz só o `config`; a chave é de cada projeto.
- ❌ Senha ou token em `.env.dev.example` — o `.example` é template, os valores
  ficam em branco com um comentário explicando como gerar.
- ❌ Caminho absoluto ou nome de usuário — foi o defeito do `mutagen.yml`, que
  gravava o caminho da máquina de quem criou o projeto.
- ❌ Nome de cliente ou de produto real, mesmo em comentário.

---

## Por que este README não é copiado

Exatamente pelo mecanismo descrito acima: ele não está no `FILES=()`. A lista
explícita, que é armadilha ao adicionar um arquivo, aqui é a garantia de que a
documentação do molde não vaza para dentro dos projetos.

O `template/php-app/` — os artefatos de build que o `deploy-scaffold-app`
instala nos repositórios de app — funciona igual, com a própria lista `PAIRS=()`.
