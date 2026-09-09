# Imagem de PRODUÇÃO da API (deploy via Coolify).
# Base = a MESMA imagem custom do dev → paridade de runtime (PHP 8.3 + extensões).
#
# Diferenças deliberadas vs o padrão "fat" com rsync (adequação ao Coolify):
#   • serve o código direto de /var/www/html (sem rsync p/ volume compartilhado);
#   • NÃO embute .env (o Coolify injeta envs em runtime);
#   • NÃO roda migrate no boot (é "post-deployment command" no Coolify);
#   • worker/scheduler são o MESMO image com CMD trocado (horizon / schedule:work).
# Versão FIXA de propósito. Com :latest, um rebuild meses depois troca o PHP
# embaixo de quem já estava rodando — e o sintoma aparece longe da causa.
FROM iporto99/php-8-3:1.5

# nginx é a única peça que a base não traz (no dev ele é um container à parte).
RUN apt-get update \
 && apt-get install -y --no-install-recommends nginx \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /var/www/html

# 1) Dependências primeiro — camada cacheada enquanto composer.* não muda.
COPY composer.json composer.lock ./
RUN composer install --no-dev --prefer-dist --no-progress --no-interaction \
      --no-scripts --optimize-autoloader

# 2) Código da aplicação (vendor/.git/.env/bootstrap-cache ficam de fora via .dockerignore).
COPY . .
RUN mkdir -p bootstrap/cache storage/framework/cache/data storage/framework/sessions \
             storage/framework/views storage/logs \
 && composer dump-autoload --optimize --no-dev \
 && rm -rf .git .github tests

# 3) Runtime: nginx + supervisor + entrypoint.
COPY .deploy/nginx.conf       /etc/nginx/conf.d/default.conf
COPY .deploy/supervisord.conf /etc/supervisord.conf
COPY .deploy/entrypoint.sh    /usr/local/bin/entrypoint
RUN rm -f /etc/nginx/sites-enabled/default \
 && chmod +x /usr/local/bin/entrypoint

EXPOSE 80
ENTRYPOINT ["/usr/local/bin/entrypoint"]
CMD ["supervisord", "-c", "/etc/supervisord.conf", "-n"]
