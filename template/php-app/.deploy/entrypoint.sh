#!/usr/bin/env bash
#
# Entrypoint de PRODUÇÃO (Coolify). Deliberadamente enxuto — o oposto do "fat"
# entrypoint do modelo com rsync:
#   • NÃO faz rsync (o código já está em /var/www/html na imagem);
#   • NÃO copia .env (o Coolify injeta as envs em runtime, como variáveis reais);
#   • NÃO roda migrate (isso é "post-deployment command" no Coolify — uma vez por deploy,
#     não a cada boot de cada container).
#
# O MESMO image serve os três papéis; o papel é o CMD que o Coolify passa:
#   • web       → supervisord (nginx + php-fpm)   [CMD default deste image]
#   • worker    → php artisan horizon             [override no Coolify]
#   • scheduler → php artisan schedule:work       [override no Coolify]
set -e
cd /var/www/html

# Storage/cache: dono = usuário do POOL php-fpm — casar dono ↔ processo é o que permite
# fechar em 775 (não 777). Varia por base: www-data na imagem do kit, 1000 no pool custom
# do modelo antigo. Detecta do próprio pool pra não hardcodar (senão o worker não escreve a sessão).
FPM_USER=$(grep -rhE '^\s*user\s*=' /usr/local/etc/php-fpm.d/ 2>/dev/null | head -1 | sed -E 's/^\s*user\s*=\s*//; s/\s+$//')
FPM_USER=${FPM_USER:-www-data}
mkdir -p storage/framework/cache/data storage/framework/sessions \
         storage/framework/views storage/logs bootstrap/cache
chown -R "$FPM_USER":"$FPM_USER" storage bootstrap/cache
chmod -R 775 storage bootstrap/cache

# Caches do Laravel DEPOIS que o Coolify já injetou as envs (o build não as tem).
# config:cache é crítico (consolida env). route/view são best-effort: não derrubam o
# boot se houver rota com closure (route:cache falha nesses casos).
php artisan config:cache
php artisan route:cache  >/dev/null 2>&1 || true
php artisan view:cache   >/dev/null 2>&1 || true

# Papel do container por ENV — o tipo "Docker Image" do Coolify NÃO expõe override de
# comando, então a UI de Environment Variables resolve. Um image, três papéis:
#   web (default) → nginx + php-fpm (o CMD supervisord)
#   worker        → Horizon (fila: webhooks, jobs assíncronos)
#   scheduler     → schedule:work (cron do Laravel; alternativa à Scheduled Task nativa)
case "${CONTAINER_ROLE:-web}" in
  worker)    exec php artisan horizon ;;
  scheduler) exec php artisan schedule:work ;;
  *)         exec "$@" ;;
esac
