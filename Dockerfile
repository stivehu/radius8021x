FROM freeradius/freeradius-server:3.2.7

COPY raddb/mods-available/eap /etc/freeradius/mods-available/eap
COPY raddb/mods-available/authorized_macs /etc/freeradius/mods-available/authorized_macs
COPY raddb/policy.d/mab /etc/freeradius/policy.d/mab
COPY entrypoint.sh /radius-entrypoint.sh

# Log accepted/rejected authentications (radius.log)
# MAB runs first in authorize (policy.d/mab)
RUN sed -i 's/^\(\s*auth\) = no/\1 = yes/' /etc/freeradius/radiusd.conf \
    && ln -s ../mods-available/authorized_macs /etc/freeradius/mods-enabled/authorized_macs \
    && sed -i '0,/^authorize {$/s//authorize {\n\tmab/' /etc/freeradius/sites-available/default \
    && grep -qx '\smab' /etc/freeradius/sites-available/default \
    && chmod 755 /radius-entrypoint.sh

ENTRYPOINT ["/radius-entrypoint.sh"]
CMD ["freeradius"]
