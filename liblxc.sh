#!/bin/bash

function get_ip_addresses_of_lxc() {
	local container_name="$1"
	install_apt_package csvtool csvtool
	local out=$(lxc list $container_name --format=csv | csvtool format  '%(3)' -)
	echo ${out//\(+([a-z_0-9])\)/}
}

function exits_container() {
	local container_name="$1"
	lxc list --format=csv | grep -qE "^${container_name},"
}

function is_container_running() {
	local container_name="$1"
	lxc list --format=csv | grep -qE "^${container_name},RUNNING,"
}

function is_container_stopped() {
	local container_name="$1"
	lxc list --format=csv | grep -qE "^${container_name},STOPPED,"
}

function make_sure_container_is_stopped() {
	local container_name="$1"
	if is_container_running; then
		lxc stop $container_name;
	fi
	while ! is_container_stopped $container_name; do
		echo -n "."
		sleep 1
	done
}

function list_snapshots() {
	local container_name="$1"
	install_apt_package jq jq >/dev/null
	lxc list $container_name --format=json | jq -r '.[].snapshots[].name'
}

function wait_for_ip_address_of_lxc() {
	local container_name="$1"
	while [[ "$(get_ip_addresses_of_lxc $container_name)" == "" ]]; do
		sleep 1
	done
}

function exits_container() {
	local container_name="$1"
	lxc list --format=csv | grep -qE "^${container_name},"
}

function is_container_running() {
	local container_name="$1"
	lxc list --format=csv | grep -qE "^${container_name},RUNNING,"
}

function is_container_stopped() {
	local container_name="$1"
	lxc list --format=csv | grep -qE "^${container_name},STOPPED,"
}
