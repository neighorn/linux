# Restrictions used to control access to Tech Support documents.
        Satisfy Any
# Allow based on IP addres for internal servers.
        order deny,allow
	deny from all
	allow from 127.0.0.1/8
# Brian Martin
        allow from 50.35.30.132/31
# Password authentication for other locations.
	AuthName "Tech Support Documents"
	AuthType Basic
	AuthUserFile /usr/local/etc/apache2/passwd/password
	require valid-user
