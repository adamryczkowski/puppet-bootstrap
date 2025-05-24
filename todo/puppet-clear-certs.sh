#!/bin/bash

# This script is a hack to remove SSL certificates from a puppet
# client to prepare it for migration to a new puppet master server
# after puppet has altered the puppet.conf file to point to the new
# puppet master server.
#
# Normally, if you subscribe the puppet service to the puppet.conf
# file, the puppet service will be restarted too soon, interrupting
# the current puppet run. Various attempts at using
# configure_delayed_restart among other things have not proven to be
# 100% effective.  This script will watch the puppetdlock file, which
# can determine whether or not there is a run in progress. If there is
# a run in progress, we sleep for a second and then test again until
# the process is unlocked. Once unlocked, we can safely delete
# certificates and call a puppet restart. The checker process itself
# gets forked into the background. If it were not forked into the
# background, the puppet run would sit and wait for the process to
# return, or for the exec timeout, whichever came first. This would
# cause serious trouble if timeouts were disabled or very long periods
# of time.
#
# This script was inspired by this blog post by Ryan Uber:
# http://www.ryanuber.com/puppet-self-management.html
#


# Begin waiting for the current puppet run to finish, then restart.
/bin/sh -c "
    until [ ! -f /var/lib/puppet/state/puppetdlock ]
    do
        sleep 1
    done
    /sbin/service puppet stop
    rm -f /var/lib/puppet/ssl/certs/*
    rm -f /var/lib/puppet/ssl/certificate_requests/*
    rm -r /var/lib/puppet/ssl/crl.pem
    /sbin/service puppet start
" &

# Always return true, since this script just forks another process.
exit 0

# EOF
