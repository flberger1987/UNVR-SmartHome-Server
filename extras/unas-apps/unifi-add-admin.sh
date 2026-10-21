#!/bin/bash
# Create (or reset) a local super admin in the UniFi Network Application on the
# UNAS (run on the Mac, in a terminal).
#
#   extras/unas-apps/unifi-add-admin.sh root@<UNAS-IP>
#
# Needed after restoring a backup from a UniFi OS console (UDM, Cloud Key Gen2+,
# UniFi OS Server): there the admins live in UniFi OS, not in the Network
# database, and the standalone server has no UI account sign-in, so after the
# restore nobody can log in. The password is read without echo, hashed on the
# UNAS (SHA-512 crypt) and only the hash is stored.
set -Eeuo pipefail
target=${1:?usage: $0 root@<UNAS-IP>}
remote() { ssh -o BatchMode=yes ${UNAS_SSH_CONFIG:+-F "$UNAS_SSH_CONFIG"} "$target" "$@"; }

read -r -p 'Username: ' name
read -r -p 'E-mail (optional): ' email
[[ "$name" =~ ^[A-Za-z0-9._@+-]{1,64}$ ]] || { echo 'username: letters, digits and ._@+- only' >&2; exit 2; }
[[ -z "$email" || "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+$ ]] || { echo 'invalid e-mail' >&2; exit 2; }
read -r -s -p 'Password: ' pw; echo
read -r -s -p 'Repeat password: ' pw2; echo
[[ "$pw" == "$pw2" ]] || { echo 'passwords differ' >&2; exit 2; }
(( ${#pw} >= 8 )) || { echo 'password too short (min. 8)' >&2; exit 2; }
hash=$(printf '%s\n' "$pw" | remote 'openssl passwd -6 -stdin')
unset pw pw2
[[ "$hash" =~ ^\$6\$[./A-Za-z0-9]+\$[./A-Za-z0-9]+$ ]] || { echo 'hashing on the UNAS failed' >&2; exit 1; }

remote "NAME='$name' EMAIL='$email' HASH='$hash' bash -s" <<'EOF'
set -euo pipefail
docker exec -i unifi-db sh -c 'mongo --quiet -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin unifi' <<JS
(function () {
    var name = "$NAME", email = "$EMAIL", hash = "$HASH";
    var a = db.admin.findOne({name: name}), id;
    if (a) {
        id = a._id;
        db.admin.updateOne({_id: id}, {\$set: {x_shadow: hash, email: email, requires_new_password: false}});
    } else {
        id = ObjectId();
        db.admin.insertOne({_id: id, name: name, email: email, x_shadow: hash,
            time_created: NumberLong(Math.floor(Date.now() / 1000)),
            last_site_name: "default", requires_new_password: false});
    }
    // admin on every site, including the hidden "super" site (= super admin)
    db.site.find().forEach(function (s) {
        db.privilege.updateOne({admin_id: id.str, site_id: s._id.str},
            {\$set: {admin_id: id.str, site_id: s._id.str, role: "admin", permissions: []}},
            {upsert: true});
    });
    print((a ? "updated " : "created ") + name + ", admin on " + db.privilege.count({admin_id: id.str}) + " sites");
})();
JS
EOF
echo "Sign in at https://<UNIFI_IP>:8443 with this username."
