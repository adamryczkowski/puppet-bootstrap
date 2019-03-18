reset; bash -x ./make-lxd-node.sh n2nserver --bare --release bionic 
reset; bash -x ./make-lxd-node.sh n2nclient --bare --release bionic
reset; bash -x ./make-lxd-node.sh klient
reset; bash -x ./make-lxd-node.sh customer


lxc list
ip_client=10.51.192.156
ip_client=10.51.192.150
ip_server=10.51.192.210

reset;./execute-script-remotely.sh n2n-server.sh --ssh-address adam@${ip_server} --extra-executable files/n2n -- --password 'szakal' --port 5536 --network-name SiecAdama

reset;./execute-script-remotely.sh n2n-client.sh --ssh-address adam@${ip_client} --step-debug --extra-executable files/n2n -- ${ip_server}:5536 --password 'szakal' --network-name SiecAdama





reset; bash -x ./make-lxd-node.sh n2nhost --ip 10.162.198.12 --autostart
reset; ./execute-script-remotely.sh ./n2n-server.sh --ssh-address n2nhost -- --password szakal --port 5536 --network-name SiecAdama
lxc config device add n2nhost forwardudp5536 proxy listen=udp:0.0.0.0:5536 connect=udp:localhost:5536 bind=host



on commit {
	set ClientIP = binary-to-ascii(10, 8, ".", leased-address);
	set ClientMac = binary-to-ascii(16, 8, ":", substring(hardware, 1, 6));
	set ClientName = pick-first-value ( option fqdn.hostname, option host-name );
	log(concat("Commit: IP: ", ClientIP, " Mac: ", ClientMac));
	execute("/usr/bin/dhcp-event", "commit", ClientIP, ClientMac, ClientName);
}

