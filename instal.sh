#!/usr/bin/env bash
set -e

# =====================================
# CONFIGURACIÓN GENERAL
# =====================================
WG_IF="wg0"
WG_PORT=51820
WG_NET="10.50.0.0/24"
WG_SERVER_IP="10.50.0.1/24"
WG_CLIENT_IP="10.50.0.2/24"

# =====================================
# VALIDAR ROOT
# =====================================
if [ "$EUID" -ne 0 ]; then
  echo "[ERROR] Ejecuta este script como root"
  exit 1
fi

# =====================================
# LOGS
# =====================================
log_info() { echo -e "\e[34m[INFO]\e[0m $1"; }
log_ok()   { echo -e "\e[32m[OK]\e[0m $1"; }
log_err()  { echo -e "\e[31m[ERROR]\e[0m $1"; }

pause() { read -p "Presiona ENTER para continuar..."; }

# =====================================
# DEPENDENCIAS
# =====================================
deps() {
  log_info "Instalando dependencias"
  apt update -y
  apt install -y wireguard iptables-persistent
}

# =====================================
# WIREGUARD SERVER
# =====================================
wg_server() {
  clear
  log_info "Configurando WireGuard SERVER"
  deps

  umask 077
  wg genkey | tee /etc/wireguard/server.key | wg pubkey > /etc/wireguard/server.pub
  SERVER_PRIV=$(cat /etc/wireguard/server.key)

  cat > /etc/wireguard/${WG_IF}.conf <<EOF
[Interface]
Address = ${WG_SERVER_IP}
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIV}
SaveConfig = true
PostUp = iptables -A FORWARD -i ${WG_IF} -j ACCEPT; iptables -A FORWARD -o ${WG_IF} -j ACCEPT
PostDown = iptables -D FORWARD -i ${WG_IF} -j ACCEPT; iptables -D FORWARD -o ${WG_IF} -j ACCEPT
EOF

  sysctl -w net.ipv4.ip_forward=1
  grep -q net.ipv4.ip_forward /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

  systemctl enable wg-quick@${WG_IF}
  systemctl restart wg-quick@${WG_IF}

  log_ok "WireGuard SERVER listo"
  echo ""
  echo "CLAVE PÚBLICA DEL SERVER:"
  cat /etc/wireguard/server.pub
  pause
}

# =====================================
# WIREGUARD CLIENT
# =====================================
wg_client() {
  clear
  log_info "Configurando WireGuard CLIENT"

  read -p "IP pública del SERVER: " SERVER_IP
  read -p "Clave pública del SERVER: " SERVER_PUB

  deps

  umask 077
  wg genkey | tee /etc/wireguard/client.key | wg pubkey > /etc/wireguard/client.pub
  CLIENT_PRIV=$(cat /etc/wireguard/client.key)

  cat > /etc/wireguard/${WG_IF}.conf <<EOF
[Interface]
Address = ${WG_CLIENT_IP}
PrivateKey = ${CLIENT_PRIV}

[Peer]
PublicKey = ${SERVER_PUB}
Endpoint = ${SERVER_IP}:${WG_PORT}
AllowedIPs = ${WG_NET}
PersistentKeepalive = 25
EOF

  systemctl enable wg-quick@${WG_IF}
  systemctl restart wg-quick@${WG_IF}

  log_ok "WireGuard CLIENT listo"
  echo ""
  echo "CLAVE PÚBLICA DEL CLIENT:"
  cat /etc/wireguard/client.pub
  pause
}

# =====================================
# FIREWALL BACKEND (ANTI ATAQUES)
# =====================================
firewall_backend() {
  clear
  log_info "Aplicando firewall estricto (backend)"

  iptables -P INPUT DROP
  iptables -P FORWARD DROP
  iptables -P OUTPUT ACCEPT

  iptables -A INPUT -i lo -j ACCEPT
  iptables -A INPUT -i ${WG_IF} -j ACCEPT

  iptables-save > /etc/iptables/rules.v4

  log_ok "Firewall aplicado correctamente"
  pause
}

# =====================================
# ESTADO
# =====================================
status_wg() {
  clear
  wg show || log_err "WireGuard no está activo"
  pause
}

# =====================================
# MENÚ PRINCIPAL
# =====================================
while true; do
  clear
  echo "=========================================="
  echo "  PROTECCIÓN VPS - TÚNEL WIREGUARD"
  echo "=========================================="
  echo ""
  echo " [1] Instalar WireGuard SERVER (VPS público)"
  echo " [2] Instalar WireGuard CLIENT (Servidor real)"
  echo " [3] Aplicar Firewall (Servidor real)"
  echo " [4] Ver estado WireGuard"
  echo ""
  echo " [0] Salir"
  echo ""
  read -p "Selecciona una opción: " opt

  case "$opt" in
    1) wg_server ;;
    2) wg_client ;;
    3) firewall_backend ;;
    4) status_wg ;;
    0) exit 0 ;;
    *) log_err "Opción inválida"; sleep 1 ;;
  esac
done
