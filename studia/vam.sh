#!/bin/bash

Wersja 1.0.0

cd `dirname $0`
. ./common.sh

#Skrypt, który ma być uruchomiony na komputerze VAM, aby stworzyć cały framework

bash -x ./configure-lxc.sh --hostip 10.0.17.1 --network 10.0.17.0/24 --dhcprange 10.0.17.200,10.0.17.254 --usermode --log `pwd`/mylog.log --log /dev/stdout

./configure-lxc.sh --hostip 10.0.17.1 --network 10.0.17.0/24 --dhcprange 10.0.17.200,10.0.17.254 --usermode --log /dev/stdout

reboot

bash -x -- ./make-lxc-node.sh usik --debug --ip 10.0.17.105 --grant-ssh-access-to zosia --apt-proxy 192.168.56.1:3142 --hostname usik.statystyka.net --usermode  --log `pwd`/log-make-lxc-node.log

bash -x ./prepare-git-serving.sh -r `dirname $0`


# bash -x -- ./bootstrap-puppet-and-friends.sh --debug --gitolite-lxc-name gitolite --gitolite-lxc-ip 10.0.17.107 --gitolite-name gitolite.statystyka.net --user-on-gitolite adas --puppetmaster-lxc-name puppetmaster --puppetmaster-lxc-ip 10.0.17.106 --puppetmaster-name puppetmaster.statystyka.net --user-on-puppetmaster adam --lxc-host-ip 10.0.17.1 --lxc-network 10.0.17.0/24 --lxc-dhcprange 10.0.17.200,10.0.17.254 --lxc-usermode --apt-proxy 192.168.56.1:3142 --import-puppet-manifest git://10.0.13.1/manifest.git --import-git puppet/autostart:git://10.0.13.1/modules/autostart.git --import-git puppet/lxc:git://10.0.13.1/modules/lxc.git --log `pwd`/mylog.log

bash -- ./bootstrap-puppet-and-friends.sh --gitolite-lxc-name gitolite --gitolite-lxc-ip 10.0.17.107 --gitolite-name gitolite.vam.statystyka.net --user-on-gitolite adas --puppetmaster-lxc-name puppetmaster --puppetmaster-lxc-ip 10.0.17.106 --puppetmaster-name puppetmaster.vam.statystyka.net --user-on-puppetmaster adam --lxc-host-ip 10.0.17.1 --lxc-network 10.0.17.0/24 --lxc-dhcprange 10.0.17.200,10.0.17.254 --lxc-usermode --apt-proxy 192.168.56.1:3142 --import-puppet-manifest git://10.0.13.1/manifest --import-git puppet/autostart:git://10.0.13.1/modules/autostart --import-git puppet/lxc:git://10.0.13.1/modules/lxc --import-git puppet/sshauth:git://10.0.13.1/modules/sshauth --log /dev/stdout --dont-merge-manifest-with-template

bash -- ./bootstrap-puppet-and-friends.sh --gitolite-lxc-name gitolite --gitolite-lxc-ip 10.0.13.107 --gitolite-name gitolite.statystyka.net --user-on-gitolite zosia --puppetmaster-lxc-name puppetmaster --puppetmaster-lxc-ip 10.0.13.106 --puppetmaster-name puppetmaster.statystyka.net --user-on-puppetmaster zosia --lxc-host-ip 10.0.13.1 --lxc-network 10.0.13.0/24 --lxc-dhcprange 10.0.13.200,10.0.13.254 --lxc-usermode --apt-proxy 10.0.13.1:3142 --import-puppet-manifest git://10.0.13.1/manifest --import-git puppet/autostart:git://10.0.13.1/modules/autostart --import-git puppet/lxc:git://10.0.13.1/modules/lxc --import-git puppet/sshauth:git://10.0.13.1/modules/sshauth --log /dev/stdout --dont-merge-manifest-with-template

./force-sudo.sh puppetmaster --lxcusername zosia --usermode
./force-sudo.sh gitolite --lxcusername zosia --usermode

stop



bash ./execute-script-remotely.sh remote/configure-puppetclient.sh --host 192.168.56.101 --user zosia --debug --log /dev/stdout -- --puppetmaster puppetmaster.statystyka.net --myfqdn vam.statystyka.net

sudo mkdir -p /home/adam/.cache/lxc; sudo rsync -avr /home/zosia/bootstrap/lxc-cache/* /home/adam/.cache/lxc; sudo chown -R adam:adam /home/adam/.cache; sudo mkdir -p /home/mikolaj/.cache/lxc; sudo rsync -avr /home/zosia/bootstrap/lxc-cache/* /home/mikolaj/.cache/lxc; sudo chown -R mikolaj:mikolaj /home/mikolaj/.cache;

. ./execute-script-remotely.sh remote/configure-puppetclient.sh --host localhost -- --puppetmaster puppetmaster.statystyka.net

bash -x ./install-puppetmaster-on-lxc.sh --usermode --fqdn puppetmaster.statystyka.net --debug --lxc-name puppetmaster --other-lxc-opts "--ip 10.0.17.106 --apt-proxy 192.168.56.1:3142" --lxc-username adam

bash -x ./install-gitolite-on-lxc.sh --usermode --fqdn gitolite.statystyka.net --debug --lxc-name gitolite --lxc-username adas --other-lxc-opts "--ip 10.0.17.107 --apt-proxy 192.168.56.1:3142" --git-user zosia

lxc-start -d -n puppetmaster
lxc-start -d -n gitolite
lxc-start -d -n usik

./force-sudo.sh usik --lxcusername zosia --usermode
./force-sudo.sh puppetmaster --lxcusername adam --usermode
./force-sudo.sh gitolite --lxcusername adas --usermode

bash -x ./prepare-git-serving.sh -r /home/Adama-docs/Adam/puppet

bash -x -- ./tie-gitolite-with-puppet.sh --gitolite-server adas@gitolite --puppetmaster-server adam@puppetmaster --dont-merge-existing-manifest-git --remote-manifest git://10.0.13.1/manifest.git --debug

bash -x -- ./import-into-gitolite.sh --ssh-address adas@gitolite --git-repo-uri git://10.0.13.1/manifest.git --reponame puppet/autostart -c `whoami` --debug

sudo rm -r manifest
git clone gitolite@gitolite:puppet/manifest
cd manifest
cp hieradata/nodes/loft40.statystyka.net.yaml hieradata/nodes/usik.statystyka.net.yaml
cp hieradata/nodes/loft40.statystyka.net.yaml hieradata/nodes/gitolite.statystyka.net.yaml
cp hieradata/nodes/loft40.statystyka.net.yaml hieradata/nodes/puppetmaster.statystyka.net.yaml
git add .
git commit -m "usik i reszta"
git config --global push.default matching
git push

bash -x -- ./execute-script-remotely.sh remote/configure-puppetclient.sh --user zosia --host vam.statystyka.net -- --puppetmaster puppetmaster.statystyka.net --myfqdn vam.statystyka.net


#To jest skrypt, który tworzy konter LXC z konfiguruje puppetmaster wewnątrz.
#install-puppetmaster-on-lxc.sh [--fqdn <fqdn>] [--debug|-d] --lxc-name <lxc container name> [--lxc-username <lxc user name>] --other-lxc-opts <other options to make-lxc-node> ] [--conf-puppet-opts <other options to configure-puppetmaster>] [-g|--git-user <user name>] [-h|--git-user-keypath <keypath>] [--r10k-gems-path <path to the gem cache>] [--import-into-gitolite-server <ssh-compatible address of gitolite server>]
#--fqdn - fqdn
#--debug|-d
#--lxc-name - lxc container name
#--lxc-username - lxc user name
#--other-lxc-opts - other options forwarded to make-lxc-node
#--conf-puppet-opts - dodatkowe opcje do przekazania skryptowi configure-puppetmaster
#--r10k-gems-path - path to the gem cache. Useful if no or little internet is available

#
#
#

bash -x ./configure-lxc.sh --hostip 10.0.17.1 --network 10.0.17.0/24 --dhcprange 10.0.17.200,10.0.17.254

bash -x ./install-puppetmaster-on-lxc.sh --fqdn puppetmaster.statystyka.net --debug --lxc-name puppetmaster --other-lxc-opts "--ip 10.0.17.106 --apt-proxy 192.168.56.1:3142" --lxc-username adam

bash -x ./install-gitolite-on-lxc.sh --fqdn gitolite.statystyka.net --debug --lxc-name gitolite --lxc-username adas --other-lxc-opts "--ip 10.0.17.107 --apt-proxy 192.168.56.1:3142" --git-user zosia

bash -x -- ./make-lxc-node.sh usik --debug --ip 10.0.17.105 --grant-ssh-access-to zosia --apt-proxy 192.168.56.1:3142 --hostname usik.statystyka.net

#tie-gitolite-with-puppet
#	-g|--gitolite-server <[username]@severname> SSH URI do serwera gitolite. Obowiązkowy parametr>
#	--puppetmaster-is-local-to-gitolite
#	--puppetmaster-server <SSH URI do serwera, jeśli puppetmaster jest oddzielny. Podania tego parametru zakłada, że puppetmaster nie jest lokalny. Użytkownik wywołujący skrypt musi mieć uprawnienia sudo do tego serwera w celu ustawienia kluczy>
#	-r|--main-manifest-repository <nazwa głównego repozytorium, domyślnie "puppet/manifest">
#	--dont-merge-existing-manifest-git - jeśli podane, to manifest w gitolite nie będzie połączony z istniejącym manifestem szkieletowym stworzonym automatycznie przez skrypt configure-puppetmaser.sh
#	--puppetmaster-rsa-pub <ścieżka do klucza publicznego puppetmastera, osiągalna przez scp. Jeśli nie jest podana, to skrypt zaloguje się na puppetmasterze i uruchomi ssh-keygen>
#	--remote-manifest <akceptowalna przez git ścieżka do głównego repozytorium> - jeśli nie podane, to zostanie wykorzystany automatyczne, szkieletowe repozytorium

mypath=`pwd`

cd /tmp/temp


sudo lxc-start -d -n puppetmaster
sudo lxc-start -d -n gitolite

bash -x force-sudo.sh puppetmaster --lxcusername adam

bash -x force-sudo.sh gitolite --lxcusername adas

#Exportujemy nasz manifest pod git://10.0.13.1/manifest.git
bash -x ./prepare-git-serving.sh -r /home/Adama-docs/Adam/puppet

./force-sudo gitolite -l adas
./force-sudo puppetmaster -l adam

bash -x -- ./tie-gitolite-with-puppet.sh --gitolite-server adas@gitolite --puppetmaster-server adam@puppetmaster --dont-merge-existing-manifest-git --remote-manifest git://10.0.13.1/manifest.git --debug



reset; sudo bash  ./ensure-ssh-access-setup-by-proxies.sh --server-access root@localhost --client-access root@localhost --server-target-account adam --log /dev/stdout
