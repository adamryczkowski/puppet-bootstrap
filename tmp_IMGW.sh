#!/bin/bash
reset; bash -x ./make-lxd-node.sh xen --map-host-folder /media/adam-minipc/other/spack-mirror /media/adam-minipc/other/spack-mirror
reset;./execute-script-remotely.sh prepare_spack.sh --ssh-address adam@10.0.19.68 -- --spack-mirror /media/adam-minipc/other/spack-mirror --pre-install jq
reset; ./execute-script-remotely.sh IMGW-VPN.sh --ssh-address 10.51.192.109 -- https://aryczkowski@vpn.imgw.pl --password AeXw13589123


reset; bash -x ./deploy_IMGW_CI.sh xen --vpn-password AeXw13589123 --vpn-username aryczkowski --git-address git@git.imgw.ad:aryczkowski/propoze.git --git-branch CEfused --ssh-key-path /home/adam/tmp/puppet-bootstrap/id_ed25519 --host-repo-path /home/adam/tmp/all1 --guest-repo-path /home/adam/tmp/propoze --preinstall-spack boost --repo-path /media/adam-minipc/other/debs --spack-mirror /media/adam-minipc/other/spack-mirror  --source-dir tests/mpdata-gauge


reset; bash -x ./make-lxd-node.sh ci-runner --private-key-path id_ed25519 --public-key-path id_ed25519.pub --map-host-folder /media/adam-minipc/other /media/adam-minipc/other
reset; ./execute-script-remotely.sh prepare_spack.sh --lxc-name ci-runner --user adam -- --spack-mirror /media/adam-minipc/other/spack-mirror --pre-install cmake
reset; ./execute-script-remotely.sh prepare_for_imgw.sh --lxc-name ci-runner --user adam --step-debug  -- --gcc6
#reset; ./execute-script-remotely.sh prepare_GitLab_CI_runner.sh --lxc-name ci-runner --user adam --step-debug  -- --user adam --gitlab-server https://git1.imgw.pl --gitlab-token ENMnScUBNMFDJqjQ8N9z --runner-name koszmarny
ip=10.0.19.34
reset; ./execute-script-remotely.sh prepare_GitLab_CI_runner.sh --ssh-address adam@${ip} --step-debug -- --user adam --gitlab-server https://git1.imgw.pl --gitlab-token ENMnScUBNMFDJqjQ8N9z --runner-name wariat

reset; ./execute-script-remotely.sh prepare_GitLab_CI_runner.sh --extra-executable id_ed25519 --lxc-name ci-runner --user adam --step-debug  -- --ssh-identity id_ed25519 --gitlab-server https://git1.imgw.pl --gitlab-token ENMnScUBNMFDJqjQ8N9z --runner-name upiorny


