#!/bin/bash
# An MJPEG camera as a camera in UniFi Protect (run on the Mac, after
# install-on-unas.sh): a go2rtc stack on its own LAN address that encodes the
# camera's MJPEG to H.264 and offers it to Protect over ONVIF/RTSP.
#
#   extras/unas-apps/mjpeg-camera/install-mjpeg-camera.sh root@<UNAS-IP> --ip <IP> \
#       --url http://<camera>/mjpg/video.mjpg [--name mjpeg-camera] [--stream camera] \
#       [--mac 02:42:c0:a8:01:08] [--size 1280x720] [--keep-every 4] [--fps 5] \
#       [--kbps 1200] [--crf 26] [--new-credentials] [--up]
#
#   --ip            the camera's own LAN address (macvlan), outside the DHCP range
#   --url           the camera's MJPEG stream (multipart/x-mixed-replace)
#   --name          stack and container name (<pool>/.unas-apps/data/stacks/<name>)
#   --stream        stream name = ONVIF profile Protect stores at adoption
#   --size          the camera's resolution, as reported to Protect
#   --keep-every N  keep every Nth frame, drop the others before decoding;
#                   pick N = camera fps / --fps (a 19 fps camera, 5 fps out: 4)
#   --fps           frame rate of the H.264 stream
#   --kbps, --crf   bit rate cap (kbit/s) and quality (lower = better, bigger)
#   --new-credentials  ask for the camera login again (otherwise kept from .env)
#   --up            start the container
#
# The camera login is asked for in the terminal (Basic auth) and written to the
# stack's .env together with a random RTSP password for Protect; .env is
# readable by root only. Adopting the camera in Protect: see ../README.md.
set -Eeuo pipefail
usage="usage: $0 root@<UNAS-IP> --ip <IP> --url <MJPEG-URL> [--name N] [--stream S] [--mac M] [--size WxH] [--keep-every N] [--fps F] [--kbps K] [--crf C] [--new-credentials] [--up]"
target=${1:?$usage}
shift
ip='' url='' name='mjpeg-camera' stream='camera' mac='02:42:c0:a8:01:08' size='1280x720'
keep=4 fps=5 kbps=1200 crf=26 newcred=false up=false
while (( $# )); do
    case "$1" in
        --ip) ip=${2:?$usage}; shift ;;
        --url) url=${2:?$usage}; shift ;;
        --name) name=${2:?$usage}; shift ;;
        --stream) stream=${2:?$usage}; shift ;;
        --mac) mac=${2:?$usage}; shift ;;
        --size) size=${2:?$usage}; shift ;;
        --keep-every) keep=${2:?$usage}; shift ;;
        --fps) fps=${2:?$usage}; shift ;;
        --kbps) kbps=${2:?$usage}; shift ;;
        --crf) crf=${2:?$usage}; shift ;;
        --new-credentials) newcred=true ;;
        --up) up=true ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
[[ -n "$ip" && "$url" =~ ^https?://[^[:space:]\"\'#]+$ ]] || { echo "$usage" >&2; exit 2; }
[[ "$mac" =~ ^02(:[0-9a-f]{2}){5}$ ]] || { echo "--mac must be a locally administered MAC (02:xx:...), lower case" >&2; exit 2; }
[[ "$name" =~ ^[a-z0-9][a-z0-9_-]*$ && "$stream" =~ ^[a-z0-9_]+$ ]] || { echo "--name/--stream: lower-case letters, digits, - and _" >&2; exit 2; }
[[ "$size" =~ ^([0-9]{1,4})x([0-9]{1,4})$ ]] || { echo "--size like 1280x720" >&2; exit 2; }
width=${BASH_REMATCH[1]} height=${BASH_REMATCH[2]}
[[ "$keep" =~ ^[1-9][0-9]?$ && "$fps" =~ ^[1-9][0-9]?$ && "$kbps" =~ ^[1-9][0-9]{0,3}$ && "$crf" =~ ^[0-9]{1,2}$ ]] \
    || { echo "--keep-every/--fps: 1-99, --kbps: 1-9999, --crf: 0-51" >&2; exit 2; }
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
remote() { ssh -o BatchMode=yes ${UNAS_SSH_CONFIG:+-F "$UNAS_SSH_CONFIG"} "$target" "$@"; }
tz=$(readlink /etc/localtime 2>/dev/null | sed -n 's|.*zoneinfo/||p'); tz=${tz:-Europe/Berlin}

volume=$(remote 'for v in /volume/*-*-*-*-*; do mountpoint -q "$v" && echo "$v" && break; done')
[[ -n "$volume" ]] || { echo 'no mounted storage pool on the UNAS' >&2; exit 1; }
stack="$volume/.unas-apps/data/stacks/$name"
remote "test -x /usr/local/sbin/unas-docker-start && docker info >/dev/null 2>&1" \
    || { echo 'Docker is not set up on the UNAS; run install-on-unas.sh first' >&2; exit 1; }

# the camera login: asked for here, sent over SSH stdin, never on a command line
auth=''
if [[ "$newcred" == true ]] || ! remote "grep -q '^CAM_AUTH=.' '$stack/.env' 2>/dev/null"; then
    read -r -p 'Camera user: ' cam_user < /dev/tty
    read -r -s -p 'Camera password: ' cam_pass < /dev/tty; echo
    [[ -n "$cam_user" ]] || { echo 'no camera user' >&2; exit 1; }
    auth=$(printf '%s:%s' "$cam_user" "$cam_pass" | base64 | tr -d '\n')
    unset cam_pass
fi

remote "mkdir -p '$stack'"
for f in compose.yaml go2rtc.yaml patch-onvif-values.sh; do
    remote "cat > '$stack/$f'" < "$here/$f"
done

# first line of stdin: the new camera login (empty = keep), then the script
{ printf '%s\n' "$auth"; cat <<'EOF'
set -euo pipefail
cd "$S"; chmod 755 patch-onvif-values.sh
old() { sed -n "s/^$1=\"\{0,1\}\([^\"]*\)\"\{0,1\}$/\1/p" .env 2>/dev/null | tail -1; }
[ -n "$AUTH" ] || AUTH=$(old CAM_AUTH)
ruser=$(old RTSP_USER); ruser=${ruser:-protect}
rpass=$(old RTSP_PASS); [ -n "$rpass" ] || rpass=$(head -c 48 /dev/urandom | base64 | tr -dc A-Za-z0-9 | head -c 20)
umask 077
cat > .env.new <<ENV
# written by install-mjpeg-camera.sh; root only (camera login, RTSP password)
CAM_CONTAINER=$NAME
CAM_IP=$IP
CAM_MAC=$MAC
CAM_URL="$URL"
CAM_STREAM=$STREAM
CAM_AUTH=$AUTH
CAM_WIDTH=$W
CAM_HEIGHT=$H
CAM_KEEP_EVERY=$KEEP
CAM_FPS=$FPS
CAM_KBPS=$KBPS
CAM_BUFSIZE=$((KBPS * 2))
CAM_CRF=$CRF
# entered in Protect when adopting the camera
RTSP_USER=$ruser
RTSP_PASS=$rpass
TZ=$TZ
ENV
mv .env.new .env
./patch-onvif-values.sh
EOF
} | remote "S='$stack' NAME='$name' IP='$ip' MAC='$mac' URL='$url' STREAM='$stream' W='$width' H='$height' KEEP='$keep' FPS='$fps' KBPS='$kbps' CRF='$crf' TZ='$tz' bash -c 'read -r AUTH; export AUTH; exec bash -s'"

if [[ "$up" == true ]]; then
    remote "cd '$stack' && docker compose up -d" 2>&1 | grep -v -i 'forwarding' | tail -1
fi
cat <<EOF
Camera stack: $stack (RTSP rtsp://$ip:8554/$stream, ONVIF http://$ip:1984/onvif/device_service)
Adopt in Protect: Devices -> (?) next to the search -> "Try advanced adoption":
  IP $ip, user and password from the stack's .env, e.g. to the clipboard:
  ssh $target 'sed -n "s/^RTSP_PASS=//p" "$stack/.env"' | tr -d '\n' | pbcopy
EOF
