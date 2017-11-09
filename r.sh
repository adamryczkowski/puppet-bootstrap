#!/bin/bash

sudo apt install --yes python3-pip build-essential python3-dev libffi-dev libssl-dev
sudo chown adam:adam -R /home/adam
sudo -H pip3 install --upgrade pip
sudo -H pip3 install magic-wormhole

echo "deb https://cran.rstudio.com/bin/linux/ubuntu xenial/" | sudo tee /etc/apt/sources.list.d/r.list
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys E084DAB9
sudo apt update
sudo apt install --yes r-base r-cran-digest r-cran-foreign r-cran-getopt pandoc git-core r-cran-rcpp r-cran-rjava r-cran-rsqlite r-cran-rserve libxml2-dev libssl-dev libcurl4-openssl-dev sysbench libssh2-1-dev

sudo chown -R adam:adam /usr/local/lib/R/site-library


tee install_deps.R <<EOF
install.packages(c('quantregGrowth'), Ncpus=8, repos='http://cran.us.r-project.org')
EOF

Rscript install_deps.R

wormhole receive 3-brazilian-offload
wormhole receive 7-voyager-ammo


gen_geom_series<-function(n, start, end, steepness=0.7) {
  offset<-(-1/steepness + 2)*start
  s<-offset + exp(seq(from = log(start-offset), by = log((end-offset)/(start-offset))/(n-1), length.out = n))
  return(s)
}
aa<-readRDS('q/qr_ch1.rds')
ps<-quantregGrowth::ps
tauss<-c(.03, 0.1, 0.25, 0.50, 0.75, 0.90, 0.97)
m3<-quantregGrowth::gcrq(preg_weight~ps(preg_weeks, lambda=gen_geom_series(80, 0.0001, 100)), tau=tauss, data=aa)
saveRDS(m3, 'q/m3_ch1.rds', compress='xz')



gen_geom_series<-function(n, start, end, steepness=0.7) {
  offset<-(-1/steepness + 2)*start
  s<-offset + exp(seq(from = log(start-offset), by = log((end-offset)/(start-offset))/(n-1), length.out = n))
  return(s)
}
aa<-readRDS('q/qr_dz1.rds')
ps<-quantregGrowth::ps
tauss<-c(.03, 0.1, 0.25, 0.50, 0.75, 0.90, 0.97)
m3<-quantregGrowth::gcrq(preg_weight~ps(preg_weeks, lambda=gen_geom_series(80, 0.0001, 100)), tau=tauss, data=aa)
saveRDS(m3, 'q/m3_dz1.rds', compress='xz')



gen_geom_series<-function(n, start, end, steepness=0.7) {
  offset<-(-1/steepness + 2)*start
  s<-offset + exp(seq(from = log(start-offset), by = log((end-offset)/(start-offset))/(n-1), length.out = n))
  return(s)
}
aa<-readRDS('q/qr_ch2.rds')
ps<-quantregGrowth::ps
tauss<-c(.03, 0.1, 0.25, 0.50, 0.75, 0.90, 0.97)
m3<-quantregGrowth::gcrq(preg_weight~ps(preg_weeks, lambda=gen_geom_series(80, 0.0001, 100)), tau=tauss, data=aa)
saveRDS(m3, 'q/m3_ch2.rds', compress='xz')



gen_geom_series<-function(n, start, end, steepness=0.7) {
  offset<-(-1/steepness + 2)*start
  s<-offset + exp(seq(from = log(start-offset), by = log((end-offset)/(start-offset))/(n-1), length.out = n))
  return(s)
}
aa<-readRDS('q/qr_dz2.rds')
ps<-quantregGrowth::ps
tauss<-c(.03, 0.1, 0.25, 0.50, 0.75, 0.90, 0.97)
m3<-quantregGrowth::gcrq(preg_weight~ps(preg_weeks, lambda=gen_geom_series(80, 0.0001, 100)), tau=tauss, data=aa)
saveRDS(m3, 'q/m3_dz2.rds', compress='xz')


