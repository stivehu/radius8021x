FROM freeradius/freeradius-server:3.2.7

COPY raddb/mods-available/eap /etc/freeradius/mods-available/eap
COPY raddb/mods-available/authorized_macs /etc/freeradius/mods-available/authorized_macs
COPY raddb/mods-available/eap_md5_users /etc/freeradius/mods-available/eap_md5_users
COPY raddb/mods-available/peap_users /etc/freeradius/mods-available/peap_users
COPY raddb/policy.d/mab /etc/freeradius/policy.d/mab
COPY raddb/policy.d/md5_users /etc/freeradius/policy.d/md5_users
COPY entrypoint.sh /radius-entrypoint.sh

# Log accepted/rejected authentications (radius.log)
# MAB runs first in authorize (policy.d/mab), then the EAP-MD5 password lookup (policy.d/md5_users)
# The PEAP-MSCHAPv2 password lookup (peap_users) runs first in the inner-tunnel authorize
RUN sed -i 's/^\(\s*auth\) = no/\1 = yes/' /etc/freeradius/radiusd.conf \
    && ln -s ../mods-available/authorized_macs /etc/freeradius/mods-enabled/authorized_macs \
    && ln -s ../mods-available/eap_md5_users /etc/freeradius/mods-enabled/eap_md5_users \
    && ln -s ../mods-available/peap_users /etc/freeradius/mods-enabled/peap_users \
    && sed -i '0,/^authorize {$/s//authorize {\n\tmab\n\tmd5_users/' /etc/freeradius/sites-available/default \
    && grep -qx '\smab' /etc/freeradius/sites-available/default \
    && grep -qx '\smd5_users' /etc/freeradius/sites-available/default \
    && sed -i '0,/^authorize {$/s//authorize {\n\tpeap_users/' /etc/freeradius/sites-available/inner-tunnel \
    && grep -qx '\speap_users' /etc/freeradius/sites-available/inner-tunnel \
    && chmod 755 /radius-entrypoint.sh

ENTRYPOINT ["/radius-entrypoint.sh"]
CMD ["freeradius"]
