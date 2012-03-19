sudo apt-get install openssh-server 

sudo adduser \
  --system \
  --shell /bin/sh \
  --gecos 'git version control' \
  --group \
  --disabled-password \
  --home /home/git \
  git

# add your user to git group
sudo usermod -a -G git `eval whoami` 

# copy your pub key to git home
sudo cp ~/.ssh/id_rsa.pub /home/git/rails.pub

# clone gitolite
sudo -u git -H git clone git://github.com/gitlabhq/gitolite /home/git/gitolite

# alter UMASK in gitolite.rc before installing
sudo -u git sed -i 's/0077/0007/g' /home/git/gitolite/conf/example.gitolite.rc

# install gitolite
sudo -u git -H sh -c "PATH=/home/git/bin:$PATH; /home/git/gitolite/src/gl-system-install"

# setup user account in gitolite
sudo -u git -H sh -c "PATH=/home/git/bin:$PATH; gl-setup ~/rails.pub"

# set permission and ownership of the git repositories dir
sudo chmod -R g+rwX /home/git/repositories/
sudo chown -R git:git /home/git/repositories/

echo "Done"
