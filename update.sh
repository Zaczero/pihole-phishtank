#!/usr/bin/env bash
# shellcheck disable=SC2181
set -e

# cwd to script directory
cd "$(dirname "$0")"

fetch_data() {
  for _ in $(seq 1 10); do
    # fetch the data
    data=$(curl -sL https://data.phishtank.com/data/online-valid.json)

    # check if curl was successful
    if [[ $? -ne 0 ]]; then
      echo "Curl failed. Retrying..."
      sleep 60
      continue
    fi

    # check if data is non-empty
    if [[ -z "$data" ]]; then
      echo "Received empty response. Retrying..."
      sleep 60
      continue
    fi

    # validate JSON
    if ! echo "$data" | jq empty; then
      echo "Received invalid JSON. Retrying..."
      sleep 60
      continue
    fi

    return 0
  done

  return 1
}

echo "Fetching latest data from phishtank..."
if ! fetch_data; then
  echo "Failed to fetch data after multiple attempts."
  exit 1
fi

echo "Extracting urls from json..."
urls=$(echo "$data" | jq -r '.[].url')

hosts=""
declare -A counts

echo "Generating hosts file..."
for url in $urls; do
    domain=${url#*//}
    domain=${domain%%/*}
    domain=${domain%%\#*}  # remove fragment identifiers
    domain=${domain%%\?*}  # remove query parameters
    domain=${domain%:*}  # remove port
    domain=${domain##*@}  # remove username

    # skip if domain is an ipv4 address
    if [[ $domain =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        continue
    fi

    # skip if domain is an ipv6 address
    if [[ $domain =~ ^([0-9a-fA-F]*:){1,7}[0-9a-fA-F]* ]]; then
        continue
    fi

    # skip if url is not simple
    # https?:\/\/[^\/]* - match protocol and domain
    # (\/([?#]([^h].*)?)?)? - match empty path, path with query, or path with fragment...
    # [^h] - ...but only if it doesn't start with h (to avoid matching http, some legitimate sites use this)
    if [[ ! $url =~ ^https?:\/\/[^\/]*(\/([?#]([^h].*)?)?)?$ ]]; then
        continue
    fi

    # skip if url contains 2 or more https?:\/\/
    if [[ $url =~ ^https?:\/\/.*https?:\/\/ ]]; then
        continue
    fi

    # skip if url contains www in path or query or fragment
    if [[ $url =~ ^https?:\/\/.*?\/.*[Ww]{3} ]]; then
        continue
    fi
    
    # add to hosts and increment count
    hosts+="$domain\n"
    counts[$domain]=$(( ${counts[$domain]} + 1 ))
done

hosts=$(echo -e "$hosts" | sort -u)

{
  echo "# Title: PhishTank Blocklist for Pi-hole"
  echo "#"
  echo "# Date: $(date -u)"
  echo "# Number of unique domains: ${#counts[@]}"
  echo "#"
  echo "# Maintainer: Kamil Monicz (Zaczero)"
  echo "# Project home page: https://github.com/Zaczero/pihole-phishtank"
  echo "$hosts"
} > hosts.txt
echo "Done, saved to hosts.txt"

echo "Top blocked domains:"
for domain in "${!counts[@]}"; do
    echo "${counts[$domain]} times - $domain"
done | sort -rn -k1 | head -20
