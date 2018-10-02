ZODB Upgrade Tests
==================

Setup and documentation for testing migration of ZODB from python2 to python3

(see https://github.com/plone/Products.CMFPlone/issues/2525 for details and discussions)



Setup
-----

use https://github.com/frisi/coredev52multipy/tree/zodbupdate to setup a plone5.2 coredev buildout for python2 and python3 in parallel
that also installs the necessary dependencies/scripts and checks out packages having the `[zodbupdate.decode]` entry point.

::

    ./bootstrap


Create sample content with python2:


py2/bin/instance fg

* create folder with umlauts in title and description
  http://localhost:8080/Plone/test-folder Test Földer

* create image, file in there (to test blobstorage)

* create site in there
  add site as default page of portal

* create user frisi with password frisi


backup database and blobstorage (to run migration multiple times)::

    cp py2/var/filestorage/Data.fs py2/var/filestorage/Data.fs-unmigrated
    cp -a py2/var/blobstorage py2/var/blobstorage-unmigrated


Try migration
-------------


Analyze existing objects in the ZODB and list classes with missing `[zodbupdate.decode]` mapping for
attributes containing string values that could possibly break when converted to python3

::

    py2/bin/zodb-py3migrate-analyze py2/var/filestorage/Data.fs -b py2/var/blobstorage -v



Run Migration:

Copy Database to the py3 instance and migrate it there in place


::

    cp py2/var/filestorage/Data.fs-unmigrated py3/var/filestorage/Data.fs
    rm -rf py3/var/blobstorage; cp -a py2/var/blobstorage-unmigrated/ py3/var/blobstorage
    py2/bin/zodbupdate --pack --convert-py3 --file py3/var/filestorage/Data.fs


Startup py3 instance and see what worked and what not


::

    py3/bin/instance fg



Test protocol
'''''''''''''

XXX document tests/problems and possible solutions as checkbox list in
https://github.com/plone/Products.CMFPlone/issues/2525


* login

