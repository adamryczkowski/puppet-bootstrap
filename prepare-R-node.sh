#!/bin/bash
cd `dirname $0`
. ./common.sh


usage="
Prepares R in the server it is run on


Usage:

$(basename $0) [--rstudio] [--rstudio-server] [--repo-server <repo-address>] 
               [--deb-folder <deb_folder>] [--install-lib <path>]
                [--help] [--debug] [--log <output file>]


where

 --ip                         - IP address in the private network of the node. 
 --debug                      - Flag that sets debugging mode. 
 --log                        - Path to the log file that will log all meaningful commands
 --deb-folder <path>          - Path where the .deb files for rstudio and rstudio-server will
                                be downloaded. Preferably some sort of shared folder for whole
                                institution. 
 --repo-server <repo-address> - Alternative CRAN address. Defaults to http://cran.us.r-project.org
 --install-lib <path>         - Path to the source directory of the library to install.
                                This library purpose is to install its dependencies. Defaults to the
                                rdep repository boundled with the script.

Example2:

$(basename $0) --debug

"

if [ -z "$1" ]; then
	echo "$usage" >&2
	exit 0
fi

set -x

repo_server="http://cran.us.r-project.org"
deb_folder='/tmp'
install_lib=auto

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
	--install-lib)
	install_lib=$1
	shift
	;;
	--rstudio)
	rstudio=1
	;;
	--rstudio-server)
	rstudio_server=1
	;;
	--repo-server)
	repo_server=$1
	shift
	;;
	--deb-folder)
	deb_folder=$1
	shift
	;;
	-*)
	echo "Error: Unknown option: $1" >&2
	echo "$usage" >&2
	exit 1
	;;
esac
done

if [ -n "$debug" ]; then
	if [ -z "$log" ]; then
		log=/dev/stdout
	fi
fi

if [ -n "${install_lib}" ]; then
	install_lib=$(pwd)/rdep
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

install_apt_packages r-base-core libxml2-dev libssl-dev libcurl4-openssl-dev libssh2-1-dev sysbench openjdk-8-jdk pkg-config libnlopt-dev

logexec sudo R CMD javareconf

if ! which Rscript >/dev/null; then
	errcho "Something wrong with the R install. Abort."
	exit 1
fi
logheredoc EOT
tee /tmp/prepare_R.R <<EOT
dir.create(path = Sys.getenv("R_LIBS_USER"), showWarnings = FALSE, recursive = TRUE)
if(!require('devtools')) install.packages('devtools', Ncpus=8, repos=setNames('${repo_server}', 'CRAN'), lib = Sys.getenv("R_LIBS_USER"))
EOT

logexec Rscript /tmp/prepare_R.R
logexec Rscript -e "repos=setNames('${repo_server}', 'CRAN');options(repos=repos);devtools::install_github('hadley/devtools', Ncpus=8, lib = Sys.getenv('R_LIBS_USER'))"


if [ -n "$rstudio" ]; then
	if ! dpkg -s rstudio>/dev/null  2> /dev/null; then
		logheredoc EOT
		tee /tmp/get_rstudio_uri.R <<EOT
repos=setNames('${repo_server}', 'CRAN')
options(repos=repos);
if(!require('rvest')) install.packages('rvest', Ncpus=8, lib = Sys.getenv("R_LIBS_USER"))
xpath='.downloads:nth-child(2) tr:nth-child(5) a'
url = "https://www.rstudio.com/products/rstudio/download/"
thepage<-xml2::read_html(url)
cat(html_node(thepage, xpath) %>% html_attr("href"))
EOT
		RSTUDIO_URI=$(Rscript /tmp/get_rstudio_uri.R)
		
		wget -c $RSTUDIO_URI -O ${deb_folder}/rstudio_${netvesion}_amd64.deb
		logexec dpkg -i ${deb_folder}/rstudio_${netvesion}_amd64.deb
		if ! logexec dpkg -i ${deb_folder}/rstudio_${netvesion}_amd64.deb; then
			logexec sudo apt install -f --yes
		fi

		if ! fc-list |grep -q FiraCode; then
			for type in Bold Light Medium Regular Retina; do
				logexec wget -O ~/.local/share/fonts/FiraCode-${type}.ttf "https://github.com/tonsky/FiraCode/blob/master/distr/ttf/FiraCode-${type}.ttf?raw=true";
			done
		fi

		if fc-list |grep -q FiraCode; then
			if !grep -q "text-rendering:" /usr/lib/rstudio/www/index.htm; then
				sudo sed -i '/<head>/a<style>*{text-rendering: optimizeLegibility;}<\/style>' /usr/lib/rstudio/www/index.htm
			fi
		fi
	fi
fi


if [ -n "$rstudio_server" ]; then
	if dpkg -s rstudio>/dev/null  2> /dev/null; then
		logheredoc EOT
		tee /tmp/get_rstudio_server_uri.R <<EOT
repos=setNames('${repo_server}', 'CRAN')
options(repos=repos);
if(!require('rvest')) install.packages('rvest', Ncpus=8, lib = Sys.getenv("R_LIBS_USER"))
if(!require('stringr')) install.packages('stringr', Ncpus=8, lib = Sys.getenv("R_LIBS_USER"))
xpath='code:nth-child(3)'
url = "https://www.rstudio.com/products/rstudio/download-server/"
thepage<-xml2::read_html(url)
link<-html_node(thepage, xpath) %>% html_text()
cat(stringr::str_match(link, '^\\$( wget)? (.*)$')[[3]])
EOT
		RSTUDIO_URI=$(Rscript /tmp/get_rstudio_server_uri.R)
		logexec wget -c $RSTUDIO_URI --output-document ${deb_folder}/rstudio-server_${netversion}_amd64.deb
		if ! logexec sudo dpkg -i ${deb_folder}/rstudio-server_${netversion}_amd64.deb; then
			logexec sudo apt install -f --yes
		fi
	fi
fi

logexec sudo -H Rscript -e "update.packages(ask = FALSE, repos=setNames('${repo_server}', 'CRAN'))"
logexec Rscript -e "repos=setNames('${repo_server}', 'CRAN');options(repos=repos);update.packages(ask = FALSE,lib = Sys.getenv('R_LIBS_USER'))"
if [ -n "${install_lib}" ]; then
	logexec Rscript -e "repos=setNames('${repo_server}', 'CRAN');options(repos=repos);if(!require('devtools')) {install.packages('devtools', ask=FALSE, lib = Sys.getenv('R_LIBS_USER'));devtools::install_github('hadley/devtools', lib = Sys.getenv('R_LIBS_USER'))}"
	logexec Rscript -e "repos=setNames('${repo_server}', 'CRAN');options(repos=repos);devtools::install('${install_lib}', dependencies=TRUE, lib = Sys.getenv('R_LIBS_USER'))"
fi


