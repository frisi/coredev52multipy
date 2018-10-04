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

::

    py2/bin/instance fg

    http://localhost:8080

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

    cp py2/var/filestorage/Data.fs py3/var/filestorage/Data.fs
    rm -rf py3/var/blobstorage; cp -a py2/var/blobstorage/ py3/var/blobstorage
    py2/bin/zodbupdate --pack --convert-py3 --file py3/var/filestorage/Data.fs


Startup py3 instance and see what worked (and what not ;-)


::

    py3/bin/wsgi

    http://0.0.0.0:6543




Debug documentation
-------------------

Root of all evil
''''''''''''''''

To understand the problem that arises when migrating a zodb from python2 to python3,
this `introduction <https://blog.gocept.com/2018/06/07/migrate-a-zope-zodb-data-fs-to-python-3/>`_
and the following example helped me a lot.

(This might be handy information to include in the database migration guide in the plone docs) :


When pickling an object the datatypes and values are stored.

Python2 strings get STRING, and unicode gets UNICODE

::

    $ python2
    Python 2.7.14 (default, Sep 23 2017, 22:06:14)
    >>> di=dict(int=23,str='Ümläut',unicode=u'Ümläut')
    >>> di
    {'int': 23, 'unicode': u'\xdcml\xe4ut', 'str': '\xc3\x9cml\xc3\xa4ut'}
    >>> import pickle
    >>> import pickletools
    >>> pickletools.dis(pickle.dumps(di))
        0: (    MARK
        1: d        DICT       (MARK at 0)
        2: p    PUT        0
        5: S    STRING     'int'
       12: p    PUT        1
       15: I    INT        23
       19: s    SETITEM
       20: S    STRING     'unicode'
       31: p    PUT        2
       34: V    UNICODE    u'\xdcml\xe4ut'
       42: p    PUT        3
       45: s    SETITEM
       46: S    STRING     'str'
       53: p    PUT        4
       56: S    STRING     '\xc3\x9cml\xc3\xa4ut'
       80: p    PUT        5
       83: s    SETITEM
       84: .    STOP
    highest protocol among opcodes = 0

Python3 does not allow non-ascii characters in bytes and the pickle declares
the byte string as SHORT_BINBYTES and the string (py2 unicode) as BINUNICODE

::

    $ python3
    Python 3.6.3 (default, Oct  3 2017, 21:45:48)
    >>> di=dict(int=23,str=b'Ümläut',unicode='Ümläut')
      File "<stdin>", line 1
    SyntaxError: bytes can only contain ASCII literal characters.
    >>> di=dict(int=23,str=b'Umlaut',unicode='Ümläut')
    >>> di
    {'int': 23, 'str': b'Umlaut', 'unicode': 'Ümläut'}
    >>> import pickle
    >>> import pickletools
    >>> pickletools.dis(pickle.dumps(di))
        0: \x80 PROTO      3
        2: }    EMPTY_DICT
        3: q    BINPUT     0
        5: (    MARK
        6: X        BINUNICODE 'int'
       14: q        BINPUT     1
       16: K        BININT1    23
       18: X        BINUNICODE 'str'
       26: q        BINPUT     2
       28: C        SHORT_BINBYTES b'Umlaut'
       36: q        BINPUT     3
       38: X        BINUNICODE 'unicode'
       50: q        BINPUT     4
       52: X        BINUNICODE 'Ümläut'
       65: q        BINPUT     5
       67: u        SETITEMS   (MARK at 5)
       68: .    STOP
    highest protocol among opcodes = 3


When reading a pickle created with python2 with python3 that contains non-ascii
characters in a field declared with OPTCODE `STRING` python3 is trying to interpret it as python3 string (py2 unicode)
and we might end up getting a UnicodeDecodeError for this pickle in ZODB.serialize

::

    $ python3
    >>> b'\xc3\x9cml\xc3\xa4ut'.decode('ascii')
    Traceback (most recent call last):
      File "<stdin>", line 1, in <module>
    UnicodeDecodeError: 'ascii' codec can't decode byte 0xc3 in position 0: ordinal not in range(128)


Or when utf-8 encoded byte-strings are interpreted as unicode we do not get an error but mangled non-ascii characters

::

    $ python3
    >>> print('\xdcml\xe4ut')
    Ümläut
    >>> print('\xc3\x9cml\xc3\xa4ut')
    ÃmlÃ¤ut





how to debug UnicodeDecodeErrors in ZODB.serialize
''''''''''''''''''''''''''''''''''''''''''''''''''

add logging information to ZODB.serialize::

    def getState(self, pickle):
        unpickler = self._get_unpickler(pickle)
        try:
            unpickler.load() # skip the class metadata
            return unpickler.load()
        except EOFError as msg:
            log = logging.getLogger("ZODB.serialize")
            log.exception("Unpickling error: %r", pickle)
            raise
        except UnicodeDecodeError:
            unpickler = self._get_unpickler(pickle)
            log = logging.getLogger("ZODB.serialize")
            log.exception(
                "Unpickling error for class {}, pickle data:\n{}\n".format(
                    unpickler.load(),
                    pickle))
            # by not raising the error here we get a better idea of which
            # component broke in the traceback


Test protocol
-------------


Manager login
'''''''''''''

Users that lived in Zope's acl_users and also Plone/acl_users can't login after
migrating the database to python3.


To get a valid manager user to login again call `py3$ bin/wsgidebug`

    >>> import transaction
    >>> result = app.acl_users._doAddUser('admin2', 'admin2', ['Manager'], [])
    >>> transaction.commit()



To debug the problem, set pdb in `Products.PluggableAuthService.plugins.ZODBUserManager.ZODBUserManager.authenticateCredentials`

::

    # user created on python3 buildot
    (Pdb++) self._user_passwords.get('py3_user')
    b'{SSHA}+PbUAlxU0josF67yU6PT8sMtHRy+AODY9qGB'
    # migrated user
    (Pdb++) self._user_passwords.get('migrated_user')
    '{SSHA}qe2xDYQzuDeWkMAUni+xmtjeK9TJqV1fUXh3'


    btree = plone.restrictedTraverse('acl_users/source_users')._user_passwords


Possible strategies:

* A) Before running zodbmigrate, run a script on plone-site that handles this (@thefunny pointed out he had a script for this, asked him to share it https://github.com/plone/Products.CMFPlone/issues/2525#issuecomment-426546419) :

* B) have entry_point (`[zodbupdate.migratepy3]`) for custom code that executed before migrating blobs in `zodbupdate --convert-py3`
  that can be used for things like this (so packages can provide their own migration routines)

* C) Fix after migration

  - in an upgrade step that is required to be run after the python3 migration documented in the plone docs
  - make usermanager handle both cases at runtime as david suggested https://github.com/plone/Products.CMFPlone/issues/2525#issuecomment-425609483)



error when rendering plonesite
''''''''''''''''''''''''''''''

looks like catalog query leads to the problem::

    2018-10-02 18:33:14,415 ERROR [ZODB.serialize:626][waitress] Unpickling error for class <class 'BTrees.IOBTree.IOBTree'>, pickle data:
    b'\x80\x03cBTrees.IOBTree\nIOBTree\nq\x01.\x80\x03(J\x10\x82\xdcV(U\x192018-10-01T23:25:55+02:00q\x02U\x05adminq\x03U\x192018-10-01T23:25:55+02:00q\x04U\x08uml\xc3\xa4uteq\x05U\x04Noneq\x06h\x06U\x192018-10-01T23:25:55+02:00q\x07)U\x13Seite mit Uml\xc3\xa4utenq\x08czope.i18nmessageid.message\nMessage\nq\t(X\x04\x00\x00\x00Pageq\nU\x05ploneq\x0bNNtRq\x0cU 719cba453179404ea40657bc6359d17fq\rcDateTime.DateTime\nDateTime\nq\x0e)\x81q\x0fGA\xd6\xec\xa48\xd3]:\x89U\x05GMT+2q\x10\x87bh\x0e)\x81q\x11G\xc0\xf6\xda\x00\x00\x00\x00\x00\x89h\x10\x87bcMissing\nV\nq\x12\x89h\x0e)\x81q\x13GB\x0f\'*\x17\x00\x00\x00\x89h\x10\x87bh\x12U\x13seite-mit-umlaeutenq\x14U\x041 KBq\x15h\x12h\x14\x89U\x05adminq\x16\x85h\x12U\x0eDexterity Itemq\x17h\x0e)\x81q\x18GA\xd6\xec\xa48\xd8\x9fZ\x89h\x10\x87bU\x08Documentq\x19U\x07privateq\x1ah\x12U\ntext/plainq\x1bK\x03K\x00N)h\x12h\x12h\x12tq\x1cJ\x079r[(U\x192018-10-01T19:07:02+02:00q\x1dU\x05adminq\x1eU\x192018-10-01T19:07:02+02:00q\x1fUzHerzlichen Gl\xc3\xbcckwunsch! Sie haben das professionelle Open-Source Content-Management-System Plone erfolgreich installiert.q U\x04Noneq!h!U\x192018-10-01T19:07:02+02:00q")U\x14Willkommen bei Ploneq#h\t(X\x04\x00\x00\x00Pageq$U\x05ploneq%NNtRq&U cf32b3fcf37d45a5b68d148cbbbf78c9q\'h\x0e)\x81q(GA\xd6\xec\x95\r\xb1\x90\x8e\x89h\x10\x87bh\x0e)\x81q)G\xc0\xf6\xda\x00\x00\x00\x00\x00\x89h\x10\x87bh\x12\x89h\x0e)\x81q*GB\x0f\'*\x17\x00\x00\x00\x89h\x10\x87bh\x12U\nfront-pageq+U\x061.6 KBq,h\x12h+\x89U\x05adminq-\x85h\x12U\x0eDexterity Itemq.h\x0e)\x81q/GA\xd6\xec\x95\r\xbe\x95!\x89h\x10\x87bU\x08Documentq0U\tpublishedq1h\x12U\ntext/plainq2K\x01K\x00N)h\x12h\x12h\x12tq3J\x089r[(U\x192018-10-01T19:07:02+02:00q4U\x05adminq5U\x192018-10-01T19:07:03+02:00q6U\x0bNachrichtenq7h!h!U\x192018-10-01T19:07:03+02:00q8)U\x0bNachrichtenq9h\t(X\x06\x00\x00\x00Folderq:U\x05ploneq;NNtRq<U 0bb917feced4425c85e71b823887c186q=h\x0e)\x81q>GA\xd6\xec\x95\r\xbe\xa2\x1a\x89h\x10\x87bh)h\x12\x89h*h\x12U\x04newsq?U\x040 KBq@h\x12h?\x88U\x05adminqA\x85h\x12U\x13Dexterity ContainerqBh\x0e)\x81qCGA\xd6\xec\x95\r\xcb>)\x89h\x10\x87bU\x06FolderqDh1h\x12h2h\x12K\x00N)h\x12h\x12h\x12tqEJ\t9r[(U\x192018-10-01T19:07:03+02:00qFU\x05adminqGU\x192018-10-01T19:07:03+02:00qHU\x0bNachrichtenqIh!h!U\x192018-10-01T19:07:03+02:00qJ)U\x0bNachrichtenqKh\t(X\n\x00\x00\x00CollectionqLU\x05ploneqMNNtRqNU 0be7dd5b3ec14a0a8f30f1f871986886qOh\x0e)\x81qPGA\xd6\xec\x95\r\xc4V\x86\x89h\x10\x87bh)h\x12\x89h*h\x12U\naggregatorqQU\x040 KBqRh\x12hQ\x89U\x05adminqS\x85h\x12h.h\x0e)\x81qTGA\xd6\xec\x95\r\xcag\xa5\x89h\x10\x87bU\nCollectionqUh1h\x12h2h\x12K\x00N)h\x12h\x12h\x12tqVJ\n9r[(U\x192018-10-01T19:07:03+02:00qWU\x05adminqXU\x192018-10-01T19:07:03+02:00qYU\x07TermineqZh!h!U\x192018-10-01T19:07:03+02:00q[)U\x07Termineq\\h\t(X\x06\x00\x00\x00Folderq]h;NNtRq^U e635e8d64cc149689017e0bf7668d885q_h\x0e)\x81q`GA\xd6\xec\x95\r\xd0\x8fz\x89h\x10\x87bh)h\x12\x89h*h\x12U\x06eventsqaU\x040 KBqbh\x12ha\x88U\x05adminqc\x85h\x12hBh\x0e)\x81qdGA\xd6\xec\x95\r\xdb(1\x89h\x10\x87bhDh1h\x12h2h\x12K\x00N)h\x12h\x12h\x12tqeJ\x0b9r[(U\x192018-10-01T19:07:03+02:00qfU\x05adminqgU\x192018-10-01T19:07:03+02:00qhU\x07Termineqih!h!U\x192018-10-01T19:07:03+02:00qj)U\x07Termineqkh\t(X\n\x00\x00\x00CollectionqlhMNNtRqmU d65e8b9c64784acd9e8f013b0befeacbqnh\x0e)\x81qoGA\xd6\xec\x95\r\xd5\x08[\x89h\x10\x87bh)h\x12\x89h*h\x12hQU\x040 KBqph\x12hQ\x89U\x05adminqq\x85h\x12h.h\x0e)\x81qrGA\xd6\xec\x95\r\xda\x87w\x89h\x10\x87bhUh1h\x12h2h\x12K\x00N)h\x12h\x12h\x12tqsJ\x0c9r[(U\x192018-10-01T19:07:03+02:00qtU\x05adminquU\x192018-10-01T19:07:03+02:00qvU/Bereich f\xc3\xbcr pers\xc3\xb6nliche Artikel der Benutzer.qwh!h!U\x192018-10-01T19:07:03+02:00qx)U\x08Benutzerqyh\t(X\x06\x00\x00\x00Folderqzh;NNtRq{U b8efe38019924fd3980d0123c0e10f3bq|h\x0e)\x81q}GA\xd6\xec\x95\r\xe06D\x89h\x10\x87bh)h\x12\x89h*h\x12U\x07Membersq~U\x040 KBq\x7fh\x12h~\x88U\x05adminq\x80\x85h\x12hBh\x0e)\x81q\x81GA\xd6\xec\x95\r\xe4\xb3J\x89h\x10\x87bhDU\x07privateq\x82h\x12h2h\x12K\x00N)h\x12h\x12h\x12tq\x83J\r9r[(U\x192018-10-01T19:08:42+02:00q\x84U\x05adminq\x85U\x192018-10-01T23:25:55+02:00q\x86U\x12beschreib\xc3\xbcngstextq\x87h\x06h\x06U\x192018-10-01T23:25:55+02:00q\x88)U\x0cTest F\xc3\xb6lderq\x89h\t(X\x06\x00\x00\x00Folderq\x8aU\x05ploneq\x8bNNtRq\x8cU acd9698b06094a20a0f2996da2474b23q\x8dh\x0e)\x81q\x8eGA\xd6\xec\x95&\xb2\xa2/\x89h\x10\x87bh\x11h\x12\x89h\x13h\x12U\x0btest-folderq\x8fU\x040 KBq\x90h\x12h\x8f\x88U\x05adminq\x91\x85h\x12U\x13Dexterity Containerq\x92h\x0e)\x81q\x93GA\xd6\xec\xa48\xdb\xf0\xfe\x89h\x10\x87bU\x06Folderq\x94U\x07privateq\x95h\x12h\x1bK\x04K\x00N)h\x12h\x12h\x12tq\x96J\x0e9r[(U\x192018-10-01T19:09:47+02:00q\x97U\x05adminq\x98U\x192018-10-01T19:09:47+02:00q\x99U\x00h!h!U\x192018-10-01T19:09:47+02:00q\x9a)U\x0ckleines bildq\x9bh\t(X\x05\x00\x00\x00Imageq\x9cU\x05ploneq\x9dNNtRq\x9eU bd10fc609e95427292dd48ea011661c9q\x9fh\x0e)\x81q\xa0GA\xd6\xec\x956\xf8\xc3\x8b\x89h\x10\x87bh)h\x12\x89h*\x88U\x08user.pngq\xa1U\x061.9 KBq\xa2h\x12h\xa1\x89U\x05adminq\xa3\x85q\xa4h\x12h.h\x0e)\x81q\xa5GA\xd6\xec\x956\xff\x15\xfd\x89h\x10\x87bU\x05Imageq\xa6h\x12h\x12U\timage/pngq\xa7h\x12K\x00N)h\x12h\x12h\x12tq\xa8t\x85\x85\x85q\xa9.'
    Traceback (most recent call last):
      File "~/.buildout/eggs/ZODB-5.3.0-py3.6.egg/ZODB/serialize.py", line 615, in getState
        return unpickler.load()
    UnicodeDecodeError: 'ascii' codec can't decode byte 0xc3 in position 3: ordinal not in range(128)


    2018-10-02 18:33:14,785 ERROR [Zope.SiteErrorLog:250][waitress] 1538497994.771280.5922534063983516 http://0.0.0.0:6543/Plone/front-page/document_view
    Traceback (innermost last):
      Module ZPublisher.WSGIPublisher, line 128, in transaction_pubevents
      Module ZPublisher.WSGIPublisher, line 270, in publish_module
      Module ZPublisher.WSGIPublisher, line 210, in publish
      Module ZPublisher.mapply, line 85, in mapply
      Module ZPublisher.WSGIPublisher, line 57, in call_object
      Module zope.browserpage.simpleviewclass, line 41, in __call__
      Module Products.Five.browser.pagetemplatefile, line 125, in __call__
      Module Products.Five.browser.pagetemplatefile, line 60, in __call__
      Module zope.pagetemplate.pagetemplate, line 134, in pt_render
      Module Products.PageTemplates.engine, line 85, in __call__
      Module z3c.pt.pagetemplate, line 158, in render
      Module chameleon.zpt.template, line 297, in render
      Module chameleon.template, line 203, in render
      Module chameleon.utils, line 75, in raise_with_traceback
      Module chameleon.template, line 183, in render
      Module 5e2f47117949f83762f22aae2b1cdfb6.py, line 246, in render
      Module 8d1253f3a74b3314e551d24932d33e2a.py, line 581, in render_master
      Module z3c.pt.expressions, line 69, in render_content_provider
      Module zope.viewlet.manager, line 111, in update
      Module zope.viewlet.manager, line 117, in _updateViewlets
      Module plone.app.layout.viewlets.common, line 223, in update
      Module Products.CMFPlone.browser.navigation, line 150, in topLevelTabs
      Module ZTUtils.Lazy, line 200, in __getitem__
      Module Products.ZCatalog.Catalog, line 128, in __getitem__
    KeyError: 1534212360


solution: clear and rebuild portal_catalog (after the migration, after first startup of instance running on python3)



Blobs (kind of Solved)
''''''''''''''''''''''

TLDR;

PR is ready, but test needs to be fixed before we can merge it
https://github.com/zopefoundation/zodbupdate/pull/7/files



Uploaded test image is missing the actual image data, an error is logged::

    2018-10-03 10:21:15,750 ERROR [Zope.SiteErrorLog:250][waitress] 1538554875.72902750.17350855738202609 http://0.0.0.0:6543/Plone/test-folder/user.png/image_view
    Traceback (innermost last):
      Module plone.app.portlets.manager, line 54, in safe_render
      Module plone.app.portlets.portlets.navigation, line 371, in render
      ...
      Module plone.namedfile.scaling, line 434, in scale
      Module plone.scale.storage, line 210, in scale
      Module plone.namedfile.scaling, line 217, in __call__
      Module plone.namedfile.file, line 337, in open
      Module ZODB.Connection, line 808, in setstate
      Module ZODB.blob, line 696, in loadBlob
    ZODB.POSException.POSKeyError: ZODB.POSException.POSKeyError: 'No blob file at plone-coredev-52-multipy/py3/var/blobstorage/0x00/0x00/0x00/0x00/0x00/0x00/0x17/0xa0/0x03caada3bcd474aa.blob'


References to blob get lost as Silvain already pointed out (https://github.com/plone/Products.CMFPlone/issues/2525#issuecomment-426047862)



Strategy:

* Skip processing of `ZODB.blob` records in `zodbupdate.update.Updater.__call__`
  so no rename/move of files in var/blobstorage is needed


Background:

blobstorage files correspond to a zodb record

the filename of a blobstorage file (eg: `blobstorage/0x00/0x00/0x00/0x00/0x00/0x00/0x17/0xa0/0x03cab8373063e588.blob`)
is made up of the oid and serial of the database record:

oid: b'\x00\x00\x00\x00\x00\x00\x17\xa0'
serial: b'\x03\xca\xb870c\xe5\x88'



Open for test/analysis
''''''''''''''''''''''

* Propertymanager properties

* annotations








XXX document tests/problems and possible solutions as checkbox list in
https://github.com/plone/Products.CMFPlone/issues/2525


* login
