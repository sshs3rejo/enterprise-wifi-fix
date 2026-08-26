#!/usr/bin/env bash
#
# fix-wpa2-enterprise-tls.sh
# Corrige o erro "SSL_connect error:0A000102:SSL routines::unsupported protocol"
# em conexoes WPA2-Enterprise (802.1X/PEAP) causado pelo OpenSSL 3.x que
# desabilita versoes antigas de TLS por padrao.
#
# Distribuicoes suportadas: qualquer Linux com NetworkManager + wpa_supplicant
# (Ubuntu, Debian, Fedora, Arch, Manjaro, openSUSE, Linux Mint, etc.)
#
# Uso:
#   sudo ./fix-wpa2-enterprise-tls.sh <SSID_DA_REDE>
#
# Exemplo:
#   sudo ./fix-wpa2-enterprise-tls.sh ALUNOS
#   sudo ./fix-wpa2-enterprise-tls.sh eduroam
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[AVISO]${NC} $*"; }
err()   { echo -e "${RED}[ERRO]${NC} $*" >&2; }

# --- Verificacao de pre-requisitos ---

if [[ $EUID -ne 0 ]]; then
    err "Este script precisa ser executado como root (sudo)."
    exit 1
fi

if [[ $# -lt 1 ]]; then
    echo "Uso: $0 <SSID_DA_REDE>"
    echo ""
    echo "Exemplos:"
    echo "  $0 ALUNOS"
    echo "  $0 eduroam"
    echo ""
    echo "Para listar redes WPA2-Enterprise configuradas:"
    echo "  nmcli -t -f NAME,TYPE connection show | grep 802-1x"
    exit 1
fi

SSID="$1"

# Verifica se o NetworkManager esta disponivel
if ! command -v nmcli &>/dev/null; then
    err "NetworkManager (nmcli) nao encontrado. Este script requer NetworkManager."
    exit 1
fi

# Verifica se a conexao existe
if ! nmcli -t -f NAME connection show | grep -qx "$SSID"; then
    err "Conexao '$SSID' nao encontrada no NetworkManager."
    echo ""
    info "Conexoes disponiveis:"
    nmcli -t -f NAME,TYPE connection show | grep 802-1x || echo "  (nenhuma conexao 802.1x encontrada)"
    exit 1
fi

# Verifica se e uma conexao 802.1x
CONN_TYPE=$(nmcli -t -f TYPE connection show "$SSID" 2>/dev/null || true)
if [[ "$CONN_TYPE" != *"802-1x"* ]] && [[ "$CONN_TYPE" != *"wifi"* ]]; then
    warn "A conexao '$SSID' parece nao ser uma conexao WiFi/802.1x (tipo: $CONN_TYPE)."
    warn "Continuando mesmo assim..."
fi

# --- Verificacao do problema ---

info "Verificando se o erro TLS esta presente nos logs..."
TLS_ERROR=$(journalctl -u wpa_supplicant --no-pager -n 200 2>/dev/null \
    | grep -c "unsupported protocol" || true)

if [[ "$TLS_ERROR" -gt 0 ]]; then
    ok "Erro TLS detectado nos logs recentes ($TLS_ERROR ocorrencias)."
else
    warn "Nenhum erro TLS recente detectado. Aplicando correcao preventivamente..."
fi

# --- Aplicacao da correcao ---

info "Aplicando phase1-auth-flags=32 na conexao '$SSID'..."
info "  (isso habilita TLS 1.0/1.1 para esta conexao especifica)"
echo ""

# Metodo 1: via nmcli (funciona em qualquer distro com NM)
nmcli connection modify "$SSID" 802-1x.phase1-auth-flags 32
ok "Correcao aplicada via nmcli."

# Verificar se pegou
CURRENT_FLAGS=$(nmcli -t -f 802-1x.phase1-auth-flags connection show "$SSID" 2>/dev/null || true)
if [[ "$CURRENT_FLAGS" == *"32"* ]] || [[ "$CURRENT_FLAGS" == *"0x20"* ]]; then
    ok "phase1-auth-flags configurado corretamente: $CURRENT_FLAGS"
else
    warn "Valor atual: $CURRENT_FLAGS (esperado: 32 ou 0x20)"
fi

# --- Reiniciar servicos ---

info "Reiniciando NetworkManager e wpa_supplicant..."
systemctl restart wpa_supplicant 2>/dev/null || true
systemctl restart NetworkManager 2>/dev/null || true
sleep 2
ok "Servicos reiniciados."

# --- Instrucoes finais ---

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  CORRECAO APLICADA COM SUCESSO!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "A rede '$SSID' deve conectar automaticamente em alguns instantes."
echo ""
echo "Se nao conectar automaticamente, execute:"
echo "  nmcli connection up '$SSID'"
echo ""
echo "--- O que foi feito ---"
echo "O OpenSSL 3.x (presente em distros modernas) desabilita por padrao"
echo "TLS 1.0 e 1.1. Servidores RADIUS antigos usam essas versoes para"
echo "o tunel TLS do PEAP. O flag 'phase1-auth-flags=32' instrui o"
echo "wpa_supplicant a reabilitar esses protocolos APENAS para esta"
echo "conexao, sem afetar a seguranca do resto do sistema."
echo ""
echo "--- Para reverter ---"
echo "  nmcli connection modify '$SSID' 802-1x.phase1-auth-flags 0"
echo "  systemctl restart NetworkManager"
echo ""
echo "--- Referencias ---"
echo "  https://gist.github.com/cstanze/bb663ad02884932386d8c58c74c279bd"
echo "  https://bbs.archlinux.org/viewtopic.php?id=286417"
