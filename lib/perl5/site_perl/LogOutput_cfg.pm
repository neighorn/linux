#! /usr/bin/perl
#
# Copyright (c) 2005, Martin Consulting Services, Inc.
# Licensed under the Lesser Gnu Public License (LGPL).
# 
# ABSOLUTELY NO WARRENTIES EXPRESSED OR IMPLIED.  ANY USE OF THIS
# CODE IS STRICTLY AT YOUR OWN RISK.
#
use strict;
package	LogOutput_cfg;
require	Exporter;

our @ISA	= qw(Exporter);
our @EXPORT	= qw(LogOutput_cfg);
our @EXPORT_OK	= qw();
our $Version	= 3.0;

sub LogOutput_cfg {

# Insert name of mail server here.
my($MailServer)="mail.in.silverflash.net";

# Insert your mail domain (i.e. "example.com" if your mail comes from
# joe@example.com) here.  An @ and this value are appended to any e-mail
# addresses that don't contain a mail domain (i.e. mail addressed to "joe" gets
# readdressed to "joe@example.com).
my($MailDomain)="MartinConsulting.com";

# Pass back the machine that handles our mail, and our domain name.
warn "MailServer has not been set in LogOutput_cfg.\n" unless ($MailServer);
warn "MailDomain has not been set in LogOutput_cfg.\n" unless ($MailDomain);

return ({
	MAIL_SERVER => $MailServer,
	MAIL_DOMAIN => $MailDomain,
	# Insert other defaults here, as needed.
	MAIL_LIMIT => 4000,
});
}
1;
