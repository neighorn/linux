# Allow based on IP addres for internal servers.
   	#Require all granted
        Require IP 50.35.30.132/31 127.0.0.0/8
# Password authentication for other locations.
	AuthName "Tech Support Documents"
	AuthType Basic
	AuthUserFile /usr/local/etc/apache2/passwd/password
	require valid-user
