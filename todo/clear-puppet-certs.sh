#!/bin/bash

until [ ! -f /var/lib/puppet/state/puppetdlock ]
do
	sleep 1
done
sudo /sbin/service puppet stop
sudo rm -f /var/lib/puppet/ssl/certs/*
sudo rm -f /var/lib/puppet/ssl/certificate_requests/*
sudo rm -r /var/lib/puppet/ssl/crl.pem
sudo /sbin/service puppet start
