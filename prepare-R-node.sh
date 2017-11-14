#!/bin/bash
cd `dirname $0`
. ./common.sh


usage="
Prepares R in the server it is run on


Usage:

$(basename $0) [--rstudio] [--rstudio-server] [--help] [--debug] [--log <output file>]


where

 --ip                     - IP address in the private network of the node. 
 --debug                  - Flag that sets debugging mode. 
 --log                    - Path to the log file that will log all meaningful commands


Example2:

$(basename $0) --debug

"

set -x

while [[ $# > 0 ]]
do
key="$1"
shift

case $key in
	--debug)
	debug=1
	;;
	--log)
	log=$1
	shift
	;;
	--help)
	echo "$usage"
	exit 0
	;;
	--rstudio)
	rstudio=1
	;;
	--rstudio-server)
	rstudio_server=1
	;;
	-*)
	echo "Error: Unknown option: $1" >&2
	echo "$usage" >&2
	;;
esac
done

if [ -n "$debug" ]; then
	if [ -z "$log" ]; then
		log=/dev/stdout
	fi
fi


if ! grep -q "^deb .*https://cran.rstudio.com" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
	$loglog
	echo "deb https://cran.rstudio.com/bin/linux/ubuntu xenial/" | sudo tee /etc/apt/sources.list.d/r.list
	logexec gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys E084DAB9
	$loglog
	gpg -a --export E084DAB9 | sudo apt-key add -
	#logexec sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys E084DAB9
	flag_need_apt_update=1
fi

if ! install_apt_packages r-base r-cran-digest r-cran-foreign r-cran-getopt pandoc git-core r-cran-rcpp r-cran-rjava r-cran-rsqlite r-cran-rserve libxml2-dev libssl-dev libcurl4-openssl-dev sysbench; then
	do_upgrade
	chmod a+w /usr/local/lib/R/site-library
fi

if ! which Rscript >/dev/null; then
	errcho "Something wrong with the R install. Abourt."
	exit 1
fi

logheredoc EOT
tee /tmp/prepare_R.R <<'EOT'
if(!require('devtools')) install.packages('devtools', Ncpus=8, repos='http://cran.us.r-project.org')
devtools::install_github('hadley/devtools', Ncpus=8, repos='http://cran.us.r-project.org')
EOT

logexec sudo Rscript /tmp/get_rstudio_uri.R


if [ -n "$rstudio" ]; then
	if dpkg -s rstudio>/dev/null  2> /dev/null; then
		ver=$(apt show rstudio | grep Version)
		pattern='^Version: ([0-9.]+)\s*$'
		if [[ $ver =~ $pattern ]]; then
			ourversion=${BASH_REMATCH[1]}
			do_check=1
		fi
	else
		do_check=1
		ourversion="0.0"
	fi
	if [ "$do_check" == 1 ]; then
        netversion=$(Rscript -e 'cat(stringr::str_match(scan("https://www.rstudio.org/links/check_for_update?version=1.0.0", what = character(0), quiet=TRUE), "^[^=]+=([^\\&]+)\\&.*")[[2]])')
        if [ "$ourversion" != "$netversion" ]; then
        	RSTUDIO_URI=$(Rscript /tmp/get_rstudio_uri.R)
        	tee /tmp/get_rstudio_uri.R <<'EOF'
if(!require('rvest')) install.packages('rvest', Ncpus=8, repos='http://cran.us.r-project.org')
xpath='.downloads:nth-child(2) tr:nth-child(5) a'
url = "https://www.rstudio.com/products/rstudio/download/"
thepage<-xml2::read_html(url)
cat(html_node(thepage, xpath) %>% html_attr("href"))
EOF
			RSTUDIO_URI=$(Rscript /tmp/get_rstudio_uri.R)
			
			logexec wget -c --output-document /tmp/rstudio.deb "$RSTUDIO_URI"
			logexec sudo dpkg -i /tmp/rstudio.deb
			logexec apt install -f --yes
			logexec rm /tmp/rstudio.deb
			rm /tmp/get_rstudio_uri.R


			if ! fc-list |grep -q FiraCode; then
			for type in Bold Light Medium Regular Retina; do
				logexec wget -O ~/.local/share/fonts/FiraCode-${type}.ttf "https://github.com/tonsky/FiraCode/blob/master/distr/ttf/FiraCode-${type}.ttf?raw=true";
			done

			if fc-list |grep -q FiraCode; then
				if !grep -q "text-rendering:" /usr/lib/rstudio/www/index.htm; then
					logexec sudo sed -i '/<head>/a<style>*{text-rendering: optimizeLegibility;}<\/style>' /usr/lib/rstudio/www/index.htm
				fi
			fi
		fi
	fi
fi

if [ -n "$rstudio_server" ]; then
	if dpkg -s rstudio>/dev/null  2> /dev/null; then
		ver=$(apt show rstudio-server | grep Version)
		pattern='^Version: ([0-9.]+)\s*$'
		if [[ $ver =~ $pattern ]]; then
			ourversion=${BASH_REMATCH[1]}
			do_check=1
		fi
	else
		do_check=1
		ourversion="0.0"
	fi
	if [ "$do_check" == 1 ]; then
        netversion=$(wget --no-check-certificate -qO- https://s3.amazonaws.com/rstudio-server/current.ver)
        if [ "$ourversion" != "$netversion" ]; then
        	tee /tmp/get_rstudio_uri.R <<'EOT'
if(!require('rvest')) install.packages('rvest', Ncpus=8, repos='http://cran.us.r-project.org')
if(!require('stringr')) install.packages('stringr', Ncpus=8, repos='http://cran.us.r-project.org')
xpath='code:nth-child(3)'
url = "https://www.rstudio.com/products/rstudio/download-server/"
thepage<-xml2::read_html(url)
link<-html_node(thepage, xpath) %>% html_text()
cat(stringr::str_match(link, '^\\$ (.*)$')[[2]])
EOT
			RSTUDIO_URI=$(sudo Rscript /tmp/get_rstudio_uri.R)
			RSTUDIO_URI=$(sudo Rscript /tmp/get_rstudio_uri.R)
			
			logexec wget -c --output-document /tmp/rstudio-server.deb $RSTUDIO_URI 
			logexec sudo dpkg -i /tmp/rstudio-server.deb
			logexec apt install -f --yes
			logexec rm /tmp/rstudio-server.deb
			rm /tmp/get_rstudio_uri.R
		fi
	fi
fi

