# enterprise-wifi-fix

Corrige Wi-Fi WPA2-Enterprise (802.1X/PEAP) em qualquer Linux.

Resolve o erro:
```
OpenSSL: openssl_handshake - SSL_connect error:0A000102:SSL routines::unsupported protocol
```

## Instalacao

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/sshs3rejo/enterprise-wifi-fix/main/enterprise-wifi-fix.sh)"
```

Uma unica execucao, sem nada pra configurar.

## Distribuicoes suportadas

| Distro | Fix aplicado |
|---|---|
| Ubuntu 22.04+ | phase1-auth-flags + openssl.cnf |
| Debian 12/13 | phase1-auth-flags + openssl.cnf |
| Linux Mint | phase1-auth-flags + openssl.cnf |
| Pop!_OS | phase1-auth-flags + openssl.cnf |
| Fedora | phase1-auth-flags + crypto-policies |
| RHEL / CentOS Stream | phase1-auth-flags + crypto-policies |
| Rocky / AlmaLinux | phase1-auth-flags + crypto-policies |
| openSUSE Tumbleweed | phase1-auth-flags + crypto-policies |
| Arch Linux | phase1-auth-flags |
| Manjaro | phase1-auth-flags |

## O que faz

1. Detecta automaticamente a distro e o sistema de crypto
2. Aplica `phase1-auth-flags=32` em todas as conexoes 802.1x (universal)
3. No Fedora/RHEL/openSUSE: ajusta `crypto-policies` para permitir TLS 1.0/1.1
4. No Ubuntu/Debian/Mint: modifica `openssl.cnf` com backup automatico
5. Reinicia os servicos de rede

## Reverter

Fedora/RHEL/openSUSE:
```bash
sudo update-crypto-policies --set DEFAULT
sudo systemctl restart NetworkManager
```

Ubuntu/Debian/Mint:
```bash
sudo cp /etc/ssl/openssl.cnf.bak.enterprise-wifi-fix /etc/ssl/openssl.cnf
sudo systemctl restart NetworkManager
```

## Referencias

- https://gist.github.com/cstanze/bb663ad02884932386d8c58c74c279bd
- https://bbs.archlinux.org/viewtopic.php?id=286417
- https://discussion.fedoraproject.org/t/fedora-39-802-1x-tls-authentication-does-not-work/96382
