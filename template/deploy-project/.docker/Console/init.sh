#!/bin/bash

# Configuração para rodar CRON
chmod 0644 /etc/cron.d/crontab
/usr/bin/crontab /etc/cron.d/crontab

# Configuração para rodar Supervisor
/usr/bin/supervisord

tail -f /dev/null