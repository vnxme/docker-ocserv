#!/bin/bash

# Supported environment variables:
#
# Firewall & Forwarding
# FORWARDING   - [true/ipv4/ipv6/false]      - enables/disables IPv4/IPv6 forwarding
# MASQUERADE   - [true/...]                  - enables masquerade on the default interface
# PRIVATE_IPV4 - [semicolon separated CIDRs] - IPv4 ranges to masquerade outgoing traffic from
# PRIVATE_IPV6 - [semicolon separated CIDRs] - IPv6 ranges to masquerade outgoing traffic from
#
# Routing Daemon (bird)
# - BIRD_ARGS   -                     - custom args
# - BIRD_CONFIG - /etc/bird/bird.conf - config path
#
# OpenConnect Server (ocserv)
# - OCSERV_ARGS   -                         - custom args
# - OCSERV_CONFIG - /etc/ocserv/ocserv.conf - config path
#
# Note: if ${OCSERV_CONFIG} doesn't exist, but its directory does,
# the script runs ocserv with each *.conf found in this directory.
#
# Other Apps
# - OTHER_APPS - [semicolon separated commands] - custom commands to run with `sh -c`

PIDS=()

firewall_up() {
	local M="${MASQUERADE,,:-}"

	if [ -n "$(which iptables)" ] && [ $(iptables -t filter -L 2>/dev/null 1>&2; echo $?) -eq 0 ]; then
		IPT4='iptables'
	elif [ -n "$(which iptables-legacy)" ] && [ $(iptables-legacy -t filter -L 2>/dev/null 1>&2; echo $?) -eq 0 ]; then
		IPT4='iptables-legacy'
	fi

	if [ -n "${IPT4}" ]; then
		FIREWALL_IPV4_FILTER="$(${IPT4}-save -t filter || true)"
		FIREWALL_IPV4_MANGLE="$(${IPT4}-save -t mangle || true)"
		FIREWALL_IPV4_NAT="$(${IPT4}-save -t nat || true)"

		${IPT4} -t filter -F || true
		${IPT4} -t mangle -F || true
		${IPT4} -t nat -F || true

		if [ "${M}" == "true" ]; then
			local IFACE="$(ip route | grep default | awk '{print $5}')"
			if [ -n "${IFACE}" ]; then
				if [ -n "${PRIVATE_IPV4:-}" ]; then
					local RANGES; IFS=';' read -r -a RANGES <<< "${PRIVATE_IPV4}"
					local RANGE; for RANGE in "${RANGES[@]}"; do
						${IPT4} -t nat -A POSTROUTING -s ${RANGE} -o ${IFACE} -j MASQUERADE || true
					done
				else
					${IPT4} -t nat -A POSTROUTING -o ${IFACE} -j MASQUERADE || true
				fi
			fi
		fi
	fi

	if [ -n "$(which ip6tables)" ] && [ $(ip6tables -t filter -L 2>/dev/null 1>&2; echo $?) -eq 0 ]; then
		IPT6='ip6tables'
	elif [ -n "$(which ip6tables-legacy)" ] && [ $(ip6tables-legacy -t filter -L 2>/dev/null 1>&2; echo $?) -eq 0 ]; then
		IPT6='ip6tables-legacy'
	fi

	if [ -n "${IPT6}" ]; then
		FIREWALL_IPV6_FILTER="$(${IPT6}-save -t filter || true)"
		FIREWALL_IPV6_MANGLE="$(${IPT6}-save -t mangle || true)"
		FIREWALL_IPV6_NAT="$(${IPT6}-save -t nat || true)"

		${IPT6} -t filter -F || true
		${IPT6} -t mangle -F || true
		${IPT6} -t nat -F || true

		if [ "${M}" == "true" ]; then
			local IFACE="$(ip -6 route | grep default | awk '{print $5}')"
			if [ -n "${IFACE}" ]; then
				if [ -n "${PRIVATE_IPV6:-}" ]; then
					local RANGES; IFS=';' read -r -a RANGES <<< "${PRIVATE_IPV6}"
					local RANGE; for RANGE in "${RANGES[@]}"; do
						${IPT6} -t nat -A POSTROUTING -s ${RANGE} -o ${IFACE} -j MASQUERADE || true
					done
				else
					${IPT6} -t nat -A POSTROUTING -o ${IFACE} -j MASQUERADE || true
				fi
			fi
		fi
	fi
}

firewall_down() {
	if [ -n "${IPT4}" ]; then
		echo "${FIREWALL_IPV4_FILTER}" | ${IPT4}-restore || true
		echo "${FIREWALL_IPV4_MANGLE}" | ${IPT4}-restore || true
		echo "${FIREWALL_IPV4_NAT}" | ${IPT4}-restore || true
	fi

	if [ -n "${IPT6}" ]; then
		echo "${FIREWALL_IPV6_FILTER}" | ${IPT6}-restore || true
		echo "${FIREWALL_IPV6_MANGLE}" | ${IPT6}-restore || true
		echo "${FIREWALL_IPV6_NAT}" | ${IPT6}-restore || true
	fi
}

forwarding_up() {
	FORWARDING_IPV4="$(cat /proc/sys/net/ipv4/ip_forward)"
	FORWARDING_IPV6_ALL="$(cat /proc/sys/net/ipv6/conf/all/forwarding)"
	FORWARDING_IPV6_DEF="$(cat /proc/sys/net/ipv6/conf/default/forwarding)"	

	local F="${FORWARDING,,:-}"
	if [ "${F}" == "true" ]; then
		echo 1 > /proc/sys/net/ipv4/ip_forward
		echo 1 > /proc/sys/net/ipv6/conf/all/forwarding
		echo 1 > /proc/sys/net/ipv6/conf/default/forwarding
	elif [ "${F}" == "ipv4" ]; then
		echo 1 > /proc/sys/net/ipv4/ip_forward
		echo 0 > /proc/sys/net/ipv6/conf/all/forwarding
		echo 0 > /proc/sys/net/ipv6/conf/default/forwarding
	elif [ "${F}" == "ipv6" ]; then
		echo 0 > /proc/sys/net/ipv4/ip_forward
		echo 1 > /proc/sys/net/ipv6/conf/all/forwarding
		echo 1 > /proc/sys/net/ipv6/conf/default/forwarding
	elif [ "${F}" == "false" ]; then
		echo 0 > /proc/sys/net/ipv4/ip_forward
		echo 0 > /proc/sys/net/ipv6/conf/all/forwarding
		echo 0 > /proc/sys/net/ipv6/conf/default/forwarding
	fi
}

forwarding_down() {
	echo "${FORWARDING_IPV4}" > /proc/sys/net/ipv4/ip_forward
	echo "${FORWARDING_IPV6_ALL}" > /proc/sys/net/ipv6/conf/all/forwarding
	echo "${FORWARDING_IPV6_DEF}" > /proc/sys/net/ipv6/conf/default/forwarding
}

hooks() {
	local FILE; for FILE in /app/hooks/$1/*.sh; do
		if [ -s "${FILE}" ]; then
			/bin/sh "${FILE}" || true
		fi
	done
}

launch() {
	# Configure firewall and forwarding
	firewall_up
	forwarding_up

	# Call up hooks
	hooks "up"

	# Launch a bird instance if it's installed
	if [ -n "$(which bird)" ]; then
		local FILE="${BIRD_CONFIG:-/etc/bird/bird.conf}"
		if [ -s "${FILE}" ]; then
			bird -c "${FILE}" -f -R ${BIRD_ARGS:-} &
			PIDS+=($!)
		fi
	fi

	# Launch one or multiple ocserv instances
	if [ -n "$(which ocserv)" ]; then
		local FILE="${OCSERV_CONFIG:-/etc/ocserv/ocserv.conf}"
		if [ -s "${FILE}" ]; then
			ocserv -c "${FILE}" -f ${OCSERV_ARGS:-} &
			PIDS+=($!)
		else
			DIR="$(dirname -- "${FILE}")"
			if [ -d "${DIR}" ]; then
				local FILE; for FILE in ${DIR}/*.conf; do
					ocserv -c "${FILE}" -f ${OCSERV_ARGS:-} &
					PIDS+=($!)
				done
			fi
		fi
	fi

	# Launch other background apps if requested
	local APPS
	if [ "$#" -gt 0 ]; then
		APPS=("$@")
	elif [ -n "${OTHER_APPS:-}" ]; then
		IFS=';' read -r -a APPS <<< "${OTHER_APPS}"
	fi
	local APP; for APP in "${APPS[@]}"; do
		sh -c "${APP}" &
		PIDS+=($!)
	done
}

terminate() {
	# Terminate all subprocesses
	local PID; for PID in "${PIDS[@]}"; do
		kill "${PID}" 2>/dev/null || true
	done

	# Call down hooks
	hooks "down"

	# Restore firewall and forwarding
	forwarding_down
	firewall_down

	exit 0
}

# Call terminate() when SIGTERM is received
trap terminate TERM

# Call launch() with command line arguments
launch $@

# Wait for all subprocesses to exit
FAIL=0
for PID in "${PIDS[@]}"; do
	if ! wait "${PID}"; then
		FAIL=1
	fi
done
exit ${FAIL}
