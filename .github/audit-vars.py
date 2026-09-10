#!/usr/bin/env python3
"""Variável de cor usada sem ser definida.

`bash -n` não pega isto: é erro de RUNTIME, e com `set -u` mata o script na hora
em que a linha é alcançada. Como muitas dessas linhas estão em caminhos raros
(erro, --adopt, primeira execução), o defeito chega ao usuário.
Foi o que aconteceu com o DIM no deploy-scaffold-project.
"""
import glob, os, re, sys

CORES = ['RED', 'GREEN', 'YELLOW', 'BLUE', 'MAG', 'CYAN', 'BOLD', 'DIM', 'NC']
padrao_uso = re.compile(r'\$\{(' + '|'.join(CORES) + r')\}')
padrao_def = re.compile(r'\b(' + '|'.join(CORES) + r')=')

# Array que pode estar vazio, iterado sem o idioma seguro.
# Em bash 3.2 (o do macOS) `for x in "${arr[@]}"` com arr vazio e `set -u` morre
# com "unbound variable" — só quando o array está vazio, que costuma ser o
# caminho raro. O idioma ${arr[@]+"${arr[@]}"} é o único que preserva $#=0.
padrao_vazio = re.compile(r'^\s*(\w+)=\(\)\s*$', re.M)

def arrays_desprotegidos(texto):
    achados = []
    for v in sorted(set(padrao_vazio.findall(texto))):
        for m in re.finditer(r'for\s+\w+\s+in\s+"\$\{' + v + r'\[@\]\}"', texto):
            achados.append((texto[:m.start()].count('\n') + 1, v))
    return achados

falhas = 0
for caminho in sorted(glob.glob('*') + glob.glob('template/*')):
    if not os.path.isfile(caminho) or not os.access(caminho, os.X_OK):
        continue
    with open(caminho, encoding='utf-8', errors='ignore') as fh:
        texto = fh.read()
    if not texto.startswith('#!'):
        continue
    faltando = sorted(set(padrao_uso.findall(texto)) - set(padrao_def.findall(texto)))
    if faltando:
        print(f"::error file={caminho}::cor usada sem definir: {', '.join(faltando)}")
        falhas += 1
    inseguros = arrays_desprotegidos(texto)
    for linha, v in inseguros:
        print(f'::error file={caminho},line={linha}::array {v} pode estar vazio: '
              f'use ${{{v}[@]+"${{{v}[@]}}"}} — bash 3.2 mata com set -u')
        falhas += 1
    if not faltando and not inseguros:
        print(f"  ok    {caminho}")

sys.exit(1 if falhas else 0)
