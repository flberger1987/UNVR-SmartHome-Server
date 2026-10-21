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
printf 'APPS_ROOT=%s/data\n' "$APPS" > "$APPS/dockge/.env"

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
for _ in $(seq 1 60); do docker info >/dev/null 2>&1 && break; sleep 2; done
docker info --format 'docker {{.ServerVersion}}, runtime {{.DefaultRuntime}}, storage {{.Driver}}'
EOF

if [[ "$images" == true ]]; then
    list=$(sed -n 's/^ *image: *\([^ #]*\).*/\1/p' "$here/docker-compose.yml" "$here/dockge/compose.yaml" | sort -u)
    echo "streaming images: $(echo $list)"
    docker save $list | remote 'docker load'
fi
if [[ "$up" == true ]]; then
    remote "cd '$dockge' && docker compose up -d && cd '$stack' && docker compose up -d && docker compose ps"
fi
