FROM stellar/quickstart:testing

LABEL description="Stellar Horizon - API + Captive Core + PostgreSQL (extraido do quickstart)"

ENV STELLAR_HOME=/opt/stellar
ENV HZHOME=$STELLAR_HOME/horizon
ENV PGHOME=$STELLAR_HOME/postgresql
ENV PGDATA=$PGHOME/data
ENV PGBIN=/usr/lib/postgresql/14/bin
ENV PGUSER=stellar
ENV PGPORT=5432
ENV PGPASS=stellar

# Nginx conf
COPY nginx.conf /etc/nginx/sites-available/default

# Configs em staging (copiados para o volume no primeiro start)
COPY stellar-captive-core.cfg /etc/stellar/stellar-captive-core.cfg
COPY horizon.env /etc/stellar/horizon.env

# Entrypoint
COPY entrypoint.sh /entrypoint-horizon.sh
RUN chmod +x /entrypoint-horizon.sh

# Ajusta permissoes
RUN mkdir -p $HZHOME/captive-core && \
    chown -R stellar:stellar $HZHOME

VOLUME ["$HZHOME", "$PGDATA"]
EXPOSE 8000 5432

ENTRYPOINT ["/entrypoint-horizon.sh"]
