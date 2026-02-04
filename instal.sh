#!/usr/bin/env bash
set -e

# ==============================
# VARIABLES GLOBALES
# ==============================
WG_IF="wg0"
WG_PORT=51820
WG_NET="10.50.0.0/24"
WG_SERVER_IP="10.50.0.1/24"
WG_CLIENT_IP="10.50.0.2/24"

# ==============================
# VALIDAR ROOT
# ==============================
if [ "$EUID" -ne 0 ]; then
  echo "[ERROR] Ejecuta como root"
  exit 1
fi

# ==============================
# LOGS
# ==============================
log_info() { echo -e "\e[34m[INFO]\e[0m $1"; }
log_ok()   { echo -e "\e[32m[OK]\e[0m $1"; }
log_err()  { echo -e "\e[31m[ERROR]\e[0m $1"; }

# ==============================
# DEPENDENCIAS
# ==============================
install_deps() {
  apt update -y
  apt install -y wireguard iptables-persistent
}

# ==============================
# INSTALAR WG SERVER
# ==============================
install_wg_server() {
  clear
  log_info "Instalando WireGuard SERVER"

  install_deps

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
  grep -q ip_forward /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

  systemctl enable wg-quick@${WG_IF}
  systemctl restart wg-quick@${WG_IF}

  log_ok "SERVER listo"
  echo "Clave pública del SERVER:"
  cat /etc/wireguard/server.pub
  read -p "Enter para continuar..."
}

# ==============================
# INSTALAR WG CLIENT
# ==============================
install_wg_client() {
  clear
  log_info "Instalando WireGuard CLIENT"

  read -p "IP pública del SERVER: " SERVER_IP
  read -p "Clave pública del SERVER: " SERVER_PUB

  install_deps

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

  log_ok "CLIENT listo"
  echo "Clave pública del CLIENT:"
  cat /etc/wireguard/client.pub
  read -p "Enter para continuar..."
}

# ==============================
# FIREWALL BACKEND
# ==============================
apply_firewall_backend() {
  clear
  log_info "Aplicando firewall seguro (backend)"

  iptables -P INPUT DROP
  iptables -P FORWARD DROP
  iptables -P OUTPUT ACCEPT

  iptables -A INPUT -i lo -j ACCEPT
  iptables -A INPUT -i ${WG_IF} -j ACCEPT

  iptables-save > /etc/iptables/rules.v4

  log_ok "Firewall aplicado"
  read -p "Enter para continuar..."
}

# ==============================
# VER ESTADO
# ==============================
check_status() {
  clear
  wg show || log_err "WireGuard no activo"
  read -p "Enter para continuar..."
}

# ==============================
# MENÚ
# ==============================
while true; do
  clear
  echo "======================================="
  echo "   GESTIÓN TÚNEL WIREGUARD (SERVER↔SERVER)"
  echo "======================================="
  echo ""
  echo " [1] Instalar WireGuard SERVER"
  echo " [2] Instalar WireGuard CLIENT"
  echo " [3] Aplicar Firewall (Backend)"
  echo " [4] Ver estado WireGuard"
  echo ""
  echo " [0] Salir"
  echo ""
  read -p "Opción: " opt

  case "$opt" in
    1) install_wg_server ;;
    2) install_wg_client ;;
    3) apply_firewall_backend ;;
    4) check_status ;;
    0) exit 0 ;;
    *) log_err "Opción inválida"; sleep 1 ;;
  esac
done