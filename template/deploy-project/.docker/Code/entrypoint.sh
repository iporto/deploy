#!/usr/bin/env bash
#
# Entrypoint de produção. Enxuto por desenho — o oposto do "fat" entrypoint do
# modelo com rsync:
#   • NÃO faz rsync: o código já está em /var/www/html na imagem;
#   • NÃO copia .env: as envs chegam como variáveis de ambiente do runtime;
#   • NÃO roda migrate: é passo de pós-deploy, uma vez por deploy — não a cada
#     boot de cada container.
#
# O MESMO image serve os três papéis, selecionados por CONTAINER_ROLE:
#   • web       → supervisord (nginx + php-fpm)   [CMD default deste image]
#   • worker    → php artisan horizon
#   • scheduler → php artisan schedule:work
set -e
cd /var/www/html

mkdir -p storage/framework/cache/data storage/framework/sessions \
         storage/framework/views storage/logs bootstrap/cache

# Caches do Laravel DEPOIS que as envs de runtime existem — o build não as tem.
# config:cache é crítico (consolida env). route/view são best-effort: não derrubam o
# boot se houver rota com closure (route:cache falha nesses casos).
php artisan config:cache
php artisan route:cache  >/dev/null 2>&1 || true
php artisan view:cache   >/dev/null 2>&1 || true

# Storage/cache: dono = usuário do POOL php-fpm — casar dono ↔ processo é o que permite
# fechar em 775 (não 777). Varia por base: www-data na imagem do kit, 1000 no pool custom
# do modelo antigo. Detecta do próprio pool pra não hardcodar (senão o worker não escreve a sessão).
#
# ⚠️ É o ÚLTIMO passo antes do exec, de propósito. Tudo acima roda como root; o que root criar
#    em storage/ (um laravel.log, uma view compilada) nasce 644 root, e o FPM, que roda como
#    $FPM_USER, não consegue abrir em append: a PRIMEIRA request que logar estoura com 500 —
#    "could not be opened in append mode: Permission denied" (Spelt, 2026-10-30: os cadastros
#    pararam em produção por isso). Entregar o storage por último cobre o boot.
#
#    O setgid nos diretórios cobre o que vem DEPOIS do boot como root (o post-deployment command
#    do Coolify, um `php artisan` digitado no terminal do painel): o arquivo nasce com o grupo
#    $FPM_USER. A outra metade fica na app: `'permission' => 0664` nos canais single/daily de
#    config/logging.php, para o grupo poder escrever. Sem o par (setgid + 0664) o problema volta
#    no primeiro comando de terminal. Melhor ainda: LOG_CHANNEL=stderr em produção, sem arquivo.
FPM_USER=$(grep -rhE '^\s*user\s*=' /usr/local/etc/php-fpm.d/ 2>/dev/null | head -1 | sed -E 's/^\s*user\s*=\s*//; s/\s+$//')
FPM_USER=${FPM_USER:-www-data}
chown -R "$FPM_USER":"$FPM_USER" storage bootstrap/cache
chmod -R 775 storage bootstrap/cache
find storage bootstrap/cache -type d -exec chmod g+s {} +

# Papel do container por variável de ambiente, não por CMD: nem todo runtime
# permite trocar o comando de um image pronto. Um image, três papéis:
#   web (default) → nginx + php-fpm (o CMD supervisord)
#   worker        → Horizon (fila: webhooks, jobs assíncronos)
#   scheduler     → schedule:work (cron do Laravel; alternativa à Scheduled Task nativa)
case "${CONTAINER_ROLE:-web}" in
  worker)    exec php artisan horizon ;;
  scheduler) exec php artisan schedule:work ;;
  *)         exec "$@" ;;
esac
