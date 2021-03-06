#!/bin/sh

# pfSense master builder script
# (C)2005-2006 Scott Ullrich and the pfSense project
# All rights reserved.
#
# $Id$

# Crank up error reporting, debugging.
#set -e 
#set -x

# Suck in local vars
. ./pfsense_local.sh

# Suck in script helper functions
. ./builder_common.sh

# Make sure cvsup_current has been run first 
check_for_clog

# Output build flags
print_flags

# Allow old CVS_CO_DIR to be deleted later
if [ -d $CVS_CO_DIR ]; then 
	chflags -R noschg $CVS_CO_DIR
fi 

# Use pfSense.6 as kernel configuration file
if [ $FREEBSD_VERSION = "6" ]; then
	export KERNELCONF=${KERNELCONF:-"${PWD}/conf/pfSense.6"}
fi
if [ $FREEBSD_VERSION = "7" ]; then
	export KERNELCONF=${KERNELCONF:-"${PWD}/conf/pfSense.7"}
fi

# If a embedded build has been performed we need to nuke
# /usr/obj.pfSense/ since full uses a different
# make.conf
if [ -f /usr/obj.pfSense/pfSense_wrap.6.world.done ]; then
	echo -n "Removing /usr/obj* since embedded build performed prior..."
	rm -rf /usr/obj.pfSense/*
	echo "done."
fi

# Use normal make.conf
if [ $FREEBSD_VERSION = "6" ]; then
	export MAKE_CONF="${PWD}/conf/make.conf"
	export MAKE_CONF_INSTALL="${PWD}/conf/make.conf"	
	export MAKE_CONF_INSTALL="${PWD}/conf/make.conf"
fi
if [ $FREEBSD_VERSION = "7" ]; then
	export MAKE_CONF="${PWD}/conf/make.conf.7"
	export SRC_CONF="${PWD}/conf/make.conf.7"
	export SRC_CONF_INSTALL="${PWD}/conf/make.conf.7.install"
fi

# Add etcmfs and rootmfs to the EXTRA plugins used by freesbie2
export EXTRA="${EXTRA:-} rootmfs varmfs etcmfs"

if [ ! -z "${CUSTOM_REMOVE_LIST:-}" ]; then
	echo ">>> Using ${CUSTOM_REMOVE_LIST:-} ..."
	export PRUNE_LIST="${CUSTOM_REMOVE_LIST:-}"
else
	if [ $FREEBSD_VERSION = "6" ]; then
		echo ">>> Using ${PWD}/remove.list.iso ..."	
		export PRUNE_LIST="${PWD}/remove.list.iso"
	fi
	if [ $FREEBSD_VERSION = "7" ]; then
		echo ">>> Using ${PWD}/remove.list.iso.7 ..."
		export PRUNE_LIST="${PWD}/remove.list.iso.7"
	fi
fi

# Clean out directories
echo ">>> Cleaning up old directories..."
freesbie_make cleandir

# Checkout a fresh copy from pfsense cvs depot
echo ">>> Updating pfSense CVS depot..."
update_cvs_depot

# Calculate versions
export version_kernel=`cat $CVS_CO_DIR/etc/version_kernel`
export version_base=`cat $CVS_CO_DIR/etc/version_base`
export version=`cat $CVS_CO_DIR/etc/version`

# Invoke FreeSBIE2 toolchain

# Prepare object directry
echo ">>> Preparing object directory..."
freesbie_make obj

# Check for freesbie builder issues
if [ -f ${MAKEOBJDIRPREFIX}/usr/home/pfsense/freesbie2/.tmp_buildworld ]; then
	echo "Something has gone wrong!  Press ENTER to view log file."
	read ans
	more ${MAKEOBJDIRPREFIX}/usr/home/pfsense/freesbie2/.tmp_buildworld
	exit
fi

if [ -f ${MAKEOBJDIRPREFIX}/usr/home/pfsense/freesbie2/.tmp_installworld ]; then
	echo "Something has gone wrong!  Press ENTER to view log file."
	read ans
	more ${MAKEOBJDIRPREFIX}/usr/home/pfsense/freesbie2/.tmp_installworld
	exit
fi

# Build world, kernel and install
echo ">>> Building world and kernels for ISO... $FREEBSD_VERSION  $FREEBSD_BRANCH ..."
make_world

# Build SMP, Embedded (wrap) and Developers edition kernels
echo ">>> Building all extra kernels... $FREEBSD_VERSION  $FREEBSD_BRANCH ..."
build_all_kernels

# Check for freesbie builder issues
if [ -f ${MAKEOBJDIRPREFIX}/usr/home/pfsense/freesbie2/.tmp_kernelbuild ]; then
	echo "Something has gone wrong!  Press ENTER to view log file."
	read ans
	more ${MAKEOBJDIRPREFIX}/usr/home/pfsense/freesbie2/.tmp_kernelbuild 
	exit
fi

# Add extra pfSense packages
echo ">>> Phase install_custom_packages"
install_custom_packages
echo ">>> Phase set_image_as_cdrom"
set_image_as_cdrom

# Fixup library changes if needed
fixup_libmap

# Nuke the boot directory
# [ -d "${CVS_CO_DIR}/boot" ] && rm -rf ${CVS_CO_DIR}/boot

rm -f $BASE_DIR/tools/builder_scripts/conf/packages

echo ">>> Searching for packages..."
set +e # grep could fail
(cd /var/db/pkg && ls | grep bsdinstaller) > $BASE_DIR/tools/builder_scripts/conf/packages
(cd /var/db/pkg && ls | grep grub) >> $BASE_DIR/tools/builder_scripts/conf/packages
(cd /var/db/pkg && ls | grep lua) >> $BASE_DIR/tools/builder_scripts/conf/packages
set -e

echo ">>> Installing packages: " 
cat $BASE_DIR/tools/builder_scripts/conf/packages

rm -f $MAKEOBJDIRPREFIX/usr/home/pfsense/freesbie2/*pkginstall*

# Install custom packages
echo ">>> Installing custom packageas..."
freesbie_make pkginstall

# Add extra files such as buildtime of version, bsnmpd, etc.
echo ">>> Phase populate_extra..."
cust_populate_extra

# Overlay pfsense checkout on top of FreeSBIE image
# using the customroot plugin
echo ">>> Merging extra items..."
freesbie_make extra

# Overlay host binaries
cust_overlay_host_binaries
check_for_zero_size_files

# Check for custom config.xml
cust_install_config_xml

# Install custom pfSense-XML packages from a chroot
pfsense_install_custom_packages_exec

# See if php configuration script is available
if [ -f $PFSENSEBASEDIR/etc/rc.php_ini_setup ]; then
	echo ">>> chroot'ing and running /etc/rc.php_ini_setup"
	chroot $PFSENSEBASEDIR /etc/rc.php_ini_setup
fi

# Prepare /usr/local/pfsense-clonefs
echo ">>> Cloning filesystem..."
freesbie_make clonefs

# Ensure /home exists
mkdir -p $CLONEDIR/home

# Finalize iso
echo ">>> Finalizing iso..."
freesbie_make iso

# Report any zero sized files
report_zero_sized_files
