`doku2trac` is an extensible shell script for converting your *DokuWiki* pages
into *trac*'s wiki format.

Converting Pages
================
Fetch the source code via git, and you can convert your pages using a few
different techniques:

Pipes
-----
Pipes are the Unix mantra. Who doesn't love building a ridiculous pipeline
of commands to get things done with a series of simple tools. doku2trac can
read a *DokuWiki* page from standard-in and write the *trac* page to 
standard-out

    cat /path/to/dokuwiki/data/pages/start.txt | doku2trac

Or even import it directly into trac using `trac-admin`

    cat /path/to/start.txt | doku2trac | trac-admin /path/to/project wiki import <page-name>

Note that some versions of *trac* cannot import from standard-in. This is 
also a pretty convoluded command line.

Multiple Pages
--------------
`doku2trac` can convert multiple pages at once

    doku2trac -d /path/to/dokuwiki start [page2 [...]]

Will write the converted files to standard-out. If you'd like to have the
various converted outputs saved in individual files, you can specify the
output folder with the `-f` option

    doku2trac -d /path/to/dokuwiki start [page2 [...]] -f output

Will write the trac wiki output to individual pages in the `output/` folder
of the current path.

Using Trac-Admin
----------------
Some versions of `trac-admin` don't support importing wiki pages from stdin,
and converting each page in this manner might be a bit laborious, so you can
let `doku2trac` do a little more work.

    doku2trac -t /path/to/trac/project -d /path/to/dokuwiki start

Will convert the *start* page of *DokuWiki* and use `trac-admin` to import it
into trac. The page name will be kept the same and converted to *trac*'s
CamelCase convention.

Direct Database Import
----------------------
Unfortunately, `trac-admin` cannot import wiki page metadata, like author,
modified time, version number, edit comments, etc. So you can directly 
import the wiki pages into the database, with the page metadata as well.
This method is the most risky, so make sure you have a backup of your
data, if any.

Generate SQL statements for use as a script in your favorite database
client

    doku2trac -d /path/to/dokuwiki --sql --meta-data start > trac-wiki.sql

Then you can execute `trac-wiki.sql` in your favorite client for your 
*trac* database.

**Note:** Please be extremely careful when directly modifying *trac*'s
database. You can easily and unexpectedly trash valuable data in your
*trac* project(s)

If you'd like to automatically create **delete** statement to remove any
existing content for the pages before inserting, you can use the 
`--sql-delete` switch, which will emit a delete statement prior to the
insert statement.

I'm a big fan of one-liners. If you're feeling _*really*_ froggy, you can 
pipe the output directly to a database administration tool

    doku2trac -d /path/to/dokuwiki --sql --meta-data start \
        | mysql -u <user> -p -H <host> <db>

You'll be prompted for you database password, and then your wiki file(s)
will be inserted into you *trac* database. Currently this is only 
tested on *trac* version 0.11, but appears to conform to the [database
schema](http://trac.edgewall.org/wiki/TracDev/DatabaseSchema) of
version 0.12.

Options
================
All
---
    -A, --all

Instructs `doku2trac` to convert *all* versions of each page. This is 
mostly useful when using the `--sql` switch, since that is currently the
only method that is useful for importing all the versions of a wiki page
into *trac*.

DokuWiki Path
-------------
    -d, --doku-path <path>

This will specify where your *DokuWiki* install base is rooted. You will
need to give just the root folder of the installation. The script will 
assume that pages are stored in `data/pages` relative to this path.

Exclusions
----------
    --exclude <pattern>

Allows you to exclude certain pages from conversion. For instance, you 
might not want to import the *DokuWiki* playground or syntax pages

    --exclude=playground --exclude=syntax

You can use glob patterns as well

    --exclude=doku*

Logging
-------
    -l, --log <file>

Send the verbose conversion messages to a log file as well as to 
standard-error.

Metadata
--------
    -m, --meta-data

Dump page metadata with the page as well. This will work with any output
method but makes the most sense with the `--sql` switch. Metadata supported
currently includes

    * Doku page name
    * Last modified time
    * Author
    * Source IP address of author
    * Edit comments
    * Trac page name (*)
    * Trac version number (*)

(*) These items are always generated with the `--sql` switch, because the
comprise the primary key for the database.

Page Name Conversion
--------------------
    --page-names <type>

Where `<type>` is one of

    * CamelCase

      This is the default. Pages are converted to *trac*'s 
      CamelCasePageName. A Doku page named `path:to:page_name` will be 
      translated to PathToPageName

    * CamelPath

      This is a hybrid scheme similar to CamelCase, except *DokuWiki*'s
      namespace is preserved. So the `:` part of the page names is converted
      to a `/`. So the page named `path:to:page_name` will be translated
      to `Path/To/PageName`

This conversion affects both page names and links to other wiki pages.

Page Name Prefix
----------------
    --page-name-prefix <name>

This is a prefix to prepend to the name of every *DokuWiki* page converted.
So if you use

    --page-name-prefix=Doku

Then every converted *DokuWiki* page will have a name prefix of `Doku`, so
for instance, the *DokuWiki* start page will become `DokuStart`

Recursion
---------
    -r, --recursive

Recursion will cause `doku2trac` to recurse in the directories (namespaces)
and convert all the containing pages and namespaces.

    doku2trac -d /path/to/dokuwiki -r namespace

Or convert your entire wiki

    doku2trac -d /path/to/dokuwiki -r

Extensions
==========
`doku2trac` was created so that *Trac* extensions or difficult conversion
operations could be implemented as independent modules without clutering
up the main source code.

Table of Contents
-----------------
*DokuWiki* provides an automatic table of contents. *Trac* can supply one
via the *TocMacro* plugin. If you would like to have a table of contents
generated for each of your imported pages, use the *toc* extension

    --auto-toc

**Note:** You will need to install the *TocMacro* plugin for this to 
actually work in *trac*.

Images
------
Images links are automatically converted; however, `trac-admin` does not
provide a mechanism for importing wiki images. Therefore, for now, a warning
is emitted indicating that you need to import the image into trac manually.
