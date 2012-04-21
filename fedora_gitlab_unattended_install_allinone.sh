#!/bin/sh 

# This script has been customised based on a CENTOS 6.2 box. We need the EPEL repos for this to work as required.

# Define the version of ruby and the environment that we are installing for

export RUBY_VERSION=ruby-1.9.2-p290
export RAILS_ENV=production 

# Check our OS version/Flavour - We only care if we are RHEL/CENTOS/Fedora - All others will fail
#
# - Lightly shoplifted from here - https://github.com/coto/server-easy-install/blob/master/lib/core.sh - Thanks coto :-)

if [ -f /etc/redhat-release ] ; then
		DIST=`cat /etc/redhat-release |sed s/\ release.*//`
		RELEASENAME=`cat /etc/redhat-release | sed s/.*\(// | sed s/\)//`
		REV=`cat /etc/redhat-release | sed s/.*release\ // | sed s/\ .*//`
		else
		echo "This is not a Redhat/Fedora system - This script will provide you no love."
		exit 0
fi


# Test if we are Fedora and if not, install the EPEL repo
# Right now I only care about RHEL/CENTOS 6, 
# if you are 5, then you are on your own as this may not get the right libs, 
# but the build *should* function

if [ "$DIST" != 'Fedora' ]
	then 
	echo 'Installing the EPEL repo.' 
	/bin/rpm -Uvh http://download.fedoraproject.org/pub/epel/6/i386/epel-release-6-5.noarch.rpm
fi

# Make sure that we have a colletion of things istalled - These are needed to build the various components- I aint testing for any exceptions... You best be vigilant.

echo 'installing the required libs and packages' 

yum install -y \
make \
libtool \
openssh-clients \
gcc \
libxml2 \
libxml2-devel \
libxslt \
libxslt-devel \
python-devel \
wget \
readline-devel \
ncurses-devel \
gdbm-devel \
glibc-devel \
tcl-devel \
openssl-devel \
db4-devel \
byacc \
httpd \
gcc-c++ \
curl-devel \
openssl-devel \
zlib-devel \
httpd-devel \
apr-devel \
apr-util-devel \
sqlite-devel \
libicu-devel \
gitolite \
redis \
sudo \
postfix \
mysql-devel

# Lets get some user and other general Admin shite out of the way.

# add a user, make them a system user - call them git.

echo 'Creating the git user' 
/usr/sbin/adduser -r -m --shell /bin/bash --comment 'git version control' git

# Create our ssh key as the git user - lets not mess with this too much

ssh-keygen -q  -N '' -t rsa -f /home/git/.ssh/id_rsa

# Ensure correct ownership

/bin/chown git:git -R /home/git/.ssh 

# Make sure that the perms are correct against the .ssh dir

/bin/chmod 0700 /home/git/.ssh


# Exit from the git user once done

# Righto - GitlabHQ and Gitolite integration stuff - We need for the user that runs the webserver to have access to the gitolite admin repo
# we will be adding and removing permissions on this repo.   
# We already have the git user who is the owner of the repo, so we clone his key to make life easier.
# This may not be best practice - but y'know without being too complex this is functional.

# Apache may have to run some things in a shell.  I hate this

echo 'providing apache with a ssh key and permissions to the repositories' 

/usr/sbin/usermod -s /bin/bash -d /var/www/ -G git apache

# Create the keydir for the webserver user (apache)

mkdir /var/www/.ssh

# Copy the git users key, chown that stuff

cp -f /home/git/.ssh/id_rsa* /var/www/.ssh/ && chown apache:apache /var/www/.ssh/id_rsa* && chmod 600 /var/www/.ssh/id_rsa*

# As we will be looping back to localhost only, we grab the local key to avoid issues when its unattended.

/usr/bin/sudo -u apache ssh-keyscan localhost >> /var/www/.ssh/known_hosts

# Apparently we like to be sure who owns what.

/bin/chown apache:apache -R /var/www/.ssh

#END OS SETUP STUFF#

# Lets configure GitlabHQ and gitolite to do our bidding.  

# Change the default umask in gitolite so that repos get created with permissions that allow apache to read them
# Otherwise you will get issues with commits/code/whateveryouexpect not showing up.
# N.B. We make this change against the *example*  config file. 
sed -i 's/0077/0007/g' /usr/share/gitolite/conf/example.gitolite.rc

# Do the heavy lifting.  Configure gitolite and make git the primary admin.

echo 'Setting up Gitolite' 

su - git -c "gl-setup -q /home/git/.ssh/id_rsa.pub"

# Cause we are paranoid about ownership, pimp slap that shit.
  
/bin/chown -R git:git /home/git/
/bin/chmod 770 /home/git/repositories/
/bin/chmod 770 /home/git/
/bin/chmod 600 -R /home/git/.ssh/
/bin/chmod 700 /home/git/.ssh/
/bin/chmod 600 /home/git/.ssh/authorized_keys


# Install Ruby using the RVM method.  This has caused me pain in the past.
# The following is direct from the RVM doc set 
# I suspect that I need to punch ruby in the face.
# Apparently my Great Aunt was called Ruby and she was a very nice lady.

echo 'Insalling RVM' 

curl -o /tmp/rvm-installer https://raw.github.com/wayneeseguin/rvm/master/binscripts/rvm-installer

sh /tmp/rvm-installer --branch stable

# Source the RVM vars

source /etc/profile.d/rvm.sh

# Install Ruby via the RVM wrapper

echo 'Installing Ruby' 

rvm install $RUBY_VERSION

# Use thie ruby

rvm use $RUBY_VERSION --default

# Update the core Gems system (As root)

echo ' Upgrading core Gems' 

gem update --system --no-rdoc --no-ri

# Install some core gems system wide

echo ' System wide install of core gems' 

gem install rails passenger rake bundler grit --no-rdoc --no-ri

# Install pip from the python thing - There are no pip packages for RHEL/CENTOS that I trust anyways.

echo ' Installing Python requirements' 

curl http://python-distribute.org/distribute_setup.py | python
easy_install pip

# Install Python Pygments - Allowing for some nice code highlighting??

pip install pygments

# Clone the gitlabHQ sources to our desired location

echo ' Installing GitlabHQ' 

cd /var/www && git clone https://github.com/owindsor/gitlabhq.git

# Lets change to the git user, source the rvm crud again and execute bundle

cd /var/www/gitlabhq && bundle install

# Exit back to root

rvm all do passenger-install-apache2-module -a

# Clean up after ourselves

rm /tmp/rvm-installer

echo 'DONE initial setup'


##
#  Database setup
#

# Before we do anything, make sure that redis is started

/etc/init.d/redis start
chkconfig redis on

# Lets build the DB and some other jazz
# Do this as the apache user - else shit gets weird

cd /var/www/gitlabhq

source /etc/profile.d/rvm.sh

# Use SQLite
cp config/database.yml.sqlite config/database.yml

rvm all do rake db:setup RAILS_ENV=production
rvm all do rake db:seed_fu RAILS_ENV=production

##
# Finish the setup
#

export PASSENGER_VERSION=`find /usr/local/rvm/gems/$RUBY_VERSION/gems -type d -name "passenger*" | cut -d '-' -f 4`

# Shove everything in to a vhost - I hate Passenger config in the main, it gets in my way
echo -e "<VirtualHost *:80>\nServerName `hostname --fqdn`\nDocumentRoot /var/www/gitlabhq/public\nLoadModule passenger_module /usr/local/rvm/gems/$RUBY_VERSION/gems/passenger-$PASSENGER_VERSION/ext/apache2/mod_passenger.so\n   PassengerRoot /usr/local/rvm/gems/$RUBY_VERSION/gems/passenger-3.0.11\nPassengerRuby /usr/local/rvm/wrappers/$RUBY_VERSION/ruby\n<Directory /var/www/gitlabhq/public>\nAllowOverride all\nOptions -MultiViews\n</Directory>\n</VirtualHost>" > /etc/httpd/conf.d/gitlabhq.conf


# Ensure that apache owns all of gitlabhq - No shallower
chown -R apache:apache /var/www/gitlabhq

# permit apache the ability to write gem files if needed..  To be reviewed.
chown apache:root -R /usr/local/rvm/gems/

# Allow group access the git home dir - Allows apache in the door
chmod 770 /home/git/
chmod go-w /home/git/

# Slap selinux upside the head
setenforce 0
sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config

# Mod iptables - Allow port 22 and 80 in
sed -i '/--dport 22/ a\-A INPUT -m state --state NEW -m tcp -p tcp --dport 80 -j ACCEPT' /etc/sysconfig/iptables

#Restart iptables.
service iptables restart

# Add httpd to start and start the service
chkconfig httpd on
service httpd start