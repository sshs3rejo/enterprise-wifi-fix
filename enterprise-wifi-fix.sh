#!/usr/bin/env bash
#
# enterprise-wifi-fix
# Corrige WPA2-Enterprise (802.1X/PEAP) em qualquer Linux
# Resolve: OpenSSL: openssl_handshake - SSL_connect error:0A000102:SSL routines::unsupported protocol
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

if [[ $EUID -ne 0 ]]; then
    err "Execute como root: sudo $0"
    exit 1
fi

# ============================================================
# PASSO 1: Detectar distro e sistema de crypto
# ============================================================

DISTRO="unknown"
CRYPTO_SYSTEM="none"

if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    DISTRO="${ID:-unknown}"
fi

# Detectar crypto-policies (Fedora, RHEL, CentOS, Rocky, Alma, openSUSE)
if command -v update-crypto-policies &>/dev/null; then
    CRYPTO_SYSTEM="crypto-policies"
    CRYPTO_CURRENT=$(update-crypto-policies --show 2>/dev/null || echo "unknown")
fi

info "Distribuicao detectada: $DISTRO"
info "Sistema de crypto: $CRYPTO_SYSTEM"
[[ "$CRYPTO_SYSTEM" == "crypto-policies" ]] && info "Policy atual: $CRYPTO_CURRENT"
echo ""

# ============================================================
# PASSO 2: Correcao via NetworkManager (UNIVERSAL - todos os grupos)
# ============================================================

fix_networkmanager() {
    info "=== Correcao NetworkManager (universal) ==="

    if ! command -v nmcli &>/dev/null; then
        warn "NetworkManager nao encontrado. Pulando."
        return
    fi

    CONNS=$(nmcli -t -f NAME,TYPE connection show 2>/dev/null | grep "802-1x" | cut -d: -f1 || true)
    if [[ -z "$CONNS" ]]; then
        warn "Nenhuma conexao 802.1x encontrada."
        return
    fi

    while IFS= read -r conn; do
        FLAGS=$(nmcli -t -f 802-1x.phase1-auth-flags connection show "$conn" 2>/dev/null || true)
        if echo "$FLAGS" | grep -qE "32|0x20"; then
            ok "'$conn': phase1-auth-flags ja configurado."
        else
            info "Aplicando phase1-auth-flags=32 em '$conn'..."
            nmcli connection modify "$conn" 802-1x.phase1-auth-flags 32
            ok "'$conn': correcao aplicada."
        fi
    done <<< "$CONNS"
}

# ============================================================
# PASSO 3: Correcao crypto-policies (Fedora, RHEL, openSUSE, etc.)
# ============================================================

fix_crypto_policies() {
    if [[ "$CRYPTO_SYSTEM" != "crypto-policies" ]]; then
        return
    fi

    info "=== Correcao crypto-policies ==="

    if [[ "$CRYPTO_CURRENT" == *"LEGACY"* ]]; then
        ok "Policy ja esta em LEGACY."
        return
    fi

    # Em vez de LEGACY (muito permissivo), criar uma subpolicy sob DEFAULT
    # que apenas reabilita TLS 1.0/1.1
    info "Aplicando update-crypto-policies --set DEFAULT:NO-SHA1..."
    if update-crypto-policies --set "DEFAULT:NO-SHA1" 2>/dev/null; then
        ok "Policy atualizada para DEFAULT:NO-SHA1."
    else
        warn "DEFAULT:NO-SHA1 falhou. Tentando LEGACY..."
        update-crypto-policies --set LEGACY
        ok "Policy atualizada para LEGACY."
    fi
}

# ============================================================
# PASSO 4: Correcao openssl.cnf (Ubuntu, Debian, Mint, etc.)
# ============================================================

fix_openssl_cnf() {
    if [[ "$CRYPTO_SYSTEM" == "crypto-policies" ]]; then
        return
    fi

    info "=== Correcao openssl.cnf ==="

    OPENSSL_CNF="/etc/ssl/openssl.cnf"
    BACKUP="${OPENSSL_CNF}.bak.enterprise-wifi-fix"

    if [[ ! -f "$OPENSSL_CNF" ]]; then
        warn "$OPENSSL_CNF nao encontrado. Pulando."
        return
    fi

    # Backup (so cria se ainda nao existe)
    if [[ ! -f "$BACKUP" ]]; then
        cp "$OPENSSL_CNF" "$BACKUP"
        ok "Backup salvo em: $BACKUP"
    fi

    if grep -q "MinProtocol = TLSv1" "$OPENSSL_CNF" 2>/dev/null; then
        ok "openssl.cnf ja modificado."
        return
    fi

    # Verificar se a secao ssl_sect ja existe
    if grep -q "\[ssl_sect\]" "$OPENSSL_CNF"; then
        warn "[ssl_sect] ja existe em $OPENSSL_CNF. Verifique manualmente."
        return
    fi

    # Adicionar ssl_conf se nao existe
    if ! grep -q "ssl_conf = ssl_sect" "$OPENSSL_CNF"; then
        sed -i '/^\[openssl_init\]/a ssl_conf = ssl_sect' "$OPENSSL_CNF"
    fi

    # Adicionar secao ssl_sect
    cat >> "$OPENSSL_CNF" << 'EOF'

[ssl_sect]
system_default = system_default_sect

[system_default_sect]
MinProtocol = TLSv1
CipherString = DEFAULT:@SECLEVEL=0
EOF

    ok "openssl.cnf atualizado."
}

# ============================================================
# PASSO 5: Reiniciar servicos
# ============================================================

restart_services() {
    info "=== Reiniciando servicos ==="

    local restarted=0

    if [[ "$CRYPTO_SYSTEM" == "crypto-policies" ]]; then
        systemctl restart wpa_supplicant 2>/dev/null && restarted=1 || true
    fi

    systemctl restart NetworkManager 2>/dev/null && restarted=1 || true

    if [[ "$restarted" -eq 1 ]]; then
        sleep 2
        ok "Servicos reiniciados."
    fi
}

# ============================================================
# EXECUCAO
# ============================================================

fix_networkmanager
fix_crypto_policies
fix_openssl_cnf
restart_services

# ============================================================
# RESUMO
# ============================================================

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  CORRECAO APLICADA COM SUCESSO!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "As redes WPA2-Enterprise devem conectar normalmente."
echo ""
echo "Se nao conectar, reinicie o Wi-Fi ou execute:"
echo "  sudo systemctl restart NetworkManager"
echo ""
echo "Para reverter:"
case "$CRYPTO_SYSTEM" in
    crypto-policies)
        echo "  sudo update-crypto-policies --set DEFAULT"
        echo "  sudo systemctl restart NetworkManager"
        ;;
    *)
        if [[ -f "/etc/ssl/openssl.cnf.bak.enterprise-wifi-fix" ]]; then
            echo "  sudo cp /etc/ssl/openssl.cnf.bak.enterprise-wifi-fix /etc/ssl/openssl.cnf"
            echo "  sudo systemctl restart NetworkManager"
        fi
        ;;
esac
