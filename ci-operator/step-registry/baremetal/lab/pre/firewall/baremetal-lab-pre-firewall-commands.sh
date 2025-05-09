#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

[ -z "${AUX_HOST}" ] && { echo "AUX_HOST is not filled. Failing."; exit 1; }

SSHOPTS=(-o 'ConnectTimeout=5'
  -o 'StrictHostKeyChecking=no'
  -o 'UserKnownHostsFile=/dev/null'
  -o 'ServerAliveInterval=90'
  -o LogLevel=ERROR
  -i "${CLUSTER_PROFILE_DIR}/ssh-key")

if [ "$CLUSTER_WIDE_PROXY" == "true" ] || [ "$DISCONNECTED" == "true" ]; then
 proxy="$(<"${CLUSTER_PROFILE_DIR}/proxy")"
 cat <<EOF > "${SHARED_DIR}/proxy-conf.sh"
 export HTTP_PROXY=${proxy}
 export HTTPS_PROXY=${proxy}
 export NO_PROXY="localhost,127.0.0.1"

 export http_proxy=${proxy}
 export https_proxy=${proxy}
 export no_proxy="localhost,127.0.0.1"
EOF
fi

if [ "${CLUSTER_WIDE_PROXY}" == "true" ]; then
  # ipi-conf-proxy will run only if a specific file is found, see step code
  cp "${CLUSTER_PROFILE_DIR}/proxy_private_url" "${SHARED_DIR}/proxy_private_url"
fi

if [ x"${DISCONNECTED}" != x"true" ]; then
  echo 'Skipping firewall configuration because no disconnected installation is requested!'
  exit
fi

declare -a IP_ARRAY
for bmhost in $(yq e -o=j -I=0 '.[]' "${SHARED_DIR}/hosts.yaml"); do
  # shellcheck disable=SC1090
  . <(echo "$bmhost" | yq e 'to_entries | .[] | (.key + "=\"" + .value + "\"")')
  # shellcheck disable=SC2154
  if [ ${#ip} -eq 0 ]; then
    echo "Error while unmarshalling hosts entries"
    exit 1
  fi
  IP_ARRAY+=( "$ip" )
done

timeout -s 9 10m ssh "${SSHOPTS[@]}" "root@${AUX_HOST}" bash -s -- \
  "${INTERNAL_NET_CIDR}" "${IP_ARRAY[@]}" << 'EOF'
  set -o nounset
  set -o errexit
  INTERNAL_NET_CIDR="${1}"
  IP_ARRAY="${@:2}"
  for ip in $IP_ARRAY; do
    # TODO: change to firewalld or nftables
    # Allow connections on port 22 used by observer pod
    iptables -A FORWARD -s ${ip} ! -d "${INTERNAL_NET_CIDR}" ! -p tcp --dport 22 -j DROP
  done
EOF

# mirror-images-by-oc-adm will run only if a specific file is found, see step code
cp "${CLUSTER_PROFILE_DIR}/mirror_registry_url" "${SHARED_DIR}/mirror_registry_url"

