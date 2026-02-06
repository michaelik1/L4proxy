#!/bin/bash

usage="\e[31mUsage: l4proxy <set/unset> <tcp/udp> <src_port> <dst_port> <dst_ip>\e[0m"

function is_port {
  [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 ))
}

function is_ip {
  [[ $1 =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

function is_port_free {
  if [[ $1 != "t" && $1 != "u" ]]; then
    echo "Error: only t/u (tcp/udp)"
    exit 1
  fi
  ! ss -ln$1 | grep -q ":$2 "
}

function protocol_to_char {
  if [[ $1 == "tcp" ]]; then
    echo "t"
  else
    echo "u"
  fi
}

function set_iptables {
  local proto=$1
  local src_port=$2
  local dst_port=$3
  local dst_ip=$4
  echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-l4proxy.conf
  sysctl --system
  iptables -t nat -C PREROUTING -p "$proto" --dport "$src_port" -j DNAT --to-destination "$dst_ip":"$dst_port" 2>/dev/null || \
    iptables -t nat -A PREROUTING -p "$proto" --dport "$src_port" -j DNAT --to-destination "$dst_ip":"$dst_port" -m comment --comment "l4proxy"
  iptables -t nat -C POSTROUTING -p "$proto" -d "$dst_ip" --dport "$dst_port" -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -p "$proto" -d "$dst_ip" --dport "$dst_port" -j MASQUERADE -m comment --comment "l4proxy"
  iptables -C FORWARD -p "$proto" -d "$dst_ip" --dport "$dst_port" -j ACCEPT 2>/dev/null || \
    iptables -A FORWARD -p "$proto" -d "$dst_ip" --dport "$dst_port" -j ACCEPT -m comment --comment "l4proxy"
  iptables -C FORWARD -p "$proto" -s "$dst_ip" --sport "$dst_port" -j ACCEPT 2>/dev/null || \
    iptables -A FORWARD -p "$proto" -s "$dst_ip" --sport "$dst_port" -j ACCEPT -m comment --comment "l4proxy"
}

function unset_iptables {
  local proto=$1
  local src_port=$2
  local dst_port=$3
  local dst_ip=$4
  rm -f /etc/sysctl.d/99-l4proxy.conf
  sysctl --system
  iptables -t nat -D PREROUTING -p "$proto" --dport "$src_port" -j DNAT --to-destination "$dst_ip":"$dst_port" -m comment --comment "l4proxy"
  iptables -t nat -D POSTROUTING -p "$proto" -d "$dst_ip" --dport "$dst_port" -j MASQUERADE -m comment --comment "l4proxy"
  iptables -D FORWARD -p "$proto" -d "$dst_ip" --dport "$dst_port" -j ACCEPT -m comment --comment "l4proxy"
  iptables -D FORWARD -p "$proto" -s "$dst_ip" --sport "$dst_port" -j ACCEPT -m comment --comment "l4proxy"
}

if [[ $EUID -ne 0 ]]; then
  echo "\e[31mRun as root\e[0m"
  exit 1
fi

if [[ $# -lt 5 || ($1 != "set" && $1 != "unset") || ($2 != "tcp" && $2 != "udp") ]] || ! is_port "$3" || ! is_port "$4" || ! is_ip "$5"; then
  echo -e "$usage"
  exit 1
fi

if [[ $1 == "set" ]]; then
  proto_char=$(protocol_to_char "$2")
  if is_port_free "$proto_char" "$3" && is_port_free "$proto_char" "$4"; then
    set_iptables "$2" "$3" "$4" "$5"
  else
    echo "port(-s) busy, check via ss and free or choose another"
    exit 1
  fi
else
  unset_iptables "$2" "$3" "$4" "$5"
fi
