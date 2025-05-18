#!/bin/sh
chmod 0666 /sys/class/backlight/intel_backlight/brightness
chmod 0666 /sys/class/leds/asus::kbd_backlight/brightness
chmod 0666 /sys/class/backlight/amdgpu_bl1/brightness
chmod 0666 /sys/class/backlight/amdgpu_bl0/brightness
chmod 0666 /sys/class/backlight/nvidia_wmi_ec_backlight/brightness
