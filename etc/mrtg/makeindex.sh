#! /bin/bash
##
# Simple script to create standard mrtg index file.  Normally only used
# when /usr/local/etc/mrtg/mrtg.cfg changes.
hostname=`hostname`
hostname=${hostname%%.*}
indexmaker \
	--title="$hostname statistics"				\
	--subtitle='<!--#include file="updated.htm" -->'	\
	/usr/local/etc/mrtg/mrtg.cfg				\
	> /usr/local/etc/apache2/pages/ts/mrtg/index.shtml
