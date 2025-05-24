#!/bin/bash

if [ ! -f /tmp/suppress_power_event ]; then
	touch -d '+2 second' /tmp/suppress_power_event
fi
touch /tmp/now
if [ /tmp/now -nt /tmp/suppress_power_event  ]; then
	sleep 1
	charging_state=$(acpi -a)
	PATTERN='off-line'
	if [[ -z "$charging_state" ]]; then
		charging_state=$(acpitool --battery | grep "Charging state")
		PATTERN='Discharging'
	fi
	echo "$charging_state" > /tmp/debug
	if [[ "$charging_state" =~ $PATTERN ]]; then
		play /usr/share/sounds/freedesktop/stereo/power-unplug.oga
		touch /tmp/discharging
	else
		play /usr/share/sounds/freedesktop/stereo/power-plug.oga
		rm -f /tmp/discharging
	fi
	touch -d '+5 second' /tmp/suppress_power_event
fi
