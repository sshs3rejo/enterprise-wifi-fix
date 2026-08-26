# enterprise-wifi-fix

Corrige Wi-Fi WPA2-Enterprise (802.1X/PEAP) no Linux.

Resolve o erro:
```
OpenSSL: openssl_handshake - SSL_connect error:0A000102:SSL routines::unsupported protocol
```

## Instalacao

```bash
git clone https://github.com/USUARIO/enterprise-wifi-fix.git
cd enterprise-wifi-fix
chmod +x enterprise-wifi-fix.sh
sudo ./enterprise-wifi-fix.sh
```

Pronto. Uma unica execucao.

## O que faz

1. Faz backup do `/etc/ssl/openssl.cnf`
2. Habilita TLS 1.0/1.1 no OpenSSL (necessario para servidores RADIUS antigos)
3. Aplica `phase1-auth-flags=32` em todas as conexoes 802.1x do NetworkManager
4. Reinicia os servicos de rede

## Reverter

```bash
sudo cp /etc/ssl/openssl.cnf.bak.* /etc/ssl/openssl.cnf
sudo systemctl restart NetworkManager
```

## Referencias

- https://gist.github.com/cstanze/bb663ad02884932386d8c58c74c279bd
- https://bbs.archlinux.org/viewtopic.php?id=286417
