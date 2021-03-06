#!/usr/bin/perl

use strict;
use warnings;

use Filesys::SmbClient;
use Data::Dumper;

my $DEBUG = 0;
my $USERNAME = 'cms_rohdedan';
my $PASSWORD = '';
my $WORKGROUP = 'CMS';
my $BASEURI = 'smb://hucms11c.cms.hu-berlin.de/home/Abt4/cms_rohdedan/';
my $FLAGS = Filesys::SmbClient::SMB_CTX_FLAG_USE_KERBEROS;

my ($r,@a,$f,$d,$c);
$c = Filesys::SmbClient(username=>$USERNAME, password=>$PASSWORD, workgroup=>$WORKGROUP,flags=>$FLAGS,debug=>$DEBUG )->new();


$d = $c->opendir($BASEURI);
print "opendir($BASEURI): $d\n";
@a = $c->readdir_struct($d);
print Dumper(\@a);
$c->closedir($d);


$r = $c->mkdir($BASEURI.'test2');
print "mkdir(${BASEURI}test2): $r\n";

### write content + stat:
$f = $c->open(">${BASEURI}test2/super.txt");
print "open(>${BASEURI}test2/super.txt): $f\n";
$r = $c->write($f, "super duper\nnext line\n");
print "write(${BASEURI}test2/super.txt): $r\n";
@a = $c->fstat($f);
print "fstat($f): ".join(', ',@a)."\n";
$r= $c->close($f);
print "close($f): $r\n";

### read content:
$f = $c->open($BASEURI.'test2/super.txt');
print "open(${BASEURI}test2/super.txt: $f\n";
print "read($f)=".$c->read($f)."\n";
$r = $c->close($f);
print "close($f): $r\n";

### seek and read content:
$f = $c->open($BASEURI.'test2/super.txt');
print "open(${BASEURI}test2/super.txt: $f\n";
$r = $c->seek($f,6);
print "seek($f,6): $r\n";
print "read($f)=".$c->read($f)."\n";
$r = $c->close($f);
print "close($f): $r\n";

### stat:
@a = $c->stat($BASEURI.'test2/super.txt');
print "stat(${BASEURI}test2/super.txt'): ".join(', ',@a)."\n";
print "mtime($a[9])=".localtime($a[9]),"\n";

### rename:
$r = $c->rename($BASEURI.'test2/super.txt', $BASEURI.'test2/super-renamed.txt');
print "rename(${BASEURI}test2/super.txt, ${BASEURI}test2/super-renamed.txt): $r\n";

### remove file:
$r = $c->unlink($BASEURI.'test2/super-renamed.txt');
print "unlink(${BASEURI}test2/super-renamed.txt: $r\n";

### transfer binary:
my $fh;
my $buffer;
my $size = (stat('test.png'))[7];
print "try to write test.png with size=$size\n";
open($fh,"<","test.png") || warn("Cannot open test.png");
sysread($fh,$buffer,$size);
$d = $c->open(">${BASEURI}test2/test.png") || warn("Cannot open >${BASEURI}test2/test.png");
$r=$c->write($d, $buffer);
print "write: r=$r\n";
print "stat(test.png): ".join(",",$c->fstat($d))."\n";
$c->close($d);
close($fh);

print "try to read test.png with size=$size\n";
$f = $c->open("<${BASEURI}test2/test.png") || warn("Cannot open <${BASEURI}test2/test.pn");
$buffer = $c->read($f, $size);
$r=$c->close($f);
print "hexdump(buffer)".join("",map {sprintf('%02x',$_)} unpack("W[$size]",$buffer))."\n";


### remove dir:
$r = $c->rmdir($BASEURI.'test2');
print "rmdir(${BASEURI}test2: $r\n";
$r = $c->unlink($BASEURI.'test2/test.png');
print "unlink(${BASEURI}test2/test.png\n";
$r = $c->rmdir($BASEURI.'test2');
print "rmdir(${BASEURI}test2: $r\n";


## remove recurse and readdir:
$c->mkdir("${BASEURI}test2r") || warn("cannot make dir test2r");
$c->mkdir("${BASEURI}test2r/f1") || warn("cannot make dir test2r/f1");
$f=$c->open("${BASEURI}test2r/f1/file1.txt") || warn("cannot open file test2r/f1/file1.txt");
$c->write($f,"file");
$c->close($f);
$f=$c->opendir("${BASEURI}test2r/");
@a = $c->readdir($f);
print Dumper(\@a);
$r=$c->rmdir_recurse("${BASEURI}test2r");
print "rmdir_recurse(${BASEURI}test2r): $r\n";


$c->shutdown(1);

