#!/bin/bash
set -e

MOUNTPATH="/mnt/db"
DB_NAME=${DB_NAME:-"testdb"}
DB_USER=${DB_USER:-"tester"}
DB_PASS=${DB_PASS:-"tester0nly"}

DB_REMOTE_ROOT_NAME=${DB_REMOTE_ROOT_NAME:-}
DB_REMOTE_ROOT_PASS=${DB_REMOTE_ROOT_PASS:-}
DB_REMOTE_ROOT_HOST=${DB_REMOTE_ROOT_HOST:-"172.17.42.1"}

create_data_dir() {
  echo "EXEC: ip addr show"
  ip addr show

  adduser $MYSQL_USER root
  usermod --shell /bin/bash $MYSQL_USER
  echo "Creating Data directory..."
  chmod 775 $MOUNTPATH

  echo "EXEC: su -c \"mkdir -p ${MOUNTPATH}/mysql\" $MYSQL_USER"
  su -c "mkdir -p ${MOUNTPATH}/mysql" $MYSQL_USER
  su -c "chmod 700 ${MOUNTPATH}/mysql" $MYSQL_USER
  echo "EXEC: ls -al ${MOUNTPATH}"
  ls -al ${MOUNTPATH}

  echo "EXEC: ln -sf ${MOUNTPATH}/mysql ${MYSQL_DATA_DIR}"
  ln -sf ${MOUNTPATH}/mysql ${MYSQL_DATA_DIR}
  chown -h ${MYSQL_USER}:${MYSQL_USER} ${MYSQL_DATA_DIR}
  echo "EXEC: ls -al ${MYSQL_DATA_DIR}"
  ls -al ${MYSQL_DATA_DIR}

  deluser $MYSQL_USER root
  chmod 755 $MOUNTPATH
  echo "Created Data directory..."
}

create_run_dir() {
  echo "Creating Run directory..."
  mkdir -p ${MYSQL_RUN_DIR}
  chmod -R 0755 ${MYSQL_RUN_DIR}
  chown -R ${MYSQL_USER}:root ${MYSQL_RUN_DIR}
  echo "Created Log directory..." 
}

create_log_dir() {
  echo "Creating Log directory..."
  mkdir -p ${MYSQL_LOG_DIR}
  chmod -R 0755 ${MYSQL_LOG_DIR}
  chown -R ${MYSQL_USER}:${MYSQL_USER} ${MYSQL_LOG_DIR}
  echo "Created Log directory..." 
}

apply_configuration_fixes() {
  # disable error log
  sed 's/^log_error/# log_error/' -i /etc/mysql/my.cnf

  # Fixing StartUp Porblems with some DNS Situations and Speeds up the stuff
  # http://www.percona.com/blog/2008/05/31/dns-achilles-heel-mysql-installation/
  cat > /etc/mysql/conf.d/mysql-skip-name-resolv.cnf <<EOF
[mysqld]
skip_name_resolve
EOF
}

remove_debian_systen_maint_password() {
  #
  # the default password for the debian-sys-maint user is randomly generated
  # during the installation of the mysql-server package.
  #
  # Due to the nature of docker we blank out the password such that the maintenance
  # user can login without a password.
  #
  sed 's/password = .*/password = /g' -i /etc/mysql/debian.cnf
}

initialize_mysql_database() {
  # initialize MySQL data directory
  if [ ! -d ${MYSQL_DATA_DIR}/mysql ]; then
    echo "Installing database..."
    # mysql_install_db --user=mysql >/dev/null 2>&1
    # mysql_install_db --user=mysql 2>&1
    echo "EXEC: su -c \"mysql_install_db --datadir=${MYSQL_DATA_DIR}\" $MYSQL_USER"
    su -c "mysql_install_db --datadir=${MYSQL_DATA_DIR}" $MYSQL_USER

    # echo "EXEC: mysql_install_db --user=mysql 2>&1"
    # mysql_install_db --user=mysql 2>&1
    echo "EXEC: grep \"^user\" /etc/mysql/my.cnf"
    grep "^user" /etc/mysql/my.cnf
    cp /etc/mysql/my.cnf ./orig_my.cnf
    sed -e 's/^user.*=.*$/user            = mysql/' ./orig_my.cnf > ./mod_my.cnf
    cp ./mod_my.cnf /etc/mysql/my.cnf
    echo "EXEC: grep \"^user\" /etc/mysql/my.cnf"
    grep "^user" /etc/mysql/my.cnf

    # start mysql server
    echo "Starting MySQL server..."
    # /usr/bin/mysqld_safe >/dev/null 2>&1 &
    echo "EXEC: su -c \"/usr/bin/mysqld_safe 2>&1 &\" $MYSQL_USER"
    su -c "/usr/bin/mysqld_safe 2>&1 &" $MYSQL_USER

    echo "EXEC: ls -al /usr/bin/mysqladmin"
    ls -al /usr/bin/mysqladmin
    # wait for mysql server to start (max 30 seconds)
    timeout=60
    echo -n "Waiting for database server to accept connections"
    while ! /usr/bin/mysqladmin -u root status >/dev/null 2>&1
    do
      timeout=$(($timeout - 1))
      echo "EXEC: ps -ef | grep mysql"
      ps -ef | grep mysql
      if [ $timeout -eq 0 ]; then
        echo "EXEC: ps -ef | grep mysql"
        ps -ef | grep mysql
        echo "EXEC: ip addr show"
        ip addr show
        echo "EXEC: netstat -tulpan | grep mysql"
        netstat -tulpan | grep mysql
        cat /var/log/mysql/error.log
        echo -e "\nCould not connect to database server. Aborting..."
        exit 1
      fi
      echo -n "."
      sleep 1
    done
    echo

    ## create a localhost only, debian-sys-maint user
    ## the debian-sys-maint is used while creating users and database
    ## as well as to shut down or starting up the mysql server via mysqladmin
    echo "Creating debian-sys-maint user..."
    mysql -uroot -e "GRANT ALL PRIVILEGES on *.* TO 'debian-sys-maint'@'localhost' IDENTIFIED BY '' WITH GRANT OPTION;"

    if [ -n "${DB_REMOTE_ROOT_NAME}" -a -n "${DB_REMOTE_ROOT_HOST}" ]; then
      echo "Creating remote user \"${DB_REMOTE_ROOT_NAME}\" with root privileges..."
      mysql -uroot \
      -e "GRANT ALL PRIVILEGES ON *.* TO '${DB_REMOTE_ROOT_NAME}'@'${DB_REMOTE_ROOT_HOST}' IDENTIFIED BY '${DB_REMOTE_ROOT_PASS}' WITH GRANT OPTION; FLUSH PRIVILEGES;"
    fi
    echo "EXEC: Stop mysql"
    /usr/bin/mysqladmin --defaults-file=/etc/mysql/debian.cnf shutdown
    sleep 5
  fi
}

create_users_and_databases() {
  # create new user / database
  if [ -n "${DB_USER}" -o -n "${DB_NAME}" ]; then
    # /usr/bin/mysqld_safe >/dev/null 2>&1 &
    echo "EXEC: su -c \"/usr/bin/mysqld_safe 2>&1 &\" $MYSQL_USER"
    su -c "/usr/bin/mysqld_safe 2>&1 &" $MYSQL_USER

    # wait for mysql server to start (max 30 seconds)
    timeout=60
    while ! /usr/bin/mysqladmin -u root status >/dev/null 2>&1
    do
      timeout=$(($timeout - 1))
      echo "EXEC: ps -ef | grep mysql"
      ps -ef | grep mysql
      if [ $timeout -eq 0 ]; then
        echo "EXEC: ps -ef | grep mysql"
        ps -ef | grep mysql
        echo "EXEC: ip addr show"
        ip addr show
        echo "EXEC: netstat -tulpan | grep mysql"
        netstat -tulpan | grep mysql
        cat /var/log/mysql/error.log
        echo "Could not connect to mysql server. Aborting..."
        exit 1
      fi
      sleep 1
    done

    if [ -n "${DB_NAME}" ]; then
      for db in $(awk -F',' '{for (i = 1 ; i <= NF ; i++) print $i}' <<< "${DB_NAME}"); do
        echo "Creating database \"$db\"..."
        mysql --defaults-file=/etc/mysql/debian.cnf \
          -e "CREATE DATABASE IF NOT EXISTS \`$db\` DEFAULT CHARACTER SET \`utf8\` COLLATE \`utf8_unicode_ci\`;"
          if [ -n "${DB_USER}" ]; then
            echo "Granting access to database \"$db\" for user \"${DB_USER}\"..."
            mysql --defaults-file=/etc/mysql/debian.cnf \
            -e "GRANT ALL PRIVILEGES ON \`$db\`.* TO '${DB_USER}' IDENTIFIED BY '${DB_PASS}';"
          fi
        done
    fi
    echo "EXEC: Stop mysql"
    /usr/bin/mysqladmin --defaults-file=/etc/mysql/debian.cnf shutdown
    sleep 5
  fi
}

listen_on_all_interfaces() {
  cat > /etc/mysql/conf.d/mysql-listen.cnf <<EOF
[mysqld]
bind = 0.0.0.0
EOF
}

create_data_dir
create_run_dir
create_log_dir

timeout=60
while [[ $timeout -gt 0 ]]; do
   timeout=$(($timeout - 1))
   cnt=$(ip link show | wc -l)
   if [[ $cnt -lt 4 ]]; then
      echo "Wait for eth inetrface"
      sleep 1
   else
      timeout=-1
      echo "EXEC: ip addr show"
      ip addr show
   fi
done

# allow arguments to be passed to mysqld_safe
if [[ ${1:0:1} = '-' ]]; then
  EXTRA_ARGS="$@"
  set --
elif [[ ${1} == mysqld_safe || ${1} == $(which mysqld_safe) ]]; then
  EXTRA_ARGS="${@:2}"
  set --
fi

# default behaviour is to launch mysqld_safe
if [[ -z ${1} ]]; then
  apply_configuration_fixes
  remove_debian_systen_maint_password
  initialize_mysql_database
  create_users_and_databases
  listen_on_all_interfaces
  echo "EXEC: su -c \"$(which mysqld_safe) $EXTRA_ARGS\" $MYSQL_USER"
  #exec su -c "$(which mysqld_safe) $EXTRA_ARGS" $MYSQL_USER 
  su -c "$(which mysqld_safe) $EXTRA_ARGS" $MYSQL_USER 
else
  echo "EXEC: su -c \"$@\" $MYSQL_USER"
  #exec su -c "$@" $MYSQL_USER
  su -c "$@" $MYSQL_USER
fi
cat /var/log/mysql/error.log 

