#!/bin/bash
# go2rtc answers ONVIF with fixed values (1920x1080, 30 fps, 8192 kbit/s), and
# Protect shows and keeps what it read at adoption. This writes ./go2rtc: the
# binary of the image in compose.yaml with the camera's values from .env
# (CAM_WIDTH, CAM_HEIGHT, CAM_FPS, CAM_KBPS) put in as zero-padded text of the
# same length (Go keeps string lengths, so nothing else in the binary moves).
# compose.yaml mounts it over the original. Runs on the UNAS, in the stack
# directory; run it again after changing the image version.
set -euo pipefail
cd "$(dirname "$0")"
env_value() { sed -n "s/^$1=\"\{0,1\}\([^\"]*\)\"\{0,1\}$/\1/p" .env | tail -1; }
w=$(printf %04d "$(env_value CAM_WIDTH)") h=$(printf %04d "$(env_value CAM_HEIGHT)")
f=$(printf %02d "$(env_value CAM_FPS)") k=$(printf %04d "$(env_value CAM_KBPS)")
[[ ${#w} == 4 && ${#h} == 4 && ${#f} == 2 && ${#k} == 4 ]] \
    || { echo 'CAM_WIDTH/HEIGHT/KBPS need at most 4 digits, CAM_FPS at most 2' >&2; exit 1; }
img=$(sed -n 's/^ *image: *//p' compose.yaml | head -1)
docker image inspect "$img" >/dev/null 2>&1 || docker pull -q "$img" >/dev/null 2>&1
cid=$(docker create "$img" 2>/dev/null); trap 'docker rm "$cid" >/dev/null' EXIT
docker cp "$cid:/usr/local/bin/go2rtc" go2rtc.new >/dev/null
W=$w H=$h F=$f K=$k perl -0777 -pi -e '
    my %r = ("<tt:Width>1920</tt:Width><tt:Height>1080</tt:Height>" => "<tt:Width>$ENV{W}</tt:Width><tt:Height>$ENV{H}</tt:Height>",
             q{width="1920" height="1080"}                         => qq{width="$ENV{W}" height="$ENV{H}"},
             "<tt:FrameRateLimit>30</tt:FrameRateLimit>"            => "<tt:FrameRateLimit>$ENV{F}</tt:FrameRateLimit>",
             "<tt:BitrateLimit>8192</tt:BitrateLimit>"              => "<tt:BitrateLimit>$ENV{K}</tt:BitrateLimit>");
    for my $k (keys %r) {
        die "different length: $k\n" if length $k != length $r{$k};
        die "not in this go2rtc build: $k\n" unless /\Q$k\E/;
        s/\Q$k\E/$r{$k}/g;
    }' go2rtc.new
[[ $(stat -c %s go2rtc.new) == $(docker run --rm --network none --entrypoint stat "$img" -c %s /usr/local/bin/go2rtc 2>/dev/null) ]] \
    || { echo 'patched binary differs in size' >&2; rm -f go2rtc.new; exit 1; }
chmod 755 go2rtc.new && mv go2rtc.new go2rtc
echo "ONVIF values ${w}x${h}, $f fps, $k kbit/s -> $(pwd)/go2rtc"
