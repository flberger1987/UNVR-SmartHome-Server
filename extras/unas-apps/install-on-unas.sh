#!/bin/bash
# Set up Docker and the app stack on a converted UNVR (run on the Mac).
#
#   extras/unas-apps/install-on-unas.sh root@<UNAS-IP> [--images] [--up]
#
# Needs SSH as root with a key (Control Plane -> Console -> SSH), the files from
# build-images.sh in cache/unas-apps/ and prebuilt/modules/.../extra/macvlan.ko.
#
# What it installs (everything large lives on the RAID pool, nothing in apt):
#   <pool>/.unas-apps/docker/      static Docker, crun, compose, data-root
#   <pool>/.unas-apps/data/stacks/unas-apps/  app stack (compose.yaml, .env), managed in Dockge
#   <pool>/.unas-apps/dockge/      Dockge's own stack (http://<UNAS-IP>:5001)
#   /usr/local/sbin/unas-docker-start, /etc/systemd/system/unas-docker.service
#   /usr/local/bin/docker          wrapper for the daemon's private socket
#
# Why it looks like this: the UNVR kernel has cgroup v2 without BPF, so runc
# (and crun with cgroups) cannot apply device rules; crun runs with
# --cgroup-manager=disabled (no per-container limits). There is no
# veth/bridge/netfilter: bridge none, no iptables, macvlan for own addresses.
#   --images   stream the arm64 images from the local Docker into the UNAS
#   --up       start the stack (docker compose up -d)
set -Eeuo pipefail
target=${1:?usage: $0 root@<UNAS-IP> [--images] [--up]}
shift
images=false up=false
for arg in "$@"; do
    case "$arg" in
        --images) images=true ;;
        --up) up=true ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/../.." && pwd)
cache="$root/cache/unas-apps"
macvlan="$root/prebuilt/modules/4.19.152-alpine-unvr/extra/macvlan.ko"
for f in "$cache/docker-28.5.2.tgz" "$cache/docker-compose" "$cache/crun" "$macvlan"; do
    [[ -f "$f" ]] || { echo "missing $f (run build-images.sh)" >&2; exit 1; }
done
# UNAS_SSH_CONFIG=<file> selects another ssh_config (e.g. a dedicated key)
remote() { ssh -o BatchMode=yes ${UNAS_SSH_CONFIG:+-F "$UNAS_SSH_CONFIG"} "$target" "$@"; }

volume=$(remote 'for v in /volume/*-*-*-*-*; do mountpoint -q "$v" && echo "$v" && break; done')
[[ -n "$volume" ]] || { echo 'no mounted storage pool on the UNAS; create one in UniFi Drive first' >&2; exit 1; }
apps="$volume/.unas-apps"
echo "storage pool: $volume"

stack="$apps/data/stacks/unas-apps"   # managed in Dockge
dockge="$apps/dockge"                  # Dockge's own stack, outside the stacks dir
remote "mkdir -p '$apps/docker/bin' '$apps/docker/data' '$apps/modules' '$apps/bundle' '$stack' '$dockge'"
remote "cat > '$apps/bundle/docker.tgz'" < "$cache/docker-28.5.2.tgz"
remote "cat > '$apps/docker/bin/docker-compose'" < "$cache/docker-compose"
remote "cat > '$apps/docker/bin/crun'" < "$cache/crun"
remote "cat > '$apps/modules/macvlan.ko'" < "$macvlan"
remote "cat > '$stack/compose.yaml'" < "$here/docker-compose.yml"
remote "cat > '$stack/init-mongo.sh'" < "$here/init-mongo.sh"
remote "cat > '$stack/env.example'" < "$here/env.example"
remote "cat > '$dockge/compose.yaml'" < "$here/dockge/compose.yaml"

remote "APPS='$apps' bash -s" <<'EOF'
set -euo pipefail
tar -xzf "$APPS/bundle/docker.tgz" -C "$APPS/docker/bin" --strip-components=1
STACK="$APPS/data/stacks/unas-apps"
chmod 755 "$APPS"/docker/bin/* "$STACK/init-mongo.sh"

cat > "$APPS/docker/daemon.json" <<JSON
{
  "data-root": "$APPS/docker/data",
  "exec-root": "/run/unas-docker",
  "pidfile": "/run/unas-docker.pid",
  "hosts": ["unix:///run/unas-docker.sock"],
  "storage-driver": "btrfs",
  "bridge": "none",
  "iptables": false,
  "ip6tables": false,
  "ip-forward": false,
  "userland-proxy": false,
  "exec-opts": ["native.cgroupdriver=cgroupfs"],
  "default-runtime": "crun",
  "runtimes": {"crun": {"path": "$APPS/docker/bin/crun", "runtimeArgs": ["--cgroup-manager=disabled"]}},
  "log-driver": "local",
  "log-opts": {"max-size": "10m", "max-file": "3"}
}
JSON

cat > /usr/local/sbin/unas-docker-start <<SH
#!/bin/bash
# Wait for the UniFi Drive pool, load macvlan, then run dockerd from the pool.
set -eu
for _ in \$(seq 1 120); do mountpoint -q '${APPS%/.unas-apps}' && break; sleep 5; done
mountpoint -q '${APPS%/.unas-apps}' || { echo 'storage pool not mounted' >&2; exit 1; }
grep -q '^macvlan ' /proc/modules || insmod '$APPS/modules/macvlan.ko'
# fixed-size app volumes (e.g. Protect): <dir>/srv.img loop-mounted on <dir>/srv
for img in '$APPS'/*/srv.img; do
    [ -f "\$img" ] || continue
    mnt="\$(dirname "\$img")/srv"
    mkdir -p "\$mnt"
    mountpoint -q "\$mnt" || mount -o loop,noatime "\$img" "\$mnt"
done
export PATH='$APPS/docker/bin':\$PATH
exec dockerd --config-file '$APPS/docker/daemon.json'
SH
chmod 755 /usr/local/sbin/unas-docker-start

cat > /etc/systemd/system/unas-docker.service <<UNIT
[Unit]
Description=Docker for UNAS apps (storage pool, crun, macvlan)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/sbin/unas-docker-start
Restart=on-failure
RestartSec=30
TimeoutStartSec=0
Delegate=yes
KillMode=process
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
UNIT

# Containers that join another container's network (network_mode: service:x)
# are orphaned when x restarts on its own (e.g. Docker's restart policy after a
# crash); compose only handles restarts it performs itself. A quiet loop checks
# every minute (a timer would log three lines per minute; logs cost SD writes).
cat > /usr/local/sbin/unas-netns-guard <<'SH'
#!/bin/bash
# Restart containers whose shared network namespace no longer matches its owner.
export PATH=/usr/local/bin:$PATH
check() {
    docker ps --format '{{.Names}}' | while read -r name; do
        mode=$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$name" 2>/dev/null)
        [[ "$mode" == container:* ]] || continue
        owner=${mode#container:}
        pid=$(docker inspect -f '{{.State.Pid}}' "$name")
        opid=$(docker inspect -f '{{if .State.Running}}{{.State.Pid}}{{end}}' "$owner" 2>/dev/null)
        [[ -n "$opid" && "$pid" != 0 ]] || continue
        if [[ "$(readlink /proc/$pid/ns/net)" != "$(readlink /proc/$opid/ns/net)" ]]; then
            logger -t unas-netns-guard "restarting $name: network namespace of $(docker inspect -f '{{.Name}}' "$owner") changed"
            docker restart -t 60 "$name" >/dev/null
        fi
    done
}
sleep 180
while :; do check; sleep 60; done
SH
chmod 755 /usr/local/sbin/unas-netns-guard
systemctl disable --now unas-netns-guard.timer >/dev/null 2>&1 || true
rm -f /etc/systemd/system/unas-netns-guard.timer
cat > /etc/systemd/system/unas-netns-guard.service <<UNIT
[Unit]
Description=Re-join containers whose shared network namespace owner restarted
After=unas-docker.service
BindsTo=unas-docker.service

[Service]
ExecStart=/usr/local/sbin/unas-netns-guard
Restart=always
RestartSec=60

[Install]
WantedBy=unas-docker.service
UNIT

cat > /usr/local/bin/docker <<SH
#!/bin/sh
exec '$APPS/docker/bin/docker' -H unix:///run/unas-docker.sock "\$@"
SH
chmod 755 /usr/local/bin/docker
mkdir -p /root/.docker/cli-plugins
ln -sf "$APPS/docker/bin/docker-compose" /root/.docker/cli-plugins/docker-compose

if [ ! -f "$STACK/.env" ]; then
    rand() { head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24; }
    sed -e "s#^APPS_ROOT=.*#APPS_ROOT=$APPS/data#" \
        -e "s#^MONGO_ROOT_PASS=.*#MONGO_ROOT_PASS=$(rand)#" \
        -e "s#^MONGO_PASS=.*#MONGO_PASS=$(rand)#" \
        "$STACK/env.example" > "$STACK/.env"
    chmod 600 "$STACK/.env"
    echo "created $STACK/.env (edit the LAN values before --up)"
fi
envget() { sed -n "s/^$1=//p" "$STACK/.env" | tr -d '"'"'"''; }
grep -q '^DOCKGE_IP=' "$STACK/.env" || grep -E '^DOCKGE_(IP|MAC)=' "$STACK/env.example" >> "$STACK/.env"
printf 'APPS_ROOT=%s/data\nDOCKGE_IP=%s\nDOCKGE_MAC=%s\n' "$APPS" "$(envget DOCKGE_IP)" "$(envget DOCKGE_MAC)" > "$APPS/dockge/.env"

# Docker's embedded DNS needs iptables; give the containers the LAN DNS directly.
dns=$(sed -n 's/^LAN_DNS=//p' "$STACK/.env" | tr -d '"'"'"'')
[ -n "$dns" ] || { echo "LAN_DNS missing in $STACK/.env" >&2; exit 1; }
for ns in $dns; do echo "nameserver $ns"; done > "$STACK/resolv.conf"
echo "options ndots:0" >> "$STACK/resolv.conf"

# replace a manually started test daemon, if any
if [ -f /run/unas-docker.pid ] && ! systemctl is-active --quiet unas-docker; then
    kill "$(cat /run/unas-docker.pid)" 2>/dev/null || true
    sleep 4
fi
systemctl daemon-reload
systemctl enable --now unas-docker >/dev/null 2>&1
systemctl enable unas-netns-guard.service >/dev/null 2>&1
systemctl restart unas-netns-guard.service
for _ in $(seq 1 60); do docker info >/dev/null 2>&1 && break; sleep 2; done
docker info --format 'docker {{.ServerVersion}}, runtime {{.DefaultRuntime}}, storage {{.Driver}}'
EOF

if [[ "$images" == true ]]; then
    list=$(sed -n 's/^ *image: *\([^ #]*\).*/\1/p' "$here/docker-compose.yml" "$here/dockge/compose.yaml" | sort -u)
    # a :live image on the UNAS holds installed state; never replace it with a fresh build
    keep=$(remote 'docker image ls --format "{{.Repository}}:{{.Tag}}"' | grep ':live$' || true)
    list=$(for i in $list; do grep -qxF "$i" <<<"$keep" && echo "keeping $i on the UNAS" >&2 || echo "$i"; done)
    if [[ -n "$list" ]]; then
        echo "streaming images: $(echo $list)"
        docker save $list | remote 'docker load'
    fi
fi
if [[ "$up" == true ]]; then
    # (Re)create the shared macvlan network from LAN_* in .env, then start both stacks.
    remote "STACK='$stack' DOCKGE='$dockge' bash -s" <<'EOF'
set -euo pipefail
envget() { sed -n "s/^$1=//p" "$STACK/.env" | tr -d '"'"'"''; }
PROTECT="${STACK%/unas-apps}/protect"   # optional, from protect/install-protect.sh
UCKP="${STACK%/unas-apps}/uckp"         # optional, from uckp/install-uckp.sh
# UniFi OS and LoxBerry keep installed apps/packages in the container layer:
# commit it to the :live image the stack runs before the container is removed
for c in unifi-os unifi-protect loxberry; do
    img=$(docker container inspect -f '{{.Config.Image}}' "$c" 2>/dev/null) || continue
    case "$img" in *:live) docker commit --pause=false "$c" "$img" >/dev/null && echo "kept state of $c in $img" ;; esac
done
for s in "$PROTECT" "$UCKP"; do
    [ -f "$s/.env" ] && { (cd "$s" && docker compose down) 2>&1 | grep -v -i 'forwarding' || true; }
done
(cd "$DOCKGE" && docker compose down) 2>&1 | grep -v -i 'forwarding' || true
(cd "$STACK" && docker compose down) 2>&1 | grep -v -i 'forwarding' || true
docker network rm unas-lan unas-apps_lan >/dev/null 2>&1 || true   # unas-apps_lan: older layout
docker network create -d macvlan --subnet "$(envget LAN_SUBNET)" --gateway "$(envget LAN_GATEWAY)" \
    -o parent="$(envget LAN_PARENT)" unas-lan >/dev/null
(cd "$DOCKGE" && docker compose up -d) 2>&1 | grep -v -i 'forwarding' | tail -1
(cd "$STACK" && docker compose up -d) 2>&1 | grep -v -i 'forwarding' | tail -1
for s in "$PROTECT" "$UCKP"; do
    [ -f "$s/.env" ] && { (cd "$s" && docker compose up -d) 2>&1 | grep -v -i 'forwarding' | tail -1; }
done
docker ps --format '{{.Names}}' | while read -r c; do
    printf '%-27s %s\n' "$c" "$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$c")"
done
EOF
fi
