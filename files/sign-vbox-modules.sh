#!/bin/bash

function sign() {

	for modfile in $(dirname $(modinfo -n $1))/*.ko; do
		echo "Signing $modfile"
		/usr/src/linux-headers-$(uname -r)/scripts/sign-file sha256 \
			/var/lib/shim-signed/mok/MOK.priv \
			/var/lib/shim-signed/mok/MOK.der "$modfile"
	done
}

sign vboxdrv
sign vboxnetflt
sign vboxnetadp
sign vboxpci
