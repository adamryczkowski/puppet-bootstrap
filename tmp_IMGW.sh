#!/bin/bash
reset; bash -x ./make-lxd-node.sh xen --map-host-folder /media/adam-minipc/other/spack-mirror /media/adam-minipc/other/spack-mirror
reset;./execute-script-remotely.sh prepare_spack.sh --ssh-address adam@10.0.19.68 -- --spack-mirror /media/adam-minipc/other/spack-mirror --pre-install jq
reset; ./execute-script-remotely.sh IMGW-VPN.sh --ssh-address 10.51.192.109 -- https://aryczkowski@vpn.imgw.pl --password AeXw13589123


reset; bash -x ./deploy_IMGW_CI.sh all1 --vpn-password AeXw13589123 --vpn-username aryczkowski --git-address git@git.imgw.ad:aryczkowski/propoze.git --git-branch CEfused --ssh-key-path /home/adam/tmp/puppet-bootstrap/id_ed25519 --host-repo-path /home/tmp/propoze --preinstall-spack boost --repo-path /media/adam-minipc/other/debs --spack_mirror /media/adam-minipc/other/spack-mirror 
