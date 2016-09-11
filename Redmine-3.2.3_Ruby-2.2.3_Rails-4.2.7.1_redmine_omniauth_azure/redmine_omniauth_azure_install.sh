#!/bin/sh
#
# redmine_omniauth_azure_install.sh
#
# Description:
#   Redmine3.3とAzureADプラグインの一発インストーラ
#
# Lang:
#   UTF-8
#
# Argument:
#   なし
#
# Create 2016/08/21 yoko3st@gmail.com
# Update 2016/09/04 yoko3st@gmail.com echoするコメントについて/etc/init.d/functionsを参考に色付。改行位置を各ステップ末尾に移動。
#
#################################################

# 前提：CentOS7、最小限インストール、インストール直後、root実行

# yumアップデート
echo -e "\nyumアップデート"
yum update -y

# SELinux無効化
echo -e "\nSELinux無効化"
setenforce 0
cp -np /etc/selinux/config{,.orig}
sed -i -e "s/=enforcing/=disabled/g" /etc/selinux/config
diff /etc/selinux/config{,.orig}

# firewalld許可
echo -e "\nfirewalld許可"
firewall-cmd --zone=public --add-service=http --permanent && firewall-cmd --reload

# 前提パッケージインストール
echo -e "\n前提パッケージインストール"
yum -y groupinstall "Development Tools" && \
yum -y install openssl-devel readline-devel zlib-devel curl-devel libyaml-devel libffi-devel && \
yum -y install httpd httpd-devel && \
yum -y install ImageMagick ImageMagick-devel ipa-pgothic-fonts ; echo $?

# rbenvインストール
echo -e "\nrbenvインストール"
git clone https://github.com/sstephenson/rbenv.git /opt/rbenv && \
git clone https://github.com/sstephenson/ruby-build.git /opt/rbenv/plugins/ruby-build && \
echo 'export RBENV_ROOT="/opt/rbenv"' > /etc/profile.d/rbenv.sh && \
echo 'export PATH="${RBENV_ROOT}/bin:${PATH}"' >> /etc/profile.d/rbenv.sh && \
echo 'eval "$(rbenv init -)"' >> /etc/profile.d/rbenv.sh && \
source /etc/profile.d/rbenv.sh
rbenv --version || exit 1

# Rubyインストール
echo -e "\nRubyインストール"
rbenv install 2.2.3 && \
rbenv global 2.2.3 && \
ruby -v || exit 1

# bundlerインストール
echo -e "\nbundlerインストール"
gem install bundler --no-rdoc --no-ri || exit 1

# MariaDBインストール
echo -e "\nMariaDBインストール"
yum -y install mariadb-server mariadb-devel && \
cp -np /etc/my.cnf{,.orig}
sed -i -e "/instructions/a character-set-server=utf8" /etc/my.cnf
echo "" >> /etc/my.cnf
echo "[mysql]" >> /etc/my.cnf
echo "default-character-set=utf8" >> /etc/my.cnf
diff /etc/my.cnf{,.orig}
service mariadb start
systemctl enable mariadb
mysql -uroot -e'show variables like "character_set%";'
mysqladmin -V || exit 1

# Redmine用データベースとユーザー作成
echo -e "\nRedmine用データベースとユーザー作成"
REDMINE_DBUSER_PASSWORD=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 32 | head -1`
echo REDMINE_DBUSER_PASSWORD:${REDMINE_DBUSER_PASSWORD} >> ~/redmine_omniauth_azure_install.`date +%Y%m%d`.tmp
mysql -uroot -e'create database db_redmine default character set utf8;'
mysql -uroot -e"grant all on db_redmine.* to user_redmine@localhost identified by \"$REDMINE_DBUSER_PASSWORD\";"
mysql -uroot -e'flush privileges;'
mysql -uroot -e'select Host,User from mysql.user;'

# Redmineインストール
echo -e "\nRedmineインストール"
svn co http://svn.redmine.org/redmine/branches/3.2-stable /var/lib/redmine
echo "production:" > /var/lib/redmine/config/database.yml
echo "  adapter: mysql2" >> /var/lib/redmine/config/database.yml
echo "  database: db_redmine" >> /var/lib/redmine/config/database.yml
echo "  host: localhost" >> /var/lib/redmine/config/database.yml
echo "  username: user_redmine" >> /var/lib/redmine/config/database.yml
echo "  password: ${REDMINE_DBUSER_PASSWORD}" >> /var/lib/redmine/config/database.yml
echo "  encoding: utf8" >> /var/lib/redmine/config/database.yml
chmod 600 /var/lib/redmine/config/database.yml
cd /var/lib/redmine
bundle install --without development test --path vendor/bundle || exit 1

# Redmine初期設定および初期データ登録
echo -e "\nRedmine初期設定および初期データ登録"
bundle exec rake generate_secret_token && \
RAILS_ENV=production bundle exec rake db:migrate && \
RAILS_ENV=production REDMINE_LANG=ja bundle exec rake redmine:load_default_data || exit 1

# Passengerインストール
echo -e "\nPassengerインストール"
gem install passenger --no-rdoc --no-ri && \
passenger-install-apache2-module --auto && \
passenger-install-apache2-module --snippet || exit 1

# Apache設定
echo -e "\nApache設定"
cat <<EOF > /etc/httpd/conf.d/redmine.conf
<Directory "/var/lib/redmine/public">
Require all granted
</Directory>

EOF
passenger-install-apache2-module --snippet >> /etc/httpd/conf.d/redmine.conf
cat <<EOF >> /etc/httpd/conf.d/redmine.conf

Header always unset "X-Powered-By"
Header always unset "X-Runtime"

PassengerMaxPoolSize 20
PassengerMaxInstancesPerApp 4
PassengerPoolIdleTime 864000
PassengerHighPerformance on
PassengerStatThrottleRate 10
PassengerSpawnMethod smart
PassengerFriendlyErrorPages off
RackBaseURI /redmine
EOF
cat /etc/httpd/conf.d/redmine.conf
chown -R apache:apache /var/lib/redmine
ln -s /var/lib/redmine/public /var/www/html/redmine
apachectl configtest && service httpd start && systemctl enable httpd
ps -ef | grep [h]ttpd

# redmine_omniauth_azureプラグインインストール
echo -e "\nredmine_omniauth_azureプラグインインストール"
cd /var/lib/redmine/plugins/ && \
git clone https://github.com/sohelzerdoumi/redmine_omniauth_azure && \
cd /var/lib/redmine && \
gem install multipart-post jwt multi_json multi_xml faraday oauth2 activerecord-deprecated_finders || exit 1
bundle install --without development test --path vendor/bundle || exit 1
RAILS_ENV=production bundle exec rake redmine:plugins db:migrate || exit 1
service httpd configtest && service httpd start

echo "Finish"
echo "You shoud run the mysql_secure_installation & reboot"
exit 0
