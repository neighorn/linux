#! /bin/bash
##
# Simple script to create standard mrtg index file.  Normally only used
# when /usr/local/etc/mrtg/mrtg.cfg changes.
hostname=`hostname`
hostname=${hostname%%.*}
indexmaker \
	--title="$hostname statistics"				\
	--subtitle='<!--#include file="updated.html" -->'	\
	/usr/local/etc/mrtg/mrtg.cfg				\
	> /usr/local/etc/apache2/pages/mrtg/index.shtml

ln -s /var/mrtg/updated.html /usr/local/etc/apache2/pages/mrtg/updated.html
