#!/usr/bin/env bash
#
# enterprise-wifi-fix
# Corrige WPA2-Enterprise (802.1X/PEAP) em Linux
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

OPENSSL_CNF="/etc/ssl/openssl.cnf"
BACKUP="${OPENSSL_CNF}.bak.$(date +%Y%m%d%H%M%S)"

# --- 1. Backup do openssl.cnf ---

info "Criando backup do $OPENSSL_CNF..."
cp "$OPENSSL_CNF" "$BACKUP"
ok "Backup salvo em: $BACKUP"

# --- 2. Verificar se ja foi aplicado ---

if grep -q "MinProtocol = TLSv1" "$OPENSSL_CNF" 2>/dev/null; then
    warn "Correcao TLS ja aplicada neste sistema."
else
    info "Aplicando correcao TLS no $OPENSSL_CNF..."

    # Se ja existe uma secao ssl_sect, nao duplica
    if grep -q "\[ssl_sect\]" "$OPENSSL_CNF"; then
        warn "Secao [ssl_sect] ja existe. Verifique $OPENSSL_CNF manualmente."
    else
        # Verificar se openssl_init ja existe e tem ssl_conf
        if grep -q "ssl_conf = ssl_sect" "$OPENSSL_CNF"; then
            # ssl_conf ja aponta para ssl_sect, so adicionar a secao
            cat >> "$OPENSSL_CNF" << 'EOF'

[ssl_sect]
system_default = system_default_sect

[system_default_sect]
MinProtocol = TLSv1
CipherString = DEFAULT:@SECLEVEL=0
EOF
        else
            # Adicionar ssl_conf ao openssl_init e criar a secao
            sed -i '/^\[openssl_init\]/a ssl_conf = ssl_sect' "$OPENSSL_CNF"
            cat >> "$OPENSSL_CNF" << 'EOF'

[ssl_sect]
system_default = system_default_sect

[system_default_sect]
MinProtocol = TLSv1
CipherString = DEFAULT:@SECLEVEL=0
EOF
        fi
        ok "TLS 1.0/1.1 habilitado no OpenSSL."
    fi
fi

# --- 3. Aplicar phase1-auth-flags em conexoes 802.1x existentes ---

info "Verificando conexoes 802.1x configuradas..."

if command -v nmcli &>/dev/null; then
    CONNS=$(nmcli -t -f NAME,TYPE connection show 2>/dev/null | grep "802-1x" | cut -d: -f1 || true)
    if [[ -n "$CONNS" ]]; then
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
    else
        warn "Nenhuma conexao 802.1x encontrada no NetworkManager."
    fi
else
    warn "NetworkManager nao encontrado. Apenas o openssl.cnf foi modificado."
fi

# --- 4. Reiniciar servicos ---

info "Reiniciando servicos de rede..."
systemctl restart wpa_supplicant 2>/dev/null || true
systemctl restart NetworkManager 2>/dev/null || true
sleep 2
ok "Servicos reiniciados."

# --- Resumo ---

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
echo "  sudo cp '$BACKUP' '$OPENSSL_CNF'"
echo "  sudo systemctl restart NetworkManager"
echo ""
echo "Backup: $BACKUP"
