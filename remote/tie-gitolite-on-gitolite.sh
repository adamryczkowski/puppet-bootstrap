#!/bin/bash
cd `dirname $0`

#Program jest częścią zdalną tie-gitolite-with-puppet.sh.
#Program służy do konfiguracji gitolite tak, aby było połączone z puppetem

#tie-gitolite-on-gitolite.sh --puppetmaster-uri <kompatybilna z GIT ścieżka do repozytorium puppet.git w puppetmaster. Domyślnie /srv/puppet.git> --puppetmaster-username <nazwa użytkownika puppetmaster, domyślnie puppet> --gitolite-puppet-manifest-repo <nazwa repozytorium z gitolite. Domyślnie puppet/manifest> [--puppetmaster-is-local-to-gitolite] [--dont-push]

. ./common.sh

alias errcho='>&2 echo'

gitoliteuser=gitolite
user=`whoami`

puppetislocal=0
puppetsource="/srv/puppet.git"
puppetuser=puppet
gitoliterepo=puppet/manifest

dopush=1
#puppetrepo=puppet/manifest

while [[ $# > 0 ]]
do
	key="$1"
	shift

	case $key in
		--dont-push)
			dopush=0
			;;
		--puppetmaster-is-local-to-gitolite)
			puppetislocal=1
			;;
		--puppetmaster-uri)
			puppetsource=$1
			shift
			;;
		--puppetmaster-server)
			puppetserver=$1
			shift
			;;
		--puppetmaster-username)
			puppetuser=$1
			shift
			;;
		--gitolite-puppet-manifest-repo)
			gitoliterepo=$1
			shift
			;;
		--debug)
			debug=1
			;;
		--log)
			log=$1
			shift
			;;
		*)
			echo "Unkown parameter '$key'. Aborting."
			exit 1
			;;
	esac
done

if [ "$puppetislocal" -eq 1 ]; then
	puppetserver=localhost
fi

if [ -z "$puppetserver" ]; then
	errcho "you must specify --puppetmaster-server or --puppetmaster-is-local-to-gitolite"
	exit 1
fi


#Instalujemy skrypcik puppet-deploy w gitolite, który będzie propagował push do puppet.srv
logexec sudo -u $gitoliteuser mkdir -p /var/lib/gitolite/local/hooks/repo-specific
logheredoc EOT
sudo -u $gitoliteuser tee /var/lib/gitolite/local/hooks/repo-specific/deploy-puppet <<'EOT'  >/dev/null
#!/bin/sh
git push --all
EOT
logexec sudo -u $gitoliteuser chmod +x /var/lib/gitolite/local/hooks/repo-specific/deploy-puppet
logexec sudo -u $gitoliteuser sed -i -e "/\# LOCAL_CODE.*ENV{HOME}\/local/ s/\#\s//" /var/lib/gitolite/.gitolite.rc
logexec sudo -u $gitoliteuser sed -i -e "/\# 'repo-specific-hooks',/ s/\#\s//" /var/lib/gitolite/.gitolite.rc

logexec sudo su -l $gitoliteuser -c "gitolite setup"

#Upewniamy się, że serwer puppet mastera nie będzie dla gitolite obcy
#sshhome=`getent passwd $gitoliteuser | awk -F: '{ print $6 }'`
#sudo -u $gitoliteuser ssh-keygen -f "$sshhome/.ssh/known_hosts" -R $puppetserver >/dev/null 2>/dev/null
#sudo -u $gitoliteuser ssh-keyscan -H $puppetserver | sudo -u $gitoliteuser tee -a $sshhome/.ssh/known_hosts 2>/dev/null
