#!/bin/bash

echo "deb http://cran.rstudio.com/bin/linux/ubuntu xenial/" | sudo tee /etc/apt/sources.list.d/r.list
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys E084DAB9
sudo apt update
sudo apt install --yes r-base r-cran-digest r-cran-foreign r-cran-getopt git-core r-cran-rcpp r-cran-rjava r-cran-rsqlite r-cran-rserve libxml2-dev libssl-dev libcurl4-openssl-dev 


tee get_rstudio_uri.R <<EOF
if(!require('stringr')) install.packages('stringr', Ncpus=8, repos='http://cran.us.r-project.org')
if(!require('rvest')) install.packages('rvest', Ncpus=8, repos='http://cran.us.r-project.org')

xpath<-'//code[(((count(preceding-sibling::*) + 1) = 3) and parent::*)]'
url<-'https://www.rstudio.com/products/rstudio/download-server/'
thepage<-xml2::read_html(url)
the_links_html <- rvest::html_nodes(thepage,xpath=xpath)
the_links <- rvest::html_text(the_links_html)
the_link <- the_links[stringr::str_detect(the_links, '-amd64\\\\.deb')]
the_r_uri<-stringr::str_match(the_link, 'https://.*$')
cat(the_r_uri)
EOF


Rscript get_rstudio_uri.R
RSTUDIO_URI=$(Rscript get_rstudio_uri.R)

mkdir tmp
cd tmp
wget $RSTUDIO_URI
sudo dpkg -i *.deb


sudo apt install --yes python3-pip build-essential python3-dev libffi-dev libssl-dev htop mc pxz pngquant image-magick pandoc
sudo -H pip3 install --upgrade pip
sudo -H pip3 install magic-wormhole





tee install_deps.R <<EOF
list.of.packages <- c('devtools', 'data.table', 'ggplot2', 'purrr', 'readxl', 'Hmisc', 'R.utils', 'xlsx', 'readODS', 'pander', 'gridExtra', 'RColorBrewer', 'zipfR', 'ggrepel', 'lsr', 'car', 'doMC', 'ROCR', 'glmnet', 'lubridate', 'dplyr','dtplyr','tidyr','broom','ggfortify', 'rstan', 'stringr', 'rvest', 'mice', 'quantregGrowth')
new.packages <- list.of.packages[!(list.of.packages %in% installed.packages()[,"Package"])]
if(length(new.packages)) install.packages(new.packages, Ncpus=8, repos='http://cran.us.r-project.org')

devtools::install_github(c('adamryczkowski/pathcat', 'adamryczkowski/depwalker', 'adamryczkowski/danesurowe', 'Zelazny7/binnr'))
EOF

Rscript install_deps.R

sudo mkdir -p /home/Adama-docs/yuxia
sudo chown adam:adam -R /home/Adama-docs
cd /home/Adama-docs/yuxia

git clone --depth 1 git@gitlab.com:adamwam/yuxia.git

git config --global user.email "adam@statystyka.net"
git config --global user.name "Adam Ryczkowski"
git config --global push.default simple


#sudo route add -net 10.29.153.0/24 gw 192.168.1.103
