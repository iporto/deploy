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
        print(f"::error file={caminho}::usa sem definir: {', '.join(faltando)}")
        falhas += 1
    else:
        print(f"  ok    {caminho}")

sys.exit(1 if falhas else 0)
