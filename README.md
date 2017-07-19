# linux
MCSI Linux Tools

General system administration tools, back-up jobs, Perl libraries, etc.

Typically, the repository is cloned to /usr/mcsi/linux, then links are placed in /usr/local/etc/? for the items that are needed
at this site.  For example:

git clone https://github.com/MartinConsultingServicesInc/linux.git /usr/mcsi/linux
ln -s /usr/mcsi/linux/sbin/sysbackup /usr/local/sbin/sysbackup

Note that most of these require that the local Perl library be populated with /usr/mcsi/linux/lib/perl5/site_perl/JobUtils.
