#!/bin/sh
#
# owncloud_install.sh
#
# Description:
#   owncloudの一発インストーラ
#
# Lang:
#   UTF-8
#
# Argument:
#   なし
#
# Create 2016/09/11 yoko3st@gmail.com
#
#################################################

# 前提：CentOS7、最小限インストール、インストール直後、root実行

# yumアップデート
echo "yumアップデート"

yum update -y || exit 1

echo -e "\n\n"


# MariaDBインストール
echo "MariaDBインストール"

yum -y install mariadb mariadb-server && \
cp -np /etc/my.cnf{,.orig} && \
sed -i -e "/instructions/a character-set-server=utf8" /etc/my.cnf && \
diff /etc/my.cnf{,.orig}
systemctl start mariadb && \
systemctl enable mariadb && \
mysqladmin -V || exit 1

echo -e "\n\n"


# ownCloud用データベースとユーザー作成
echo "Redmine用データベースとユーザー作成"

OWNCLOUD_DBUSER_PASSWORD=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 32 | head -1`
echo OWNCLOUD_DBUSER_PASSWORD:${OWNCLOUD_DBUSER_PASSWORD} >> ~/owncloud_install.`date +%Y%m%d`.tmp
mysql -uroot -e'CREATE DATABASE db_owncloud;'
mysql -uroot -e"GRANT ALL ON db_owncloud.* to 'owncloud'@'localhost' IDENTIFIED BY \"$OWNCLOUD_DBUSER_PASSWORD\";"
mysql -uroot -e'flush privileges;'
mysql -uroot -e'select Host,User from mysql.user;'

echo -e "\n\n"


# ownCloudインストール
echo "ownCloudインストール"

curl http://download.owncloud.org/download/repositories/stable/CentOS_7/ce:stable.repo > /etc/yum.repos.d/ce:stable.repo && \
yum install -y owncloud || exit 1
cp -np /etc/php.ini{,.orig} && \
sed -i -e "/^\;date.timezone/a date.timezone = Asia\/Tokyo" /etc/php.ini
systemctl enable httpd && \
systemctl start httpd || exit 1

echo -e "\n\n"


# ownCloud用SELinux設定
echo "ownCloud用SELinux設定"

semanage fcontext -a -t httpd_sys_rw_content_t '/var/www/html/owncloud/data' && \
restorecon '/var/www/html/owncloud/data' && \
semanage fcontext -a -t httpd_sys_rw_content_t '/var/www/html/owncloud/config' && \
restorecon '/var/www/html/owncloud/config' && \
semanage fcontext -a -t httpd_sys_rw_content_t '/var/www/html/owncloud/apps' && \
restorecon '/var/www/html/owncloud/apps'

echo -e "\n\n"


# firewalld許可(とりあえず自分だけ)
echo -e "\nfirewalld許可"

firewall-cmd --permanent --zone=public --add-rich-rule="rule family="ipv4" source address="`who | cut -d\( -f 2 | cut -d\) -f 1`" port protocol="tcp" port="80" accept" && \
firewall-cmd --reload

echo -e "\n\n"


echo "Finish"
echo "You shoud run the mysql_secure_installation & reboot"
exit 0
