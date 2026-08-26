# fix-wpa2-enterprise-tls

Corrige o erro `SSL_connect error:0A000102:SSL routines::unsupported protocol` em conexoes WPA2-Enterprise (802.1X/PEAP) no Linux.

## O problema

O OpenSSL 3.x (presente no Ubuntu 22.04+, Fedora 36+, Arch, openSUSE Tumbleweed, etc.) **desabilitou por padrao** as versoes antigas de TLS (1.0 e 1.1). Quando um servidor RADIUS antigo — comum em universidades, escolas (SENAI, IF, etc.) e empresas — usa essas versoes para o tunel TLS dentro do PEAP, o wpa_supplicant recebe:

```
SSL: SSL3 alert: write (local SSL3 detected an error):fatal:protocol version
OpenSSL: openssl_handshake - SSL_connect error:0A000102:SSL routines::unsupported protocol
wlan0: CTRL-EVENT-EAP-FAILURE EAP authentication failed
```

### Como diagnosticar

```bash
journalctl -u wpa_supplicant --no-pager -n 100 | grep -i "unsupported protocol\|EAP-FAILURE"
```

Se aparecer `unsupported protocol` seguido de `EAP-FAILURE`, esse script resolve.

## A solucao

O script define `phase1-auth-flags=32` na conexao NetworkManager, que instrui o wpa_supplicant a **reabilitar TLS 1.0/1.1 apenas para aquela conexao**, sem afetar a seguranca do resto do sistema.

O equivalente manual e:

```bash
nmcli con mod <SSID> 802-1x.phase1-auth-flags 32
systemctl restart NetworkManager
```

## Instalacao e uso

```bash
# Clone o repositorio
git clone https://github.com/SEU-USER/fix-wpa2-enterprise-tls.git
cd fix-wpa2-enterprise-tls

# Torne o script executavel
chmod +x fix-wpa2-enterprise-tls.sh

# Execute com o nome da rede (precisa de sudo)
sudo ./fix-wpa2-enterprise-tls.sh ALUNOS
```

### Exemplos

```bash
sudo ./fix-wpa2-enterprise-tls.sh ALUNOS
sudo ./fix-wpa2-enterprise-tls.sh eduroam
sudo ./fix-wpa2-enterprise-tls.sh "Corporate WiFi"
```

### Listar redes 802.1x configuradas

```bash
nmcli -t -f NAME,TYPE connection show | grep 802-1x
```

## Reverter a correcao

```bash
nmcli connection modify <SSID> 802-1x.phase1-auth-flags 0
systemctl restart NetworkManager
```

## Compatibilidade

| Distribuicao | Status |
|---|---|
| Ubuntu 22.04+ | Testado |
| Debian 12+ | Testado |
| Fedora 36+ | Testado |
| Arch Linux | Testado |
| Manjaro | Testado |
| openSUSE Tumbleweed | Testado |
| Linux Mint 21+ | Funcional |
| CentOS Stream 9 | Funcional |

**Requisitos:** NetworkManager + wpa_supplicant (presente na maioria das distros desktop)

## Como funciona (detalhes tecnicos)

1. **PEAP** (Protected EAP) cria um tunel TLS entre o cliente e o servidor RADIUS
2. Dentro desse tunel, as credenciais (usuario/senha) sao autenticadas via MSCHAPv2
3. O OpenSSL 3.x so aceita TLS 1.2+ por padrao
4. Servidores RADIUS antigos podem usar TLS 1.0 ou 1.1 para o tunel
5. O `phase1-auth-flags=32` (= 0x20) corresponde a flag `NM_802_1X_AUTH_FLAGS_TLS_DISABLE_LOWEST_PROTOCOL_LEVEL`, que diz ao wpa_supplicant para **nao** desabilitar protocolos antigos

### Por que nao usar openssl.cnf?

O wpa_supplicant **nao le** `/etc/ssl/openssl.cnf`. Alteracoes nesse arquivo nao afetam a negociacao TLS feita pelo wpa_supplicant. A unica forma correta de configurar isso e via `phase1-auth-flags` (NetworkManager) ou `openssl_ciphers` (wpa_supplicant direto).

## Referencias

- [Gist original - cstanze](https://gist.github.com/cstanze/bb663ad02884932386d8c58c74c279bd)
- [Arch Linux Forum - Thread #286417](https://bbs.archlinux.org/viewtopic.php?id=286417)
- [OpenSSL Discussion #22642](https://github.com/openssl/openssl/discussions/22642)
- [Arch Linux Bug #78770](https://bugs.archlinux.org/task/78770)

## Licenca

MIT
