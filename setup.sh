#!/usr/bin/env bash
# =============================================================================
#  frigate-tv-installer — instalador do sistema "Câmeras na TV"
#  (Frigate overlay/PIP + Home Assistant + Alexa)
#
#  Uso:
#     ./setup.sh                # menu interativo
#     ./setup.sh scan           # descobre HA / Frigate / Android TV na rede
#     ./setup.sh doctor         # checa dependências e conectividade
#     ./setup.sh apps           # instala os APKs na TV (adb) + permissão overlay
#     ./setup.sh ha             # envia o package do HA e reinicia
#     ./setup.sh all            # apps + ha
#
#  Config: lê ./config.env se existir; senão pergunta e oferece salvar.
#  Repos: https://github.com/duarte-gui
# =============================================================================
set -euo pipefail

# ----- aparência -------------------------------------------------------------
if [ -t 1 ]; then
  B="\033[1m"; G="\033[32m"; Y="\033[33m"; R="\033[31m"; C="\033[36m"; N="\033[0m"
else B=""; G=""; Y=""; R=""; C=""; N=""; fi
log()  { printf "${C}»${N} %s\n" "$*"; }
ok()   { printf "${G}✓${N} %s\n" "$*"; }
warn() { printf "${Y}!${N} %s\n" "$*"; }
err()  { printf "${R}✗${N} %s\n" "$*" >&2; }
die()  { err "$*"; exit 1; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${HERE}/config.env"

# repos / artefatos
GH_USER="duarte-gui"
APK_TV_REPO="${GH_USER}/Frigate-on-Firestick"      # com.frigate.tv  (Fire TV: PIP + tela cheia)
APK_OVERLAY_REPO="${GH_USER}/FrigateTV4Xiaomi"     # com.frigate.tvx (overlay)
PKG_HA_REPO="${GH_USER}/frigate-pip-homeassistant" # package + blueprints

# ----- helpers ---------------------------------------------------------------
need() { command -v "$1" >/dev/null 2>&1; }
load_config() { [ -f "$CONFIG" ] && { set -a; . "$CONFIG"; set +a; ok "Config carregada de $CONFIG"; }; }
ask() { # ask VAR "Pergunta" "default"
  local __v="$1" __q="$2" __d="${3:-}" __a
  printf "%b %s%b" "${B}?${N}" "$__q" "${N}"
  [ -n "$__d" ] && printf " [%s]" "$__d"
  printf ": "
  read -r __a || true
  printf -v "$__v" '%s' "${__a:-$__d}"
}

# detecta o prefixo da subrede local (ex.: 192.168.1.)
detect_subnet() {
  local ip
  ip="$(ip -4 route get 1.1.1.1 2>/dev/null | grep -oE 'src [0-9.]+' | awk '{print $2}')"
  [ -z "$ip" ] && ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  [ -z "$ip" ] && return 1
  echo "${ip%.*}."
}

# checa porta TCP aberta (nc se houver, senão /dev/tcp), timeout 1s
port_open() { # host porta
  local h="$1" p="$2"
  if need nc; then nc -z -w1 "$h" "$p" >/dev/null 2>&1
  else timeout 1 bash -c "exec 3<>/dev/tcp/$h/$p" >/dev/null 2>&1; fi
}

# confirma serviço por HTTP
is_frigate() { curl -fsS -m2 "http://$1:5000/api/version" >/dev/null 2>&1; }
is_ha()      { curl -fsS -m2 "http://$1:8123/auth/providers" >/dev/null 2>&1; }

# ----- comandos --------------------------------------------------------------
cmd_doctor() {
  log "Checando dependências…"
  for t in curl adb; do need "$t" && ok "$t" || warn "$t ausente (necessário)"; done
  for t in nmap nc gh sam; do need "$t" && ok "$t (opcional)" || warn "$t ausente (opcional)"; done
  load_config
  [ -n "${HA_BASE_URL:-}" ] && {
    if curl -fsS -m3 -H "Authorization: Bearer ${HA_TOKEN:-}" "${HA_BASE_URL}/api/" >/dev/null 2>&1
    then ok "HA acessível em ${HA_BASE_URL}"; else warn "HA não respondeu em ${HA_BASE_URL} (token/URL?)"; fi
  }
  [ -n "${FRIGATE_URL:-}" ] && { curl -fsS -m3 "${FRIGATE_URL}/api/version" >/dev/null 2>&1 && ok "Frigate ok (${FRIGATE_URL})" || warn "Frigate não respondeu"; }
  [ -n "${ANDROIDTV_IP:-}" ] && { adb connect "${ANDROIDTV_IP}:5555" >/dev/null 2>&1 && ok "Android TV conectada (${ANDROIDTV_IP})" || warn "adb não conectou na TV"; }
}

cmd_scan() {
  local base; base="$(detect_subnet)" || die "Não consegui detectar a subrede. Informe os IPs manualmente."
  log "Varrendo ${base}0/24 (HA:8123, Frigate:5000, Android TV:5555)…"
  local found_ha="" found_frigate="" found_tv=""
  if need nmap; then
    local hosts
    hosts="$(nmap -n -p 5000,8123,5555 --open -oG - "${base}0/24" 2>/dev/null | awk '/Ports:/{print $2}')"
    for h in $hosts; do
      is_ha "$h"      && { ok "Home Assistant: $h"; found_ha="$h"; }
      is_frigate "$h" && { ok "Frigate: $h";        found_frigate="$h"; }
      port_open "$h" 5555 && { ok "Android TV (adb): $h"; found_tv="$h"; }
    done
  else
    warn "nmap ausente — varredura mais lenta (bash)…"
    local pids=() h
    for i in $(seq 1 254); do
      h="${base}${i}"
      { is_ha "$h" && echo "HA $h"; is_frigate "$h" && echo "FRIGATE $h"; port_open "$h" 5555 && echo "TV $h"; } &
      pids+=($!)
      (( ${#pids[@]} % 40 == 0 )) && wait
    done >/tmp/.scan_out 2>/dev/null
    wait
    found_ha="$(awk '/^HA/{print $2; exit}' /tmp/.scan_out)"
    found_frigate="$(awk '/^FRIGATE/{print $2; exit}' /tmp/.scan_out)"
    found_tv="$(awk '/^TV/{print $2; exit}' /tmp/.scan_out)"
    rm -f /tmp/.scan_out
  fi
  echo
  log "Resultado do scan:"
  printf "   HA=%s  Frigate=%s  AndroidTV=%s\n" "${found_ha:-?}" "${found_frigate:-?}" "${found_tv:-?}"
  # exporta p/ a config interativa
  SCAN_HA="$found_ha"; SCAN_FRIGATE="$found_frigate"; SCAN_TV="$found_tv"
}

cmd_configure() {
  load_config || true
  log "Configuração (Enter aceita o padrão). Um scan pode pré-preencher os IPs."
  ask DO_SCAN "Rodar scan da rede agora? (s/N)" "${DO_SCAN:-N}"
  [ "${DO_SCAN,,}" = "s" ] && cmd_scan
  ask HA_HOST     "IP/host do Home Assistant" "${SCAN_HA:-${HA_HOST:-192.168.1.90}}"
  ask HA_PORT     "Porta do HA"               "${HA_PORT:-8123}"
  ask HA_TOKEN    "Token de longa duração do HA (Perfil→Segurança)" "${HA_TOKEN:-}"
  ask FRIGATE_HOST "IP/host do Frigate"        "${SCAN_FRIGATE:-${FRIGATE_HOST:-192.168.1.110}}"
  ask FRIGATE_PORT "Porta do Frigate"          "${FRIGATE_PORT:-5000}"
  ask ANDROIDTV_IP "IP da Android TV (adb)"    "${SCAN_TV:-${ANDROIDTV_IP:-192.168.1.190}}"
  echo "   Tipo de dispositivo de TV:"
  echo "     1) Fire TV Stick  — usa PIP nativo (app com.frigate.tv)"
  echo "     2) Xiaomi / Android TV sem PIP — usa overlay (app com.frigate.tvx)"
  echo "     3) Outro compatível — você escolhe a técnica"
  ask DEVICE_TYPE "Opção 1/2/3" "${DEVICE_TYPE:-2}"
  case "$DEVICE_TYPE" in
    1) APP_MODE=pip;     APP_PKG=com.frigate.tv;  APP_REPO="$APK_TV_REPO";;
    3) ask APP_MODE "Técnica para 'outro' (pip/overlay)" "${APP_MODE:-overlay}"
       if [ "${APP_MODE}" = "pip" ]; then APP_PKG=com.frigate.tv; APP_REPO="$APK_TV_REPO"
       else APP_MODE=overlay; APP_PKG=com.frigate.tvx; APP_REPO="$APK_OVERLAY_REPO"; fi;;
    *) DEVICE_TYPE=2; APP_MODE=overlay; APP_PKG=com.frigate.tvx; APP_REPO="$APK_OVERLAY_REPO";;
  esac
  OVERLAY_PKG="$APP_PKG"
  ok "Dispositivo: $( [ "$APP_MODE" = pip ] && echo 'Fire TV (PIP)' || echo 'Android TV (overlay)' ) → app ${APP_PKG}"
  ask HA_COPY_METHOD "Como enviar o package do HA? (smb/ssh/manual)" "${HA_COPY_METHOD:-manual}"
  case "${HA_COPY_METHOD}" in
    smb) ask HA_SMB_USER "Usuário Samba do HA" "${HA_SMB_USER:-homeassistant}"
         ask HA_SMB_PASS "Senha Samba" "${HA_SMB_PASS:-}";;
    ssh) ask HA_SSH "user@host do HA (SSH addon)" "${HA_SSH:-}";;
  esac
  {
    echo "# Gerado por setup.sh — NÃO commitar (contém token/senha)"
    echo "HA_BASE_URL=http://${HA_HOST}:${HA_PORT}"
    echo "HA_TOKEN=${HA_TOKEN}"
    echo "FRIGATE_URL=http://${FRIGATE_HOST}:${FRIGATE_PORT}"
    echo "ANDROIDTV_IP=${ANDROIDTV_IP}"
    echo "DEVICE_TYPE=${DEVICE_TYPE}"
    echo "APP_MODE=${APP_MODE}"
    echo "APP_PKG=${APP_PKG}"
    echo "APP_REPO=${APP_REPO}"
    echo "OVERLAY_PKG=${OVERLAY_PKG}"
    echo "HA_COPY_METHOD=${HA_COPY_METHOD}"
    echo "HA_SMB_USER=${HA_SMB_USER:-}"
    echo "HA_SMB_PASS=${HA_SMB_PASS:-}"
    echo "HA_SSH=${HA_SSH:-}"
  } > "$CONFIG"
  chmod 600 "$CONFIG"
  ok "Salvo em $CONFIG (chmod 600)"
}

# baixa o APK mais recente de uma Release do GitHub
fetch_apk() { # repo destino
  local repo="$1" dest="$2"
  if need gh; then
    gh release download -R "$repo" --pattern '*.apk' -O "$dest" --clobber 2>/dev/null && return 0
  fi
  local url
  url="$(curl -fsS "https://api.github.com/repos/${repo}/releases/latest" | grep -oE 'https://[^"]+\.apk' | head -1)"
  [ -n "$url" ] || return 1
  curl -fL -o "$dest" "$url"
}

cmd_apps() {
  load_config
  need adb || die "adb não instalado."
  [ -n "${ANDROIDTV_IP:-}" ] || die "ANDROIDTV_IP não definido (rode: ./setup.sh configure)."
  log "Conectando na TV ${ANDROIDTV_IP}…"
  adb connect "${ANDROIDTV_IP}:5555" >/dev/null 2>&1 || true
  adb -s "${ANDROIDTV_IP}:5555" wait-for-device || die "Não conectou na TV (ative Depuração USB/rede)."
  local repo="${APP_REPO:-$APK_OVERLAY_REPO}" pkg="${APP_PKG:-com.frigate.tvx}" mode="${APP_MODE:-overlay}"
  log "Dispositivo: $( [ "$mode" = pip ] && echo 'Fire TV (PIP)' || echo 'Android TV (overlay)' ) → instalando ${pkg} de ${repo}"
  local tmp; tmp="$(mktemp -d)"
  if fetch_apk "$repo" "${tmp}/app.apk"; then
    adb -s "${ANDROIDTV_IP}:5555" install -r "${tmp}/app.apk" && ok "${pkg} instalado" || warn "Falha ao instalar ${pkg}"
  else
    warn "Sem Release com .apk em ${repo} (publique uma, ou buildde local)."
  fi
  rm -rf "$tmp"
  if [ "$mode" = "overlay" ]; then
    log "Concedendo permissão de overlay para ${pkg}…"
    adb -s "${ANDROIDTV_IP}:5555" shell appops set "${pkg}" SYSTEM_ALERT_WINDOW allow \
      && ok "Permissão de overlay concedida" || warn "Não consegui setar a permissão (faça manual nas Configurações)."
  else
    ok "Fire TV (PIP) não precisa de permissão de overlay."
  fi
}

cmd_ha() {
  load_config
  [ -n "${HA_BASE_URL:-}" ] && [ -n "${HA_TOKEN:-}" ] || die "HA_BASE_URL/HA_TOKEN ausentes (rode: ./setup.sh configure)."
  local pkg="${HERE}/homeassistant/packages/frigate_pip.yaml"
  [ -f "$pkg" ] || pkg="${HERE}/frigate_pip.yaml"
  [ -f "$pkg" ] || die "Não achei frigate_pip.yaml no repo."
  case "${HA_COPY_METHOD:-manual}" in
    smb)
      need smbclient || die "smbclient não instalado."
      log "Enviando package via Samba…"
      smbclient "//${HA_BASE_URL#http://}" 2>/dev/null || true
      local host="${HA_BASE_URL#http://}"; host="${host%%:*}"
      smbclient "//${host}/config" -U "${HA_SMB_USER}%${HA_SMB_PASS}" \
        -c "cd packages; put ${pkg} frigate_pip.yaml" && ok "Package enviado (Samba)" \
        || die "Falha no Samba (addon Samba ativo? credenciais?)."
      ;;
    ssh)
      [ -n "${HA_SSH:-}" ] || die "HA_SSH não definido."
      log "Enviando package via SSH…"
      scp "$pkg" "${HA_SSH}:/config/packages/frigate_pip.yaml" && ok "Package enviado (SSH)" || die "Falha no SCP."
      ;;
    *)
      warn "Método 'manual': copie você mesmo este arquivo para /config/packages/ do HA:"
      echo "    $pkg"
      warn "E garanta no configuration.yaml:  homeassistant:\\n      packages: !include_dir_named packages"
      ;;
  esac
  log "Verificando config e reiniciando o HA…"
  if curl -fsS -m45 -X POST -H "Authorization: Bearer ${HA_TOKEN}" "${HA_BASE_URL}/api/config/core/check_config" | grep -q '"result": *"valid"'; then
    curl -fsS -m20 -X POST -H "Authorization: Bearer ${HA_TOKEN}" "${HA_BASE_URL}/api/services/homeassistant/restart" >/dev/null 2>&1 || true
    ok "Reinício disparado. Aguarde ~30s e teste."
  else
    warn "check_config não retornou 'valid' — revise antes de reiniciar."
  fi
}

menu() {
  echo
  printf "${B}== frigate-tv-installer ==${N}\n"
  echo "  1) Scan da rede (descobrir HA/Frigate/TV)"
  echo "  2) Configurar (IPs, token… salva em config.env)"
  echo "  3) Instalar apps na TV (adb)"
  echo "  4) Instalar config no Home Assistant"
  echo "  5) Tudo (apps + HA)"
  echo "  6) Doctor (checar dependências/conexão)"
  echo "  0) Sair"
  ask OPT "Escolha" ""
  case "$OPT" in
    1) cmd_scan;; 2) cmd_configure;; 3) cmd_apps;; 4) cmd_ha;;
    5) cmd_apps; cmd_ha;; 6) cmd_doctor;; 0) exit 0;;
    *) warn "Opção inválida";;
  esac
}

case "${1:-menu}" in
  scan) cmd_scan;; configure|config) cmd_configure;; apps) cmd_apps;;
  ha) cmd_ha;; all) cmd_apps; cmd_ha;; doctor) cmd_doctor;;
  menu) while true; do menu; done;;
  *) die "Comando desconhecido: $1 (use: scan|configure|apps|ha|all|doctor)";;
esac
