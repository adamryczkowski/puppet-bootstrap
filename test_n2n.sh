reset; bash -x ./make-lxd-node.sh n2nhost --ip 10.162.198.12 --autostart
reset; ./execute-script-remotely.sh ./n2n-server.sh --ssh-address n2nhost -- --password szakal --port 5536 --network-name SiecAdama
lxc config device add n2nhost forwardudp5536 proxy listen=udp:0.0.0.0:5536 connect=udp:localhost:5536 bind=host

