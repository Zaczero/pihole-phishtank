#!/usr/bin/env bash
set -e

# cwd to script directory
cd "$(dirname "$0")"

echo "Fetching latest data from phishtank..."
data=$(curl -sL https://data.phishtank.com/data/online-valid.json)

echo "Extracting urls from json..."
urls=$(echo "$data" | jq -r '.[].url')

hosts=""
declare -A counts

echo "Generating hosts file..."
for url in $urls; do
    domain=${url#*//}
    domain=${domain%%/*}
    domain=${domain##*@}  # remove username
    domain=${domain%%\?*}  # remove query parameters
    domain=${domain%%\#*}  # remove fragment identifiers
    domain=${domain%:*}  # remove port

    # skip if domain is an ipv4 address
    if [[ $domain =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        continue
    fi

    # skip if domain is an ipv6 address
    if [[ $domain =~ ^([0-9a-fA-F]*:){1,7}[0-9a-fA-F]* ]]; then
        continue
    fi

    # skip if url is not specific enough
    # https?:\/\/[^\/]* - match protocol and domain
    # (\/([?#]([^h].*)?)?)? - match empty path, path with query, or path with fragment...
    # [^h] - ...but only if it doesn't start with h (to avoid matching http, some legitimate sites use this)
    if [[ ! $url =~ ^https?:\/\/[^\/]*(\/([?#]([^h].*)?)?)?$ ]]; then
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
