# 802.1X RADIUS (EAP-TLS + MAB)

FreeRADIUS 3.2 in a docker container for 802.1X port authentication of IP cameras.
The device authenticates with a client certificate issued by our own CA (EAP-TLS), and the
certificate CN must equal the EAP identity. Devices without 802.1X support can use MAB
(MAC Authentication Bypass): a request without EAP is accepted if the MAC reported by the
switch (`Calling-Station-Id`) is in `raddb/authorized_macs`.

## Files

| File | |
|---|---|
| `Dockerfile` | `freeradius/freeradius-server:3.2.7` + custom `eap`, `authorized_macs` modules and the `mab` policy |
| `raddb/clients.conf.example` | template for `raddb/clients.conf` (local, not in git): the switches, secret from `.env` `RADIUS_SECRET` |
| `raddb/authorized_macs.example` | template for `raddb/authorized_macs` (local, not in git): the MAB allow list |
| `raddb/mods-available/eap` | EAP-TLS only, TLS 1.2, `check_cert_cn = %{User-Name}` |
| `raddb/mods-available/authorized_macs` | `files` module keyed by the normalized `Calling-Station-Id` |
| `raddb/policy.d/mab` | first step of `authorize`: non-EAP requests are accepted or rejected by the allow list |
| `entrypoint.sh` | copies `certs/` into the container, owned by `freerad` |
| `mkcerts.sh` | CA (if missing) + server certificate + DH |
| `mkclient.sh` | device certificate: `certs/clients/<identity>.{pem,key,p12}` |
| `test/` | `eapol_test` and `radclient` checks: EAP-TLS valid/CN mismatch, MAB listed/unlisted MAC |

`certs/` (including the CA key!) is not in git, it lives only on the RADIUS host — back it up.

## Deployment

```bash
rsync -a --exclude certs/ --exclude .env radius/ <user>@<radius-host>:docker/radius/
ssh <user>@<radius-host>
cd ~/docker/radius
cp env.example .env                                # RADIUS_SECRET=$(openssl rand -base64 24)
cp raddb/clients.conf.example raddb/clients.conf   # list your switches
cp raddb/authorized_macs.example raddb/authorized_macs   # list the MAB devices
make certs                                         # once; the CA is never overwritten
sudo make build check start                        # sudo if the user is not in the docker group
sudo make test                                     # output: test.out
```

`raddb/clients.conf` and `raddb/authorized_macs` are mounted into the container, so after
editing them `sudo make restart` is enough.

### Firewall

If the host's `INPUT` policy is `DROP`, allow 1812/udp from every switch
(authentication only, accounting is not used):

```bash
sudo iptables -I INPUT -p udp --dport 1812 -s <switch-ip> -j ACCEPT
sudo netfilter-persistent save
```

## Switches

The container uses the host network. Configure each switch with the RADIUS host address on the
switch's own management subnet: the reply then comes from the same address, and `clients.conf`
matches the switch by its source IP.

RouterOS 7 example:

```
/radius add address=<radius-host-ip> secret=<RADIUS_SECRET> service=dot1x timeout=3s
/interface dot1x server add interface=<port> auth-types=dot1x
```

Warning: once the port is switched to 802.1X, the device gets network access only with a valid
certificate — install the certificate on the device first.

## Device certificate

```bash
make client NAME=<identity> P12PASS=<password>
```

On the device: EAP-TLS, identity `<identity>`, CA = `certs/ca.pem`,
client = `certs/clients/<identity>.p12` (or `.pem` + `.key`).

## MAB

For devices without 802.1X: add the MAC to `raddb/authorized_macs` (uppercase, dash-separated,
e.g. `00-11-22-33-44-55`), then `sudo make restart`. The switch may send the MAC in any format;
the server normalizes `Calling-Station-Id` before the lookup. Enable MAB on the port as well,
e.g. RouterOS 7: `/interface dot1x server set [find interface=<port>] auth-types=dot1x,mac-auth`.

A MAC address is easy to spoof: use MAB only where EAP-TLS is not possible. A listed MAC does not
weaken EAP-TLS: requests with EAP always need a valid certificate.

## Debugging

`.env`: `RADIUS_ARGS=-X`, then `sudo make restart logs`.
