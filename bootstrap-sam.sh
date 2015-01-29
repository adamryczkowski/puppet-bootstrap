#!/bin/bash

reset; sudo bash  ./ensure-ssh-access-setup-by-proxies.sh --server-access root@localhost --client-access root@localhost --server-target-account adam --log /dev/stdout

#bash -x ./configure-lxc.sh --hostip 10.0.19.1 --network 10.0.19.0/24 --dhcprange 10.0.19.200,10.0.19.254 --usermode --log /home/pupecik/lxc-install.log

bash -- ./bootstrap-puppet-and-friends.sh --gitolite-lxc-name gitolite --gitolite-lxc-ip 10.0.19.107 --gitolite-name gitolite.statystyka.net --user-on-gitolite adas --puppetmaster-lxc-name puppetmaster --puppetmaster-lxc-ip 10.0.19.106 --puppetmaster-name puppetmaster.statystyka.net --user-on-puppetmaster adam --lxc-host-ip 10.0.19.1 --lxc-network 10.0.19.0/24 --lxc-dhcprange 10.0.19.200,10.0.19.254 --lxc-usermode --import-puppet-manifest git://10.0.19.1/manifest --import-git puppet/autostart:git://10.0.19.1/modules/autostart --import-git puppet/lxc:git://10.0.19.1/modules/lxc --import-git puppet/sshauth:git://10.0.19.1/modules/sshauth --log /home/pupecik/lxc-install.log --dont-merge-manifest-with-template

reset; puppet agent --test --debug >puppet-lxc.log 2>&1; cat puppet-lxc.log


./force-sudo.sh puppetmaster --lxcowner pupecik --lxcusername adam
./force-sudo.sh gitolite --lxcowner pupecik --lxcusername adas

#Poniższą komendę mogę używać do deploy puppet module:
#git add . --all ; git commit -m "x"; git push --all; ssh root@sam.statystyka.net  "cd bootstrap; ./force-sudo.sh puppetmaster --lxcowner pupecik --lxcusername adam"; ssh adam@puppetmaster.statystyka.net -p 1222 "sudo su -l puppet -c 'r10k deploy environment production -p';sudo service puppetmaster restart"


#Poniższą komendę mogę używać do deploy puppet manifest:
#git add . --all ; git commit -m "x"; git push --all; ssh root@sam.statystyka.net  "cd bootstrap; ./force-sudo.sh puppetmaster --lxcowner pupecik --lxcusername adam"; ssh adam@puppetmaster.statystyka.net -p 1222 "sudo service puppetmaster restart"

