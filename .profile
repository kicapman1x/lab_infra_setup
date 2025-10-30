##infra##
export CERTS_DIR='/home/daddy/apps/lab_infra/ssl/certs'
export LDAP_HOME='/home/daddy/apps/lab_infra/ldap/apacheds-2.0.0.AM28-SNAPSHOT'

alias startldap='$LDAP_HOME/bin/apacheds.sh start'
alias stopldap='$LDAP_HOME/bin/apacheds.sh stop'

alias mldapsearch='ldapsearch -H ldap://ldap.han.gg:10389 -D "uid=admin,ou=system" -w "$(grep admin_password $SECRETS_DIR/ldap_cred | cut -d"=" -f2)"'
