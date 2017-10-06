import argparse
import logging
import os

parentParser = argparse.ArgumentParser(add_help=False)
parentParser.add_argument("--log","-l", help="File where put execution logs. If not specified, logs will be printed to stdout i stderr", default='proba.log')
parentParser.add_argument("--loglevel", help="Level of logging. Valid values are: DEBUG, INFO (default), WARNING, ERROR.", default='INFO')

parser = argparse.ArgumentParser(description='Configures lxc and lxc-net on the host.',
                                 parents=[parentParser],
                                 usage='%(prog)s [-i|--internalif <internal if name, e.g. lxcbr0>] [-h|--hostip <host ip, e.g. 10.0.14.1>] [-n|--network <network domain, e.g. 10.0.14.0/24>] [--dhcprange <dhcp range, e.g. "10.0.14.3,10.0.14.254">] [--usermode] [--lxc 1|2]')

parser.add_argument("-i", "--internalif", help="internal interface name, e.g. lxcbr0", default='lxcbr0')
parser.add_argument("--hostip", help="host ip, e.g. '10.0.14.1'", default='10.0.14.1')
parser.add_argument("-n","--network", help="network domain, e.g. '10.0.14.0/24'", default='10.0.14.0/24')
parser.add_argument("--dhcprange", help="dhcp range, e.g. '10.0.14.3,10.0.14.254'")
parser.add_argument("--usermode", help="if set, usermode-containers will be setup for the user specified in --usermode-user", action='store_true', default=True)
parser.add_argument("--usermode-user", help="this user will be given privileges to set up user-mode linux containers", default='')

args=parser.parse_args()

from contextlib import contextmanager
@contextmanager
def pushd(newDir):
    previousDir = os.getcwd()
    os.chdir(newDir)
    yield
    os.chdir(previousDir)

import subprocess


def runtimeCondition1(command, args, successValue=0):
    def closure():
        logger.debug("Attempting to check runtime condition of: " + command + ' '.join(args) + ' == ' + str(successValue))
        out = subprocess.run(command + ' ' + ' '.join(args), shell=True, check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        s = command + " returned " + str(out.returncode)
        if out.returncode == successValue:
            logger.info(s + " which is SUCCESS")
            return (True)
        else:
            logger.info(s + " which is FAILURE")
            return (False)
    return(closure)


def executeBashCommand(command, args, executeif, sudo=True):
    if ((executeif and not executeif()) or not executeif ):
        cmdstr=command + ' ' + ' '.join(args)
        if sudo:
            cmdstr='sudo ' + cmdstr
        msg = "Attempting to run '", cmdstr + ("' as root" if sudo else '')
        logger.info(msg)
        out = subprocess.run(cmdstr, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,env={"PATH": "/usr/bin"})
        if out.returncode:
            logger.warning("Command " + command + ' '.join(args) + " returned failure (" + out.check_returncode() + "):")
            for line in str(out.stdout).split('\\n'):
                logger.warning(line)
        else:
            for line in str(out.stdout).split('\\n'):
                logger.info(line)
        return(out.returncode)
    return(0)

def installPackage(packages):
    toinstall=[]
    for package in packages:
        checklxc = runtimeCondition1('dpkg -s', [package])
        if (not checklxc()):
            toinstall+=[package]

    if len(toinstall)>0:
        executeBashCommand('apt install --yes', toinstall, None, sudo=True)


def import_with_auto_install(package, install_name=""):
    import pip
    try:
        return __import__(package)
    except ImportError:
        if (install_name==''):
            logger.debug("Pulling " + package + " python module from the internet")
            install_name = package
        else:
            logger.debug("Pulling " + install_name + " python module from the internet. It will be available under the name " + package)

        pip.main(['install', install_name])
    return __import__(package)


logger = logging.getLogger('configure-lxc')
ch = logging.StreamHandler()
ch.setLevel(logging.WARNING)
logger.addHandler(ch)

if args.log != '':
    ch = logging.FileHandler(filename=args.log)
    logger.setLevel(getattr(logging, args.loglevel.upper()))
    formatter = logging.Formatter(fmt='%(name)s %(asctime)s: %(message)s', datefmt='%d.%m.%Y %H:%M:%S')
    ch.setFormatter(formatter)
    logger.addHandler(ch)


logger.info("configure-lxc called with arguments: " + str(args))

installPackage(['lxc2', 'augeas-tools'])

if args.internalif != "auto":
    executeBashCommand('augtool -L -A --transform ', ['"Shellvars incl /etc/default/lxc-net"', 'set', "/files/etc/default/lxc-net/LXC_BRIDGE", args.internalif], None)
