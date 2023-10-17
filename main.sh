#!/bin/bash
private_key=$(wg genkey)
public_key=$(echo "$private_key" | wg pubkey | sudo tee)

# Function to register an account and return the JSON response
register_account() {  
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local account_data='{
    "fcm_token": "",
    "install_id": "",
    "key": "'"$public_key"'",
    "locale": "en_US",
    "model": "warpGen",
    "tos": "'"$timestamp"'",
    "type": "Android"
  }'

  local response
  response=$(curl -X POST -H "User-Agent: okhttp/3.12.1" -H "Accept: application/json" -H "Cf-Client-Version: a-6.3-1922" -H "Content-Type: application/json" -d "$account_data" --tlsv1.3 "https://api.cloudflareclient.com/v0a1922/reg" )

  echo $response
}


#!/bin/bash

# Function to activate an account
activate() {
    # Register device
    device_name="warpGen"
    account_id="$1"
    token="$2"
    echo "Activating account $account_id"
    echo "Token: $token"

    # Register the device
    curl -X PATCH -H "Content-Type: application/json" -H "Authorization: Bearer $token" -d "{\"Name\":\"$device_name\"}" --tlsv1.3 "https://api.cloudflareclient.com/v0a1922/reg/$account_id/account/reg/$account_id"

    # Check for errors
    if [ $? -ne 0 ]; then
        echo "Failed to register the device"
        return
    fi

    # Get registered device details
    registered_device=$(curl -H "Authorization: Bearer $token" --tlsv1.3 "https://api.cloudflareclient.com/v0a1922/reg/$account_id")

    # Check for errors
    if [ $? -ne 0 ]; then
        echo "Failed to fetch registered device details"
        return
    fi

    # Activate the account
    curl -X PATCH -H "Content-Type: application/json" -H "Authorization: Bearer $token" -d '{"active":true}' --tlsv1.3 "https://api.cloudflareclient.com/v0a1922/reg/$account_id/account/reg/$account_id"

    # Check for errors
    if [ $? -ne 0 ]; then
        echo "Failed to activate the account"
        return
    fi
}

generate_wireguard_config() {
  local private_key="$1"
  local ipv4_address="$2"
  local ipv6_address="$3"
  local reserved="$4"
  local self_ip="$(ip -4 route get 1 | awk '{print $7}')"


  local config="[Interface]
PrivateKey = $private_key
Address = $ipv4_address/32
Address = $ipv6_address/128
PostUp = ip rule add from $self_ip table main
PostUp = iptables -I OUTPUT ! -o %i -m addrtype ! --dst-type LOCAL -m conntrack ! --ctstate ESTABLISHED,RELATED -j REJECT
PreDown = ip rule del from $self_ip table main
PreDown = iptables -D OUTPUT ! -o %i -m addrtype ! --dst-type LOCAL -m conntrack ! --ctstate ESTABLISHED,RELATED -j REJECT
DNS = 1.1.1.1
MTU = 1280
[Peer]
PublicKey = bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=
AllowedIPs = 0.0.0.0/0
AllowedIPs = ::/0
Endpoint = engage.cloudflareclient.com:2408
#Reserved = $reserved"
      echo "$config"
}

calculate_reserved() {
    local client_id="$1"
    echo "$client_id" | base64 -d | xxd -p | fold -w2 | while read HEX; do printf '%d ' "0x${HEX}"; done | awk '{print "[ "$1", "$2", "$3" ]"}'
}

# Main program
account_data=$(register_account)

echo $account_data

if [ -z "$account_data" ]; then
  echo "Failed to register"
  exit 1
fi

system=$(uname -s | tr '[:upper:]' '[:lower:]')
architecture=$(uname -m | tr '[:upper:]' '[:lower:]')
# map x86_64 to amd64, aarch64 to arm64, etc.
case "$architecture" in
  x86_64) architecture=amd64;;
  aarch64) architecture=arm64;;
esac

token=$(echo "$account_data" | jq -r '.token')
v4=$(echo "$account_data" | jq -r '.config.interface.addresses.v4')
v6=$(echo "$account_data" | jq -r '.config.interface.addresses.v6')
client_id=$(echo "$account_data" | jq -r '.config.client_id')
id=$(echo "$account_data" | jq -r '.id')
key=$(echo "$account_data" | jq -r '.key')
account_id=$(echo "$account_data" | jq -r '.account.id')
reserved=$(calculate_reserved "$client_id")
wireguard_config=$(generate_wireguard_config "$private_key" "$v4" "$v6" "$reserved")
wget https://raw.githubusercontent.com/nexstorm/warp-sh/main/wgo-quick/wgo-quick -O /usr/local/bin/wgo-quick
wget https://raw.githubusercontent.com/nexstorm/warp-sh/main/wireguard-go/wireguard-go-${system}-${architecture} -O /usr/local/bin/wireguard-go
chmod +x /usr/local/bin/wgo-quick
chmod +x /usr/local/bin/wireguard-go

activate "$id" "$token"
echo "$wireguard_config"
echo "$wireguard_config" > /etc/wireguard/wg0.conf
