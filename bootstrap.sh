#!/bin/sh
git clone -b zodbupdate-2525 git@github.com:plone/buildout.coredev.git

# for py 2.7
cd py2
virtualenv -p /usr/bin/python2.7 --clear .
./bin/pip install -r ../buildout.coredev/requirements.txt
./bin/buildout -N

# for py3.6
cd ../py3
#this results in an error https://askubuntu.com/questions/958303/unable-to-create-virtual-environment-with-python-3-6 on my ubuntu installation
#python3.7 -m venv .
#old style virtualenv
virtualenv --python=python3.6 --clear .
./bin/pip install -r ../buildout.coredev/requirements.txt
./bin/buildout -N
