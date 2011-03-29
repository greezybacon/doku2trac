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
read a doku page from standard-in and write the *trac* page to standard-out

    cat /path/to/dokuwiki/data/pages/start.txt | doku2trac

Or even import it directly into trac using `trac-admin`

    cat /path/to/start.txt | doku2trac | trac-admin wiki import <page-name>

Note that some versions of *trac* cannot import from standard-in

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

    doku2trac -t trac-admin -d /path/to/dokuwiki start

Will convert the *start* page of *Dokuwiki* and use `trac-admin` to import it
into trac. The page name will be kept the same and converted to *trac*'s
CamelCase convention.

**Note:** that if `trac-admin` is not in your `PATH`, you will need to give
the full path of its location

    doku2trac -t /usr/bin/trac-admin -d /path/to/dokuwiki start
