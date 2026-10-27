FROM freeradius/freeradius-server:3.2.7

COPY raddb/mods-available/eap /etc/freeradius/mods-available/eap
COPY entrypoint.sh /bkt-entrypoint.sh

# Log accepted/rejected authentications (radius.log)
RUN sed -i 's/^\(\s*auth\) = no/\1 = yes/' /etc/freeradius/radiusd.conf \
    && chmod 755 /bkt-entrypoint.sh

ENTRYPOINT ["/bkt-entrypoint.sh"]
CMD ["freeradius"]
