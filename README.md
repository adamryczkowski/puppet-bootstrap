# puppet-bootstrap
Bootstrapping a working and proper Puppet infrastructure for Ubuntu 14.04 server using lxc and gitolite.

The initial motivation for development of those scripts was a need for reliable bootstrapping procedure for "proper", well-encapsulated and secure Puppet environment capable of managing itself and any number of other hosts, including creation of other LXC containers. 

The purpose of these is scripts is to give a new users a quick way of launching their own working Puppet infrastructure, that would be a basis for their own work in the future. The scripts are designed to maintain an existing infrastructure - this job Puppet is better designed to. From the same reasons, the compatibility with legacy systems was never among my priorities - the scripts use quite new, sometimes cutting-edge technologies, like unprivileged LXC or r10k, and are suited only for users of recent (long term supported) Ubuntus who want to start something from scratch. 

# Features
**Modular architecture based on (unprivileged) LXC containers**. [LXC][5] is a operating-system level virtualization technology, that allows all guests to share a single, hosts' kernel.  For security reasons the process favors [unprivileged LXC containers][6] (which at the time of writing this document is a new and quite experimental feature). Both Puppet Master and Gitolite server can be setup on dedicated LXC container (unprivileged or not). They can also be installed together on the same host. 

**Puppet with [puppetdb][1]**. PuppetDB allows for [exported resources][2], which help a lot with tasks that need exchange of information between nodes' manifests. This is useful when one node has information that another node needs in order to manage a resource (the most common example is user management). 

**Version control**. Any module and the whole manifest has a dedicated git repository, that is hosted on [gitolite][4]. The gitolite server can be either shared with puppetmaster, or be managed on discrete host. Pushing to the `puppet-manifest` repository automatically propagates its contents to the puppetmaster.

**r10k and dynamic Puppet environments**. Puppet supports environments - which work like having separate Puppet instances that serve different nodes, but are hosted on common Puppet Master. r10k implements a trick that associates Puppet environments with git's branches. The result is easy and cheap creation of puppet environments. R10k's job is to maintain the link between git's branches and Puppet's environment including downloading any required modules from various sources, using `Puppetfile` with the syntax of [Librarian-puppet][3].

**Many options for import or creation of initial Puppet manifest** The scripts can create a working skeleton manifest, or can use external one. There is also an option to import a existing manifest and rewrite it so the skeleton will be appended on the beginning of its history - this way you will always have the correct templates on each clone of the main manifest.

**Ability to be executed as unprivileged user** Some key commands would require administrative privileges, and will be executed via `sudo`.

# Common patterns in implementation common patterns and debugging
The scripts are written in Bash. Each script is designed with command line parameters handled by Bash itself, preferably using long self-explanatory, double-dash syntax. I tried to use only English names for local variables and comments but occasionally you might find Polish words, which I will correct whenever you contact me. 

The bootstrap process includes downloading a Puppet manifest and its the modules it depends on. The only supported way of transferring the Puppet manifest is via git, because it is so easy to set up and share a git repository using git daemon (the script for managing it: `prepare-git-serving.sh`). 

## Ability to call remote hosts

From time to time one script needs to call another, sometimes requiring the execution on another host. This is accomplished with the means of `rsync`ing the callee scripts (and their dependencies) to the temporary folder on the target machine, and communication via ssh. The necessary key management is done automatically for managed LXC containers, but might require extra work if you want to use the scripts on the external, unmanaged machines.

## Logging the key commands

Most of the code is devoted for sanity checking and command parsing. The actual key commands that do some work are quite few and are carefully encapsulated in one of logging macros, so the command itself and the results of it are logged and never lost.

Each script accepts two common arguments:

* `--debug` Instructs the script, that each dependent script it might call should be interpreted in abbreviated verbose mode (`-x` switch). 

* `--log <logfile>` Instructs the script, that each key command and its result should be appended to the *logfile* on the local machine. As a special case user can specify `--logfile /dev/stdout` with obvious meaning. Both standard output and error output of each key command is appended to the log. 

# Dependencies
The scripts are developed and tested with Ubuntu 14.04, but it is reasonable to assume, that similar distributions (Linux Mint or newer versions of Ubuntu) might work as well. At the moment it is assumed, that the host uses Upstart rather than Systemd. 

Almost everything here is designed to be run with any recent version of Bash. 

# Project status
At this moment the scripts work for me, but they are not well tested against corner cases and are in desperate need for documentation. 

I never done proper testing for setting up privileged LXC (but who would need them, when you have unprivileged LXC?) 

# Example usage:

    bash -- ./bootstrap-puppet-and-friends.sh --gitolite-lxc-name gitolite --gitolite-lxc-ip 10.0.19.107 --gitolite-name gitolite.vam.statystyka.net --user-on-gitolite adas --puppetmaster-lxc-name puppetmaster --puppetmaster-lxc-ip 10.0.19.106 --puppetmaster-name puppetmaster.statystyka.net --user-on-puppetmaster adam --lxc-host-ip 10.0.19.1 --lxc-network 10.0.19.0/24 --lxc-dhcprange 10.0.19.200,10.0.19.254 --lxc-usermode --import-puppet-manifest git://10.0.19.1/manifest --import-git puppet/autostart:git://10.0.19.1/modules/autostart --import-git puppet/lxc:git://10.0.19.1/modules/lxc --import-git puppet/sshauth:git://10.0.19.1/modules/sshauth --log /home/adam/lxc-install.log --dont-merge-manifest-with-template



This example sets up the following things:
* The `lxcbr0` bridged adapter infrastructure.
* Sets up DHCP service on the internal `lxcbr0` network (with leases on range 10.0.19.200 - 10.0.19.254)
* Creates two unprivileged lxc containers for the calling user, one *gitolite* with fqdn *gitolite.vam.statystyka.net* as gitolite server, and another *puppetmaster* (puppetmaster.vam.statystyka.net) as puppetmaster server.
* Installs user *adas* on *gitolite* and user *adam* on puppetmaster, and accepts hosts' user ssh certificate for logging on (leaves password blank, preventing from logging on via password)
* Sets up static, albeit managed by dnsmasq IPs for the hosts (so the IP management is done on host (`/etc/lxc/dnsmasq.conf`), not on each container individually.
* Installs Puppet, PupeptDB, R10k and the dependencies on the *puppetmaster* host. 
* Creates user *puppet* (default name, but can be overridden) for managing internal git clone of manifest repository, together with all necessary hooks.
* Configures gitolite so that puppet@puppetmaster can pull it. It configures [wild repo][7] feature (i.e. user created repos), so that adding a new puppet module to the gitolite can be done without administrative rights. Puppet modules must have prefix `puppet/`. The main puppet manifest has name `puppet/manifest` and has special post-push hooks added, so that pushing into it automatically propagates the contents into the puppetmaster. The host user has admin rights (i.e. it can push into `gitolite@gitolite:gitolite-admin`).
* Imports several modules and the manifest onto the gitolite (the modules must be already served by the host using `prepare-git-serving.sh --repository-base-path $(pwd)`) without any modification of their history. 
* Logs the process onto /home/adam/lxc-install.log
* Accepts the gitolite's and puppetmaster's Puppet Agent certificate with the Puppet Master and runs the `puppet agent --test` on each of them. 




  [1]: https://docs.puppetlabs.com/puppetdb/
  [2]: https://docs.puppetlabs.com/puppet/latest/reference/lang_exported.html
  [3]: https://github.com/rodjek/librarian-puppet
  [4]: http://gitolite.com/gitolite/index.html
  [5]: http://en.wikipedia.org/wiki/LXC
  [6]: https://www.stgraber.org/2014/01/17/lxc-1-0-unprivileged-containers/
  [7]: http://gitolite.com/gitolite/wild.html