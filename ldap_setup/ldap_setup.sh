#!/bin/bash

wget https://dlcdn.apache.org//directory/apacheds/dist/2.0.0.AM27/apacheds-2.0.0.AM27.tar.gz
tar zxfv apacheds-2.0.0.AM27.tar.gz
wget https://dlcdn.apache.org/directory/studio/2.0.0.v20210717-M17/ApacheDirectoryStudio-2.0.0.v20210717-M17-linux.gtk.x86_64.tar.gz
tar zxfv ApacheDirectoryStudio-2.0.0.v20210717-M17-linux.gtk.x86_64.tar.gz ##i personally dont use studio cause waste time zzz 

#modifying partition
base64 han.gg.txt
#substitute the partition id contextentry

startldap

#test
ldapsearch -H ldap://localhost:10389 -D "uid=admin,ou=system" -w "secret" -b "dc=han,dc=gg" "(objectClass=*)"

#change pw
ldapmodify -H ldap://localhost:10389 -D "uid=admin,ou=system" -w "secret" -f change_password.ldif

#add stuff