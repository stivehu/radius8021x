# 802.1X RADIUS (EAP-TLS + EAP-MD5 + MAB)

FreeRADIUS 3.2 in a docker container for 802.1X port authentication of IP cameras.
The device authenticates with a client certificate issued by our own CA (EAP-TLS), and the
certificate CN must equal the EAP identity. Devices that support 802.1X but not EAP-TLS can
use EAP-MD5 with a per-device password from `raddb/eap_md5_users`. Devices without 802.1X support can use MAB
(MAC Authentication Bypass): a request without EAP is accepted if the MAC reported by the
switch (`Calling-Station-Id`) is in `raddb/authorized_macs`.

## Files

| File | |
|---|---|
| `Dockerfile` | `freeradius/freeradius-server:3.2.7` + custom `eap`, `authorized_macs`, `eap_md5_users` modules and the `mab` policy |
| `raddb/clients.conf.example` | template for `raddb/clients.conf` (local, not in git): the switches, secret from `.env` `RADIUS_SECRET` |
| `raddb/authorized_macs.example` | template for `raddb/authorized_macs` (local, not in git): the MAB allow list |
| `raddb/eap_md5_users.example` | template for `raddb/eap_md5_users` (local, not in git): the EAP-MD5 passwords |
| `raddb/mods-available/eap` | EAP-TLS (default, TLS 1.2, `check_cert_cn = %{User-Name}`) and EAP-MD5 |
| `raddb/mods-available/authorized_macs` | `files` module keyed by the normalized `Calling-Station-Id` |
| `raddb/mods-available/eap_md5_users` | `files` module keyed by `User-Name`: sets `Cleartext-Password` for EAP-MD5 |
| `raddb/policy.d/mab` | first step of `authorize`: non-EAP requests are accepted or rejected by the allow list |
| `raddb/policy.d/md5_users` | second step of `authorize`: password lookup, and EAP-MD5 offered first to the listed identities |
| `entrypoint.sh` | copies `certs/` into the container, owned by `freerad` |
| `mkcerts.sh` | CA (if missing) + server certificate + DH |
| `mkclient.sh` | device certificate: `certs/clients/<identity>.{pem,key,p12}` |
| `fetch-clients.sh` | `make fetch-clients`: copies `certs/clients/` from the RADIUS host (`RADIUS_REMOTE` in `.env`) via scp |
| `test/` | `eapol_test` and `radclient` checks: EAP-TLS valid/CN mismatch, EAP-MD5 valid/wrong password/unknown identity, first offered EAP type (MD5/TLS), MAB listed/unlisted MAC |

`certs/` (including the CA key!) is not in git, it lives only on the RADIUS host — back it up.

## Deployment

```bash
rsync -a --exclude certs/ --exclude .env radius/ <user>@<radius-host>:docker/radius/
ssh <user>@<radius-host>
cd ~/docker/radius
cp env.example .env                                # RADIUS_SECRET=$(openssl rand -base64 24)
cp raddb/clients.conf.example raddb/clients.conf   # list your switches
cp raddb/authorized_macs.example raddb/authorized_macs   # list the MAB devices
cp raddb/eap_md5_users.example raddb/eap_md5_users       # set the EAP-MD5 passwords (test-md5 too)
make certs                                         # once; the CA is never overwritten
sudo make build check start                        # sudo if the user is not in the docker group
sudo make test                                     # output: test.out
```

`raddb/clients.conf`, `raddb/authorized_macs` and `raddb/eap_md5_users` are mounted into the container, so after
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

## EAP-MD5

For devices that support 802.1X but not EAP-TLS: add a line to `raddb/eap_md5_users`, then
`sudo make restart`:

```
<identity> Cleartext-Password := "<password>"
```

On the device: EAP-MD5, identity `<identity>`, the same password. The server offers EAP-MD5
first to the identities listed here (`raddb/policy.d/md5_users`): some MD5-only devices do not
NAK EAP-TLS, they restart with a new EAP-Identity instead.

EAP-MD5 has no server authentication and no keying material, and a captured exchange allows an
offline dictionary attack: use long random passwords (`openssl rand -base64 24`) and prefer
EAP-TLS wherever the device supports it. `make test` needs the `test-md5` entry with a password
other than `change-me`.

## MAB

For devices without 802.1X: add the MAC to `raddb/authorized_macs` (uppercase, dash-separated,
e.g. `00-11-22-33-44-55`), then `sudo make restart`. The switch may send the MAC in any format;
the server normalizes `Calling-Station-Id` before the lookup. Enable MAB on the port as well,
e.g. RouterOS 7: `/interface dot1x server set [find interface=<port>] auth-types=dot1x,mac-auth`.

A MAC address is easy to spoof: use MAB only where EAP-TLS is not possible. A listed MAC does not
weaken EAP-TLS: requests with EAP always need a valid certificate.

## Debugging

`.env`: `RADIUS_ARGS=-X`, then `sudo make restart logs`.
