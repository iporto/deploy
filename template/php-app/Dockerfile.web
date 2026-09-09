# Imagem de PRODUÇÃO do Platform (deploy via Coolify).
# Igual à da API, + build do Vite. Base = a MESMA imagem custom do dev.
#
#   • serve o código direto de /var/www/html (sem rsync);
#   • NÃO embute .env (Coolify injeta em runtime);
#   • NÃO roda migrate no boot (o painel normalmente nem migra — a API é a dona do schema).
# Versão FIXA de propósito. Com :latest, um rebuild meses depois troca o PHP
# embaixo de quem já estava rodando — e o sintoma aparece longe da causa.
FROM iporto99/php-8-3:1.5

# nginx é a única peça que a base não traz.
RUN apt-get update \
 && apt-get install -y --no-install-recommends nginx \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /var/www/html

# 1) Dependências PHP primeiro (camada cacheada).
COPY composer.json composer.lock ./
RUN composer install --no-dev --prefer-dist --no-progress --no-interaction \
      --no-scripts --optimize-autoloader

# 2) Assets do Vite. node/npm vêm na base. As VITE_* do kit são só do dev-server
#    (HMR) — o bundle de produção resolve a base da API em runtime, então o build
#    não precisa de .env nem de build-args. node_modules sai no fim (imagem enxuta).
COPY package.json package-lock.json ./
# npm install (não `ci`): tolera lockfile levemente defasado do dev sem quebrar o build
# (o lock não é recommitado — a imagem é efêmera). Troque por `npm ci` se mantiver o lock em dia.
RUN npm install --no-audit --no-fund

# 3) Código + build + limpeza.
COPY . .
RUN mkdir -p bootstrap/cache storage/framework/cache/data storage/framework/sessions \
             storage/framework/views storage/logs \
 && composer dump-autoload --optimize --no-dev \
 && npm run build \
 && rm -rf node_modules .git .github tests

# 4) Runtime: nginx + supervisor + entrypoint.
COPY .deploy/nginx.conf       /etc/nginx/conf.d/default.conf
COPY .deploy/supervisord.conf /etc/supervisord.conf
COPY .deploy/entrypoint.sh    /usr/local/bin/entrypoint
RUN rm -f /etc/nginx/sites-enabled/default \
 && chmod +x /usr/local/bin/entrypoint

EXPOSE 80
ENTRYPOINT ["/usr/local/bin/entrypoint"]
CMD ["supervisord", "-c", "/etc/supervisord.conf", "-n"]
