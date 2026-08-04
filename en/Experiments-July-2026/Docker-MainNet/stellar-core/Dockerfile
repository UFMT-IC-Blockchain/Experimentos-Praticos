FROM stellar/quickstart:testing

LABEL description="Stellar Core Node - SCP Validator (extracted from quickstart)"

ENV COREHOME=/opt/stellar/core
ENV CORELOG=/var/log/stellar-core

# Staging: configs will be copied to the volume on first start
COPY stellar-core.cfg /etc/stellar/stellar-core.cfg
COPY entrypoint.sh /entrypoint-core.sh

RUN chmod +x /entrypoint-core.sh && \
    mkdir -p $COREHOME $CORELOG /etc/stellar && \
    chown -R stellar:stellar $COREHOME $CORELOG /etc/stellar

VOLUME ["$COREHOME", "$CORELOG"]
EXPOSE 11625 11626

ENTRYPOINT ["/entrypoint-core.sh"]
