#!/usr/bin/env bash
# shellcheck enable=all shell=bash
# rcon.sh: Pure Bash Minecraft RCON client
# Usage: rcon.sh <host> <port> <password> <command>
export LC_ALL=C

# Given a 4-byte hex string, reverse byte order (little→big endian)
reverse_hex_endian() {
  local INTEGER
  while read -r -d '' -N 8 INTEGER; do
    if [[ "${#INTEGER}" -eq 8 ]]; then
      printf '%s' "${INTEGER:6:2}${INTEGER:4:2}${INTEGER:2:2}${INTEGER:0:2}"
    else
      printf '%s' "$INTEGER"
    fi
  done
}

# Decode a little-endian 4-byte hex integer to decimal
decode_hex_int() {
  local INTEGER big_endian
  while read -r -d '' -N 8 INTEGER; do
    big_endian=$(printf '%s' "$INTEGER" | reverse_hex_endian)
    printf '%d\n' "$((16#$big_endian))"
  done
}

stream_to_hex() { xxd -ps; }
hex_to_stream() { xxd -ps -r; }

# Encode an integer as 4 bytes little-endian hex
encode_int() {
  # Source: https://stackoverflow.com/a/9955198
  printf '%08x' "$1" | sed -E 's/(..)(..)(..)(..)/\4\3\2\1/'
}

# Encode an RCON packet and write to fd 3
encode_packet() {
  local type="$1" payload="$2" request_id="$3"
  local plen total output
  plen="${#payload}"
  total="$((4 + 4 + plen + 1 + 1))"
  output=""
  output+=$(encode_int "$total")
  output+=$(encode_int "$request_id")
  output+=$(encode_int "$type")
  output+=$(printf '%s' "$payload" | stream_to_hex)
  output+="0000"
  printf '%s' "$output" | hex_to_stream
}

# Read a single RCON response packet from fd 3
read_response() {
  local hex_len len payload
  hex_len=$(head -c4 <&3 | stream_to_hex | reverse_hex_endian)
  len=$((16#$hex_len))
  payload=$(head -c "$len" <&3 | stream_to_hex)
  printf '%s' "$payload"
}

resp_request_id() { printf '%s' "${1:0:8}"  | decode_hex_int; }
resp_payload()    { printf '%s' "${1:16:-4}" | hex_to_stream; }

# Authenticate; returns 1 on wrong password
rcon_login() {
  local password="$1" response rid
  encode_packet 3 "$password" 12 >&3
  response=$(read_response)
  rid=$(resp_request_id "$response")
  if [[ "$rid" -eq -1 ]] || [[ "$rid" -eq 4294967295 ]]; then
    printf 'Authentication failed: Wrong RCON password\n' >&2
    return 1
  fi
}

# Open socket, login, send command, print response, close socket
rcon_command() {
  local host="$1" port="$2" password="$3" command="$4" response
  exec 3<>"/dev/tcp/${host}/${port}"
  rcon_login "$password" || { exec 3<&-; exec 3>&-; return 1; }
  encode_packet 2 "$command" 13 >&3
  response=$(read_response)
  resp_payload "$response"
  exec 3<&-
  exec 3>&-
}

rcon_command "$1" "$2" "$3" "$4"
