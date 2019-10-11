#!/bin/bash

set -eux

. tests/integration/functions.sh

sudo systemctl restart postgresql || sudo journalctl -xe

git clone --depth 1 https://pagure.io/koji.git

# Create SSL certs
git clone --depth 1 https://pagure.io/koji-tools.git

pushd koji-tools
./src/bin/koji-ssl-admin new-ca --common-name "travisci Koji CA"
./src/bin/koji-ssl-admin server-csr localhost
./src/bin/koji-ssl-admin sign localhost.csr

./src/bin/koji-ssl-admin user-csr travisci
./src/bin/koji-ssl-admin sign travisci.csr

# install client certs
mkdir -p ~/.koji/pki
cp koji-ca.crt ~/.koji/pki
cat travisci.crt travisci.key > travisci.cert
mv travisci.cert ~/.koji/pki/

# install hub certs
sudo cp koji-ca.crt /etc/ssl/certs/
cat localhost.crt koji-ca.crt | sudo tee /etc/ssl/certs/localhost.crt
cat localhost.crt koji-ca.crt | sudo tee /etc/ssl/certs/localhost.crt
sudo mv localhost.key /etc/ssl/private/localhost.key
sudo chown root:ssl-cert /etc/ssl/private/localhost.key
sudo chmod 640 /etc/ssl/private/localhost.key

popd  # koji-tools

# Install/configure Koji client
mkdir -p ~/.koji/config.d/
cp -f tests/integration/travisci.conf ~/.koji/config.d/
sed -e "s?%HOME%?$HOME?g" --in-place ~/.koji/config.d/travisci.conf

# py2 -> py3 submitted upstream at https://pagure.io/koji/pull-request/1748
sed -i -e "s,/usr/bin/python2,/usr/bin/python3,g" koji/cli/koji


# set up koji-hub
sudo a2enmod actions wsgi ssl alias
sudo sed -i -e "s,www-data,$USER,g" /etc/apache2/envvars

# configure apache virtual hosts
sudo cp -f tests/integration/apache.conf /etc/apache2/sites-available/000-default.conf
sudo sed -e "s?%TRAVIS_BUILD_DIR%?$(pwd)?g" --in-place /etc/apache2/sites-available/000-default.conf

# configuration to use our local kojihub Git clone
sed -i -e "s,/usr/share/koji-hub,$(pwd)/koji/hub,g" koji/hub/httpd.conf

sed -i -e "s,#DBHost = .*,DBHost = 127.0.0.1," koji/hub/hub.conf
sed -i -e "s,#DBPass = .*,DBPass = koji," koji/hub/hub.conf
sed -i -e "s,KojiDir = koji,KojiDir = $HOME/mnt/koji," koji/hub/hub.conf

mkdir -p $HOME/mnt/koji

reset_instance

cp tests/integration/ansible.cfg ~/.ansible.cfg

PIP_IGNORE_INSTALLED=0 pip3 install ansible --user
