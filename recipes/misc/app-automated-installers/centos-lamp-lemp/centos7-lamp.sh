#!/bin/bash
#
# Reynaldo R. Martinez P.
# tigerlinux@gmail.com
# http://tigerlinux.github.io
# https://github.com/tigerlinux
# LAMP Server Installation Script
# Rel 1.1
# For usage on centos7 64 bits machines.
#

PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
OSFlavor='unknown'
lgfile="/var/log/lamp-server-automated-installer.log"
credfile="/root/lamp-server-mariadb-credentials.txt"
echo "Start Date/Time: `date`" &>>$lgfile
export debug="no"
# Select your php version: Supported options:
# 56 for "php 5.6"
# 71 for "php" 7.1
# export phpversion="71"
# anything else for "distro" included php version
# export phpversion="standard"
export phpversion="56"

if [ -f /etc/centos-release ]
then
	OSFlavor='centos-based'
	yum clean all
	yum -y install coreutils grep curl wget redhat-lsb-core net-tools git findutils iproute grep openssh sed gawk openssl which xz bzip2 util-linux procps-ng which lvm2 sudo hostname
else
	echo "Nota a centos machine. Aborting!." &>>$lgfile
	echo "End Date/Time: `date`" &>>$lgfile
	exit 0
fi

amicen=`lsb_release -i|grep -ic centos`
crel7=`lsb_release -r|awk '{print $2}'|grep ^7.|wc -l`
if [ $amicen != "1" ] || [ $crel7 != "1" ]
then
	echo "This is NOT a Centos 7 machine. Aborting !" &>>$lgfile
	echo "End Date/Time: `date`" &>>$lgfile
	exit 0
fi

kr64inst=`uname -p 2>/dev/null|grep x86_64|head -n1|wc -l`

if [ $kr64inst != "1" ]
then
	echo "Not a 64 bits machine. Aborting !" &>>$lgfile
	echo "End Date/Time: `date`" &>>$lgfile
	exit 0
fi

export mariadbpass=`openssl rand -hex 10`
export mariadbip='0.0.0.0'

cpus=`lscpu -a --extended|grep -ic yes`
instram=`free -m -t|grep -i mem:|awk '{print $2}'`
avusr=`df -k --output=avail /usr|tail -n 1`
avvar=`df -k --output=avail /var|tail -n 1`

if [ $cpus -lt "1" ] || [ $instram -lt "480" ] || [ $avusr -lt "5000000" ] || [ $avvar -lt "5000000" ]
then
	echo "Not enough hardware for a LAMP Server. Aborting!" &>>$lgfile
	echo "End Date/Time: `date`" &>>$lgfile
	exit 0
fi

setenforce 0
sed -r -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
sed -r -i 's/SELINUX=permissive/SELINUX=disabled/g' /etc/selinux/config
yum -y erase firewalld

if [ `grep -c swapfile /etc/fstab` == "0" ]
then
	myswap=`free -m -t|grep -i swap:|awk '{print $2}'`
	if [ $myswap -lt 2000 ]
	then
		fallocate -l 2G /swapfile
		chmod 600 /swapfile
		mkswap /swapfile
		swapon /swapfile
		echo '/swapfile none swap sw 0 0' >> /etc/fstab
	fi
fi

# Kill packet.net repositories if detected here.
yum -y install yum-utils
repotokill=`yum repolist|grep -i ^packet|cut -d/ -f1`
for myrepo in $repotokill
do
	echo "Disabling repo: $myrepo" &>>$lgfile
	yum-config-manager --disable $myrepo &>>$lgfile
done


yum -y install epel-release
yum -y install yum-utils device-mapper-persistent-data

cat <<EOF >/etc/yum.repos.d/mariadb101.repo
[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/10.1/centos7-amd64
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1
EOF

if [ $debug == "yes" ]
then
	wget http://mirror.gatuvelus.home/cfgs/repos/centos7/mariadb101-amd64.repo -O /etc/yum.repos.d/mariadb101.repo
fi

yum -y update --exclude=kernel*
yum -y install MariaDB MariaDB-server MariaDB-client galera crudini

cat <<EOF >/etc/my.cnf.d/server-lamp.cnf
[mysqld]
binlog_format = ROW
default-storage-engine = innodb
innodb_autoinc_lock_mode = 2
query_cache_type = 0
query_cache_size = 0
bind-address = $mariadbip
max_allowed_packet = 1024M
max_connections = 1000
innodb_doublewrite = 1
innodb_log_file_size = 100M
innodb_flush_log_at_trx_commit = 2
innodb_file_per_table
EOF

mkdir -p /etc/systemd/system/mariadb.service.d/
mkdir -p /etc/systemd/system/mariadb.service.d/
cat <<EOF >/etc/systemd/system/mariadb.service.d/limits.conf
[Service]
LimitNOFILE=65535
EOF

cat <<EOF >/etc/security/limits.d/10-mariadb.conf
mysql hard nofile 65535
mysql soft nofile 65535
EOF

systemctl --system daemon-reload

systemctl enable mariadb.service
systemctl start mariadb.service

cat<<EOF >/root/os-db.sql
UPDATE mysql.user SET Password=PASSWORD('$mariadbpass') WHERE User='root';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY '$mariadbpass' WITH GRANT OPTION;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF

mysql < /root/os-db.sql

cat<<EOF >/root/.my.cnf
[client]
user = "root"
password = "$mariadbpass"
host = "localhost"
EOF

chmod 0600 /root/.my.cnf

rm -f /root/os-db.sql

echo "Database credentials:" > $credfile
echo "User: root" >> $credfile
echo "Password: $mariadbpass" >> $credfile
echo "Listen IP: $mariadbip" >> $credfile

case $phpversion in
56)
	yum -y install centos-release-scl
	yum -y update --exclude=kernel*
	yum -y erase php-common
	yum -y install httpd rh-php56 rh-php56-php rh-php56-php-gd rh-php56-php-mbstring \
	rh-php56-php-mysqlnd rh-php56-php-ldap rh-php56-php-pecl-memcache \
	rh-php56-php-pdo rh-php56-php-xml rh-php56-php-cli

	rm -f /etc/httpd/conf.d/php.conf
	rm -f /etc/httpd/conf.modules.d/10-php.conf
	rm -f /etc/php.ini
	cp /opt/rh/httpd24/root/etc/httpd/conf.d/rh-php56-php.conf /etc/httpd/conf.d/
	cp /opt/rh/httpd24/root/etc/httpd/conf.modules.d/10-rh-php56-php.conf /etc/httpd/conf.modules.d/
	cp /opt/rh/httpd24/root/etc/httpd/modules/librh-php56-php5.so /etc/httpd/modules/
	bash /opt/rh/rh-php56/register
	scl enable rh-php56 bash
	cat /opt/rh/rh-php56/enable > /etc/profile.d/php56-profile.conf
	source /etc/profile.d/php56-profile.conf
	ln -sf 	/etc/opt/rh/rh-php56/php.ini /etc/php.ini
	ln -sf `which php` /usr/local/bin/php
	;;
71)
	yum -y install https://mirror.webtatic.com/yum/el7/webtatic-release.rpm
	yum -y update --exclude=kernel*
	yum -y erase php-common
	yum -y install httpd mod_php71w php71w php71w-opcache \
	php71w-pear php71w-pdo php71w-xml php71w-pdo_dblib \
	php71w-mbstring php71w-mysql php71w-mcrypt php71w-fpm \
	php71w-bcmath php71w-gd php71w-cli
	;;
*)
	yum -y update --exclude=kernel*
	yum -y install httpd php-common mod_php php-pear php-opcache \
	php-pdo php-mbstring php-mysqlnd php-xml php-bcmath \
	php-json php-cli php-gd
	;;
esac

crudini --set /etc/php.ini PHP upload_max_filesize 100M
crudini --set /etc/php.ini PHP post_max_size 100M


cat <<EOF >/var/www/html/index.html
<!DOCTYPE html>
<html>
<body>
<h1>LAMP SERVER READY!!!</h1>
<p>This is a TEST page</p>
</body>
</html>
EOF

cat <<EOF > /var/www/html/info.php
<?php phpinfo(); ?>
EOF

systemctl enable httpd
systemctl restart httpd

finalcheck=`curl --write-out %{http_code} --silent --output /dev/null http://127.0.0.1/info.php|grep -c 200`

if [ $finalcheck == "1" ]
then
	echo "Ready. Your LAMP Server is ready. See your database credentiales at $credfile" &>>$lgfile
	echo "" &>>$lgfile
	cat $credfile &>>$lgfile
	echo "End Date/Time: `date`" &>>$lgfile
else
	echo "LAMP Server install failed" &>>$lgfile
	echo "End Date/Time: `date`" &>>$lgfile
fi

# END