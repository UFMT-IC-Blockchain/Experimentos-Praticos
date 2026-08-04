FROM stellar/quickstart:testing

LABEL description="Stellar Horizon - API + Captive Core + PostgreSQL (extracted from quickstart)"

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

# Configs in staging (copied to the volume on first start)
COPY stellar-captive-core.cfg /etc/stellar/stellar-captive-core.cfg
COPY horizon.env /etc/stellar/horizon.env

# Entrypoint
COPY entrypoint.sh /entrypoint-horizon.sh
RUN chmod +x /entrypoint-horizon.sh

# Adjust permissions
RUN mkdir -p $HZHOME/captive-core && \
    chown -R stellar:stellar $HZHOME

VOLUME ["$HZHOME", "$PGDATA"]
EXPOSE 8000 5432

ENTRYPOINT ["/entrypoint-horizon.sh"]
