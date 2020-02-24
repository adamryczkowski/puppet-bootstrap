#!/bin/bash

function get_ip_addresses_of_lxc {
	local container_name="$1"
	lxc list "${container_name}" -c 4 | awk '!/IPV4/{ if ( $2 != "" ) print $2}'
}
