#!/usr/bin/perl
#########################################################################
# (C) ZE CMS, Humboldt-Universitaet zu Berlin
# Written 2015 by Daniel Rohde <d.rohde@cms.hu-berlin.de>
#########################################################################
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#########################################################################

package Backend::S3B::Driver;

use strict;
#use warnings;

use Carp;

use Backend::Helper;
our @ISA = qw( Backend::Helper );

our $VERSION = 0.1;

use Amazon::S3;
use Digest::SHA qw( sha512_base64 );
use File::Temp qw( tempfile tempdir );
use Date::Parse;



use Data::Dumper;

use vars qw( $S3 %CACHE );
sub new {
	my $class = shift;
	my $self = {};
	bless $self, $class;
	return $self;
}
sub finalize {
	$S3 = undef;
	%CACHE = ();
	return;
}

sub initialize {
	my ($self) = @_;
	$S3 = Amazon::S3->new(
		{
		aws_access_key_id => $main::BACKEND_CONFIG{$main::BACKEND}{access_id},
		aws_secret_access_key=> $main::BACKEND_CONFIG{$main::BACKEND}{secret_key},
		host => $main::BACKEND_CONFIG{$main::BACKEND}{host},
		secure => defined $main::BACKEND_CONFIG{$main::BACKEND}{secure} ? $main::BACKEND_CONFIG{S3B}{secure} : 1,
		retry => $main::BACKEND_CONFIG{$main::BACKEND}{retry},
		timeout => $main::BACKEND_CONFIG{$main::BACKEND}{timeout} || 60
		}
	) unless defined $S3;
	$$self{bucketprefix} = $main::BACKEND_CONFIG{$main::BACKEND}{bucketprefix};
	return;
}

sub readDir {
	my($self, $fn, $limit, $filter) = @_;
	$self->initialize();
	my @list;
	if ($self->_isRoot($fn)) {
		my $buckets = $S3->buckets();
		foreach my $b ( @{$$buckets{buckets}}) {
			my $bn = $$b{bucket};
			$bn=~s/^\Q$$self{bucketprefix}// if $$self{bucketprefix};
			$self->_fillStatCache($fn.$bn, $b);
			push @list, $bn;
		}
	} elsif ($self->_isBucket($fn) && !$self->SUPER::isDir($fn)) {
		my $l = $S3->list_bucket_all({ bucket=> $self->_getBucketName($fn)});
		foreach my $key (@{$$l{keys}}) {
			my $file = $$key{key};
			my $full = $fn.$file;
			$self->_fillStatCache($full, $key);
			push @list, $$key{key};
		}
	}
	return \@list;
}
sub unlinkFile {
	my ($self, $fn) = @_;
	my $ret = 0;
	$self->initialize();
	$fn = $self->resolve($fn);
	if ($self->_isRoot($fn)) {
		$ret = 0;
	} elsif ($self->_isBucket($fn)) {
		$ret = $S3->delete_bucket({ bucket=>$self->_getBucketName($fn) });
	} else {
		my $bucket = $S3->bucket($self->_getBucketName($fn));
		$ret =  $bucket && $bucket->delete_key($self->basename($fn));
	}
	return $ret;
}
sub deltree {
	my ($self, $fn) = @_;
	my $ret = 1;
	$self->initialize();
	$fn = $self->resolve($fn);
	if ($self->_isRoot($fn) || $self->_isBucket($fn)) {
		my $list = $self->readDir($fn);
		foreach my $f (@{$list}) {
			$ret &=$self->deltree($fn.'/'.$f);
		}	
	}
	$ret &= $self->unlinkFile($fn);
	return $ret;
}
sub isLink {
	return 0;
}
sub isDir {
	return $_[0]->_isRoot($_[1]) || $_[0]->_isBucket($_[1]);
}
sub isFile {
	return !$_[0]->isDir($_[1]);
}
sub rename { 
	my ($self, $on, $nn) = @_;
	$on=$self->resolve($on);
	$nn=$self->resolve($nn);
	return $self->copy($on, $nn) && $self->deltree($on);
}
sub copy {
	my ($self, $src, $dst) = @_;
	my $ret = 1;
	$src = $self->resolve($src);
	$dst = $self->resolve($dst);
	if ($self->_isRoot($src)) {
		$ret = 0;
	} elsif ($self->_isBucket($src)) {
		if ($self->_isRoot($self->dirname($dst))) {
			$self->mkcol($dst) || return 0;
		}
		my @list = $self->readDir($src);
		foreach my $f (@list) {
			$ret&=$self->copy($src.'/'.$f, $dst);
		}
	} elsif ($self->_isBucket($self->dirname($src))) {
		$ret = !$self->_isRoot($dst) && ($self->_isBucket($dst) || $self->_isBucket($self->dirname($dst))) ? $self->saveData($dst,$self->getFileContent($src) ) : 0;
	}
	return $ret;
}
sub mkcol {
	my ($self, $fn) = @_;
	$self->initialize();
	my $ret = 0;
	if ($self->_isRoot($self->dirname($fn))) {
		$ret = $S3->add_bucket({ bucket=>$self->_getBucketName($fn)}); 
		warn($S3->err.': '.$S3->errstr) unless $ret;
	}
	return $ret;
}
sub isReadable { return 1;}
sub isWriteable { return 1;}
sub isExecutable{ return $_[0]->isDir($_[1]);}

sub hasSetUidBit { return 0; }
sub hasSetGidBit { return 0; }
sub changeMod { return 0; }
sub isBlockDevice { return 0; }
sub isCharDevice { return 0; }
sub getLinkSrc { $!='not supported'; return; }
sub createSymLink { return 0; }
sub hasStickyBit { return 0; }

sub exists {
	my ($self, $fn) = @_;
	return 1 if $self->_isRoot($fn) || $self->_isBucket($fn);
	$fn = $self->resolve($fn);
	$self->initialize();
	my $bucket = $S3->bucket($self->_getBucketName($fn));
	return $bucket->head_key($self->basename($fn));
}
sub stat {
	my ($self,$fn) =@_;
	return (0,0,$main::UMASK,0,0,0,0,0,0,0,0,0,0) if $self->_isRoot($fn);
	if (!exists $CACHE{stat}{$fn} && ! $self->_isBucket($fn)) {
		my $bucketdir = $self->_getBucketDirname($fn);
		return $self->SUPER::stat($fn) if !$self->_isBucket($bucketdir);
		my $bucket = $S3->bucket($self->_getBucketName($fn));
		$self->_fillStatCache( $fn, $bucket->head_key($self->basename($fn))); 
	}
	$fn=$self->resolve($fn);
	my $lm = $CACHE{stat}{$fn}{last_modified} || $CACHE{stat}{$fn}{creation_date} || 0;
	my $size = $CACHE{stat}{$fn}{size} || 0;
	return (0,0,$main::UMASK,0,0,0,0,$size,$lm,$lm,$lm,0,0);
}

sub _isRoot {
	return $_[1] eq $main::DOCUMENT_ROOT;
}
sub _isBucket {
	my ($self, $bucketdirname) = @_;
	$_[0]->_readBuckets($_[1]) unless exists $CACHE{buckets};
	my $bn = $self->basename($bucketdirname);
	$bn = $$self{bucketprefix}.$bn if $$self{bucketprefix} && $bn!~/^\Q$$self{bucketprefix}\E/;
	return $CACHE{buckets}{$bn} && $self->_isRoot($self->dirname($bucketdirname));
}
sub _readBuckets {
	my ($self) = @_;
	$self->initialize();
	my $b = $S3->buckets();
	foreach my $b (@{$$b{buckets}}) {
		my $bn = $$b{bucket};
		$CACHE{buckets}{$bn} = 1;
		$bn=~s/^\Q$$self{bucketprefix}\E// if $$self{bucketprefix};
		$self->_fillStatCache($main::DOCUMENT_ROOT.$bn, $b);
	}
	return;
}
sub _fillStatCache {
	my($self, $fn, $v) = @_;
	$CACHE{stat}{$fn} = {
			content_type => $$v{content_type},
			size => $$v{size} || $$v{content_length},
			last_modified => str2time($$v{last_modified} || $$v{creation_date})
	};
	return;
}
sub _getBucketDirname {
	my ($self, $fn) = @_;
	if ($self->_isBucket($fn)) {
		return $self->dirname($fn).$$self{bucketprefix}.$self->basename($fn) if $$self{bucketprefix};
		return $fn;
	} elsif ($self->_isBucket($self->dirname($fn))) {
		return $self->_getBucketDirname($self->dirname($fn));
	} elsif ($self->_isRoot($self->dirname($fn))) {
		return $self->dirname($fn).$$self{bucketprefix}.$self->basename($fn) if $$self{bucketprefix};
		return $fn;
	}
	return;
}
sub _getBucketName {
	my ($self, $fn) = @_;
	my $dn = $self->_getBucketDirname($fn);
	return  $self->basename($dn ? $dn : $fn);
}
sub resolve {
	my ($self, $fn) = @_;
	$fn=~s/([^\/]*)\/\.\.(\/?.*)/$1/;
	$fn=~s/(.+)\/$/$1/;
	$fn=~s/\/\//\//g;
	return $fn;
}

sub isEmpty {
	return ($_[0]->stat($_[1]))[7] == 0;
}
sub saveData {
	#my ($self, $path, $data, $append) = @_;
	my $fn = $_[0]->resolve($_[1]);
	$_[0]->initialize();
	my $bucket = $S3->bucket($_[0]->_getBucketName($fn));
	my $key = $_[0]->basename($fn);
	my $mime = main::getMIMEType($fn);
	my $ret  = $bucket->add_key($key, $_[2], { content_type=> $mime}  );	
	warn($bucket->err.': '.$bucket->errstr) unless $ret;
	return $ret;
	
}
sub saveStream {
	my ($self, $fn, $fh) = @_;
	$fn = $self->resolve($fn);
	my $blob;
	while (read($fh, my $buffer, $main::BUFSIZE || 1048576)) {
		$blob.=$buffer;
	}
	return $self->saveData($fn, $blob);
}

sub printFile {
	my ($self, $fn, $fh, $pos, $count) = @_;
	$fn=$self->resolve($fn);
	
	print $fh substr($self->getFileContent($fn), $pos, $count) if $pos;
	print $fh $self->getFileContent($fn);
	return;  
}
sub getLocalFilename {
	my ($self, $fn) = @_;
	$fn=~/(\.[^\.]+)$/;
	my $suffix=$1;
	my ($fh, $filename) = tempfile(TEMPLATE=>'/tmp/webdavcgiXXXXX', CLEANUP=>1, SUFFIX=>$suffix);
	$self->printFile($fn, $fh);
	return $filename;
}
sub getFileContent {
	my ($self, $fn) = @_;
	$self->initialize();
	$fn = $self->resolve($fn);
	my $bucket = $S3->bucket($self->_getBucketName($fn));
	my $v = $bucket->get_key($self->basename($fn));
	return $$v{value};
}
1;