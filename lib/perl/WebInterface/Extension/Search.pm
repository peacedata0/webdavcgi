#########################################################################
# (C) ZE CMS, Humboldt-Universitaet zu Berlin
# Written 2014 by Daniel Rohde <d.rohde@cms.hu-berlin.de>
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
#
# SETUP:
# disable_fileactionpopup - disables fileaction entry in popup menu
# disable_apps - disables sidebar menu entry
# allow_contentsearch - allowes search file content
# resultlimit - sets result limit (default: 1000)
# searchtimeout - sets a timeout in seconds (default: 30 seconds) 
# sizelimit - sets size limit for content search (default: 2097152 (=2MB))
# disable_dupseaerch - disables duplicate file search
# maxdepth - maximum search level (default: 100)
# duplicate_sample_size - sample size for doublet search (default: 1024 (=1KB))

package WebInterface::Extension::Search;

use strict;
use warnings;

our $VERSION = '1.0';

use base qw( WebInterface::Extension  );

use JSON;
use Time::HiRes qw(time);
use Digest::MD5 qw(md5_hex);
use POSIX qw(strftime);
use I18N::Langinfo qw (langinfo MON_1 MON_2 MON_3 MON_4 MON_5 MON_6 MON_7 MON_8 MON_9 MON_10 MON_11 MON_12 ABMON_1  ABMON_2 ABMON_3 ABMON_4 ABMON_5 ABMON_6 ABMON_7 ABMON_8 ABMON_9 ABMON_10 ABMON_11 ABMON_12
			DAY_1 DAY_2 DAY_3 DAY_4 DAY_5 DAY_6 DAY_7 ABDAY_1 ABDAY_2 ABDAY_3 ABDAY_4 ABDAY_5 ABDAY_6 ABDAY_7 D_FMT); 
use Time::Piece;

use FileUtils qw( get_file_limit );

use vars qw( %CACHE %TIMEUNITS);

%TIMEUNITS = ( 'seconds' => 1, 'minutes' => 60, 'hours'=>3600, 'days'=>86400, 'weeks'=> 604800, 'months'=>18144000, 'years'=>31557600);

sub init { 
	my($self, $hookreg) = @_; 
	my @hooks = ('link', 'css','locales','javascript', 'gethandler','posthandler');
	push @hooks,'fileactionpopup' unless $main::EXTENSION_CONFIG{Search}{disable_fileactionpopup};
	push @hooks,'apps' unless $main::EXTENSION_CONFIG{Search}{disable_apps};	
	$hookreg->register(\@hooks, $self);
	
	$self->{resultlimit} = $self->config('resultlimit', 1000);
	$self->{searchtimeout} = $self->config('searchtimeout', 30);
	$self->{sizelimit} = $self->config('sizelimit', 2_097_152);
	$self->{maxdepth} = $self->config('maxdepth',100);
	$self->{duplicate_sample_size} = $self->config('duplicate_sample_size', 1024);
	return $self;
}
sub handle { 
	my ($self, $hook, $config, $params) = @_;
	my $ret = $self->SUPER::handle($hook, $config, $params);
	return $ret if $ret;
	
	if( $hook eq 'fileactionpopup') {
		$ret = { action=>'search', label=>'search', path=>$$params{path}, type=>'li', classes=>'access-readable sel-dir' };
	} elsif ($hook eq 'apps') {
		$ret = $self->handleAppsHook($self->{cgi},'search access-readable ','search','search'); 
	} elsif ($hook eq 'gethandler') {
		my $action = $self->{cgi}->param('action');
		if ($action eq 'getSearchForm') {
			$ret = $self->getSearchForm();
		} elsif ($action eq 'getSearchResult') {
			$ret = $self->getSearchResult();
		} elsif ($action eq 'opensearch') {
                	$ret = $self->printOpenSearch();
		}
	} elsif ($hook eq 'posthandler') {
		if ($self->{cgi}->param('action') eq 'search') {
			$ret = $self->handleSearch();
		}
	} elsif ($hook eq 'link') {
		$ret='<link rel="search" href="?action=opensearch&amp;searchin=filename" type="application/opensearchdescription+xml" title="WebDAV CGI '. $self->tl('search.opensearch.filename') . ' '.$main::REQUEST_URI.'"/>';
		$ret.='<link rel="search" href="?action=opensearch&amp;searchin=content" type="application/opensearchdescription+xml" title="WebDAV CGI '. $self->tl('search.opensearch.content').' '.$main::REQUEST_URI.'"/>' if $self->config('allow_contentsearch',0);
	}
	
	return $ret;
}
sub cutLongString {
	my ($self, $string, $limit) = @_;
	$limit = 100 unless $limit;
	return $string if (length($string)<=$limit);
	return substr($string, 0, $limit-3).'...';
}
sub getSearchForm {
	my ($self) = @_;
	my $searchinfolders = $self->{cgi}->param('files') ? join(", ", map{ $self->{backend}->getDisplayName($main::PATH_TRANSLATED.$_)} $self->{cgi}->param('files')) : $self->tl('search.currentfolder');
	my $dfmt = langinfo(D_FMT);
	$dfmt=~s/\%(.)/\L$1$1\E/g;
	my $vars = { searchinfolders => $self->quote_ws($self->{cgi}->escapeHTML($self->cutLongString($searchinfolders))), searchinfolderstitle => $self->{cgi}->escapeHTML($searchinfolders),
			MONTHNAMES => '"'.join('","', map { langinfo($_)} ( MON_1, MON_2, MON_3, MON_4, MON_5, MON_6, MON_7, MON_8, MON_9, MON_10, MON_11, MON_12 )).'"',
			MONTHNAMESABBR => '"'.join('","', map { langinfo($_)} ( ABMON_1, ABMON_2, ABMON_3, ABMON_4, ABMON_5, ABMON_6, ABMON_7, ABMON_8, ABMON_9, ABMON_10, ABMON_11, ABMON_12 )).'"',
			DAYNAMES => '"'.join('","', map { langinfo($_)} ( DAY_1, DAY_2, DAY_3, DAY_4, DAY_5, DAY_6, DAY_7)).'"',
			DAYNAMESABBR => '"'.join('","', map { langinfo($_)} ( ABDAY_1, ABDAY_2, ABDAY_3, ABDAY_4, ABDAY_5, ABDAY_6, ABDAY_7)).'"',
			DAYNAMESMIN => '"'.join('","', map { substr(langinfo($_), 0, 2)} ( ABDAY_1, ABDAY_2, ABDAY_3, ABDAY_4, ABDAY_5, ABDAY_6, ABDAY_7)).'"',
			DATEFORMAT => $dfmt, FIRSTDAY => $main::LANG eq 'de' ? 1 : 0
	};
	my $content = $self->render_template($main::PATH_TRANSLATED,$main::REQUEST_URI,$self->read_template($self->config('template','search')), $vars);
	main::print_compressed_header_and_content('200 OK','text/html', $content,'Cache-Control: no-cache, no-store');	
	return 1;
}
sub getTempFilename {
	my ($self,$type) = @_;
	my $searchid = $self->{cgi}->param('searchid');
	return "/tmp/webdavcgi-search-$main::REMOTE_USER-$searchid.$type";
}
sub getResultTemplate {
	my($self, $tmplname) = @_;
	return $CACHE{$self}{resulttemplate}{$tmplname} ||= $self->read_template($tmplname);
}
sub addSearchResult {
	my ($self, $base, $file, $counter) = @_;
	if (open(my $fh,">>", $self->getTempFilename('result'))) {
		my $filename = $file eq "" ? "." : $self->{cgi}->escapeHTML($self->{backend}->getDisplayName($base.$file));
		my $full = $base.$file;
		my @stat = $self->{backend}->stat($full);
		my $uri = $main::REQUEST_URI.$self->{cgi}->escape($file);
		$uri=~s/\%2f/\//gi; 
		my $mime = $self->{backend}->isDir($full)?'<folder>':main::get_mime_type($full);
		my $suffix = $file eq '..' ? 'folderup' : ($self->{backend}->isDir($full) ? 'folder' : ($file =~ /\.([\w?]+)$/i ?  lc($1) : 'unknown')) ;
		my $category = $CACHE{categories}{$suffix} ||= $suffix ne 'unknown' && $main::FILETYPES =~ /^(\w+).*(?<=\s)\Q$suffix\E(?=\s)/m ? "category-$1" : '';
		print $fh $self->render_template($main::PATH_TRANSLATED, $main::REQUEST_URI, $self->getResultTemplate($self->config('resulttemplate', 'result')), 
			{ fileuri=>$self->{cgi}->escapeHTML($uri),  
				filename=>$filename,
				qfilename=>$self->quote_ws($filename),
				dirname=>$self->{cgi}->escapeHTML($self->{backend}->dirname($uri)),
				iconurl=>$self->{backend}->isDir($full) ? $self->get_icon($mime) : $self->can_create_thumb($full) && $self->{cgi}->cookie('settings.enable.thumbnails') ne 'no' ? $self->{cgi}->escapeHTML($uri).'?action=thumb' : $self->get_icon($mime),
				iconclass=>"icon $category suffix-$suffix ".($self->can_create_thumb($full) ? 'thumbnail': ''),
				mime => $self->{cgi}->escapeHTML($mime),
				type=> $mime eq '<folder>' ? 'folder' : 'file',
				parentfolder => $self->{cgi}->escapeHTML($self->{backend}->dirname($base.$file)),
				lastmodified => $self->{backend}->isReadable($full) ? strftime($self->tl('lastmodifiedformat'), localtime($stat[9])) : '-', 
				size=> ($self->render_byte_val($stat[7]))[0]
			});
		$$counter{results}++;
		close($fh);
	}
}
sub filterFiles {
	my ($self, $base, $file, $counter) = @_;
	my $ret = 0;
	my $query = $self->{query};
	my $size = $CACHE{$self}{search}{size} //= $self->{cgi}->param('size');
	my $searchin = $CACHE{$self}{search}{searchin} //=  $self->{cgi}->param('searchin') || 'filename';
	my $time = $CACHE{$self}{search}{time} //= $self->{cgi}->param('time');
	my $mstartdate = $CACHE{$self}{search}{mstartdate} //= $self->{cgi}->param('mstartdate') ? eval { Time::Piece->strptime(scalar $self->{cgi}->param('mstartdate'), langinfo(D_FMT)) }: undef;
	my $menddate = $CACHE{$self}{search}{menddate} //= $self->{cgi}->param('menddate') ? eval { Time::Piece->strptime(scalar $self->{cgi}->param('menddate'), langinfo(D_FMT)) + 86399999 } : undef;
	my $cstartdate = $CACHE{$self}{search}{cstartdate} //= $self->{cgi}->param('cstartdate') ? eval { Time::Piece->strptime(scalar $self->{cgi}->param('cstartdate'), langinfo(D_FMT)) }: undef;
	my $cenddate = $CACHE{$self}{search}{cenddate} //= $self->{cgi}->param('cenddate') ? eval { Time::Piece->strptime(scalar $self->{cgi}->param('cenddate'), langinfo(D_FMT)) + 86399999 } : undef;
	my $full = $base.$file;
	my @stat = $self->{backend}->stat($full);
	my $now = time();
	
	$ret = 1 if  $query && $searchin eq 'filename' && $self->{backend}->basename($file) !~ /$query/i;
	
	$ret = 1 if  $query && $self->config('allow_contentsearch',0) && $searchin eq 'content' 
			&& (	!$self->{backend}->isReadable($full)  
				|| !$self->{backend}->isFile($full)
				|| $self->{backend}->getFileContent($full,$self->{sizelimit} ) !~ /$query/igs
			);
		
	$ret |= 1 if !$self->{cgi}->param('filetype') && $self->{backend}->isFile($full) && !$self->{backend}->isLink($full);
	$ret |= 1 if !$self->{cgi}->param('foldertype') && $self->{backend}->isDir($full);
	$ret |= 1 if !$self->{cgi}->param('linktype') && $self->{backend}->isLink($full);
	
	if (defined $size && $size=~/^\d+$/) {
		my $sizecomparator = $self->{cgi}->param('sizecomparator');
		$sizecomparator = '==' if $sizecomparator eq '=';
		if ($sizecomparator =~ /^[<>=]{1,2}$/) { 
			my $filesize = $stat[7];
			my $realsize = $size * ( $self->{BYTEUNITS}{$self->{cgi}->param('sizeunits')} || 1);
			$ret |= ! eval "$filesize $sizecomparator $realsize";
		}
	}
	if (defined $time && $time=~/^[\d\.\,]+$/) {
		my $timecomparator = $self->{cgi}->param('timecomparator');
		my $timeunits = $self->{cgi}->param('timeunits');
		if ($timecomparator =~ /^[<>=]{1,2}$/ && exists $TIMEUNITS{$timeunits}) {
			my $expr = "($now-$stat[9]) $timecomparator ($time * $TIMEUNITS{$timeunits})";
			$expr=~s/\,/\./g;	
			$ret |= $self->{backend}->isDir($full) || !eval $expr;
		}
	}
	$ret |= $stat[9] <= $mstartdate if defined $mstartdate;
	$ret |= $stat[9] >= $menddate if defined $menddate;
	$ret |= $stat[10] <= $cstartdate if defined $cstartdate;
	$ret |= $stat[10] >= $cenddate if defined $cenddate;
	
	if (!$self->config('disable_dupsearch',0) && $self->{cgi}->param('dupsearch')) {
		if (!$ret && $self->{backend}->isFile($full) && !$self->{backend}->isLink($full)&& !$self->{backend}->isDir($full)) {  ## && ($self->{backend}->stat($full))[7] <= $self->{sizelimit}) {
			push @{$$counter{dupsearch}{sizes}{$stat[7]}}, { base=>$base, file=>$file };
		}
		$ret = 1;
	}
	return $ret;
}
sub limitsReached {
	my ($self, $counter) = @_;
	return $$counter{results} >= $self->{resultlimit} || (time() - $$counter{started}) >  $self->{searchtimeout} || $$counter{level} > $self->{maxdepth};
}
sub doSearch {
	my ($self, $base, $file, $counter) = @_;
	my $backend = $self->{backend};
	my $full = $base.$file;
	my $fullresolved = $self->{backend}->resolve($full);
	$$counter{level}++;
	return if $self->limitsReached($counter);
	$self->addSearchResult($base, $file, $counter) unless $self->filterFiles($base,$file,$counter);
	if ($backend->isDir($full)) {
		$$counter{folders}++;
		return if exists $$counter{visited}{$fullresolved};
		$$counter{visited}{$fullresolved}=1;
		foreach my $f ( sort @{ $backend->readDir($full, get_file_limit($full)) } ) {
			$f.='/' if $backend->isDir($full.$f);
			$self->doSearch($base, "$file$f", $counter);
			
		}
	} else {
		$$counter{files}++;
	}
	$$counter{maxlevel} = $$counter{level} if $$counter{level} > $$counter{maxlevel};
	$$counter{level}--;	
}
sub getSampleData {
	my ($self, $data, $size) = @_;
	foreach my $fileinfo (@{$$data{dupsearch}{sizes}{$size}}) {
		if ($size>0) {
			my $full = $$fileinfo{base}.$$fileinfo{file};
			my $md5 = md5_hex($self->{backend}->getFileContent($full, $self->{duplicate_sample_size}));
			push @{$$data{dupsearch}{md5sample}{$size}{$md5}}, $fileinfo;
		} else {
			push @{$$data{dupsearch}{md5sample}{$size}{0}}, $fileinfo; 
		}
	}
}
sub getFullData {
	my ($self, $data, $size, $md5sample) = @_;
	foreach my $fileinfo (@{$$data{dupsearch}{md5sample}{$size}{$md5sample},}) {
		if ($size <= $self->{duplicate_sample_size}) {
			push @{$$data{dupsearch}{md5}{$size}{$md5sample}}, $fileinfo;
			next;
		}
		my $md5 = md5_hex($self->{backend}->getFileContent($$fileinfo{base}.$$fileinfo{file}, $self->{sizelimit}));
		push @{$$data{dupsearch}{md5}{$size}{$md5}}, $fileinfo;		
	}
}
sub addDuplicateClusterResult {
	my ($self, $data, $size, $md5) = @_;
	if (open(my $fh,">>", $self->getTempFilename('result'))) {
		my ($s,$st) = $self->render_byte_val($size);
		my $bytesavings = (scalar(@{$$data{dupsearch}{md5}{$size}{$md5}})-1) * $size;
		my @savings = $self->render_byte_val($bytesavings);
		
		my ($sl, $slt) = $self->render_byte_val($self->{sizelimit});
		print $fh $self->render_template($main::PATH_TRANSLATED, $main::REQUEST_URI, $self->getResultTemplate($self->config('dupsearchtemplate', 'dupsearch')), 
			{
				filecount => scalar(@{$$data{dupsearch}{md5}{$size}{$md5}}),
				digest => $md5,
				size => $s,
				sizetitle=> $st,
				bytesize=>$size,
				sizelimit => $self->{sizelimit},
				sizelimittext => $sl,
				sizelimittitle=> $slt,
				savings => $savings[0],
				savingstitle=> $savings[1],
				bytesavings => $bytesavings,
			}
		);	
		close($fh); 
	}	
	foreach my $fileinfo (@{$$data{dupsearch}{md5}{$size}{$md5}}) {
		$self->addSearchResult($$fileinfo{base}, $$fileinfo{file}, $data);
	}
}
sub addDuplicateSavings {
	my ($self, $data) = @_;
	return if $$data{dupsearch}{savings} == 0;
	if (open(my $fh,">>", $self->getTempFilename('result'))) {
		my @savings  = $self->render_byte_val($$data{dupsearch}{savings});
		print $fh $self->render_template($main::PATH_TRANSLATED, $main::REQUEST_URI, $self->getResultTemplate($self->config('dupsearchsavingstemplate', 'dupsearchsavings')), {
			savings => $savings[0],
			savingstitle => $savings[1], 
			bytesavings =>  $$data{dupsearch}{savings},
			filecount => $$data{dupsearch}{filecount},
		});
		close($fh);
	}
}
sub doDupSearch {
	my ($self, $data) = @_;
	foreach my $size (sort { $a <=> $b} keys %{$$data{dupsearch}{sizes}}) {
		return if $self->limitsReached($data);
		## check count of files with same size:
		next unless scalar(@{$$data{dupsearch}{sizes}{$size}})>1;
		## get sample data:
		$self->getSampleData($data, $size);
		## check sample data md5 sums:		
		foreach my $md5sample (keys %{$$data{dupsearch}{md5sample}{$size}}) {		
			next unless scalar(@{$$data{dupsearch}{md5sample}{$size}{$md5sample}}) >1; 
			$self->getFullData( $data, $size, $md5sample);
		}
		## check md5 sums:	
		foreach my $md5 (keys %{$$data{dupsearch}{md5}{$size}}) {
			my $count = scalar(@{$$data{dupsearch}{md5}{$size}{$md5}});
			next unless $count >1;
			## TODO: compare bitwise
			$self->addDuplicateClusterResult($data, $size, $md5);
			$$data{dupsearch}{savings} += ($count - 1) * $size;
			$$data{dupsearch}{filecount} += $count - 1;
		}		
	}
}
sub handleSearch {
	my ($self) = @_;
	
	my @files = $self->{cgi}->param('files');
	@files = ( '' ) if scalar(@files) == 0;
	my @results = ();
	unlink $self->getTempFilename('result');
	my %counter = ( started => time(), results => 0, files => 0, folders => 0);

	if ($self->{query} = $self->{cgi}->param('query')) {
		$self->{query} = join('.*?', map {quotemeta($_)} split(/\s+/,$self->{query})); ## replace all
		$self->{query} =~s/([^\#\\]*)\\[\%\*]/$1\.\*\?/g; ## wildcards *,%
		$self->{query} =~s/([^\#\\]*)\\[\?_]/$1\./g; ## wildcards ?,_
		$self->{query} =~s/([^\#\\]*)\\\#/$1\\d+/g; ## wildcard #
		$self->{query} =~s/([^\#\\]*)\\\[(.*?([^\#\\]))\\\]/$1\[$2\]/g; ## [...]
		$self->{query} =~s/\\\\([\#\?\%\*_\[\]])/$1/g; ## quoted wildcards
		$self->{query} = '('.join('|', split(/\.\*\?or\.\*\?/i, $self->{query})).')' if $self->{query}=~/\.\*\?or\.\*\?/;
		$self->{query} =~s/(\.\*\?){2,}/$1/g; ## replace .*? sequence with one .*?
		eval { /$self->{query}/ };
		$self->{query} = quotemeta($self->{cgi}->param('query')) if $@;
	}
	#warn("query=$self->{query}");
	foreach my $file (@files) {
		last if $self->limitsReached(\%counter);
		$self->doSearch($main::PATH_TRANSLATED, $file,\%counter);
	}
	
	if (!$self->config('disable_dupsearch',0) && $self->{cgi}->param('dupsearch')) {
		$self->doDupSearch(\%counter);
		$self->addDuplicateSavings(\%counter);
	}
	
	$counter{completed} = time();
	my $duration = $counter{completed} - $counter{started};
	my $status = sprintf($self->tl('search.completed'),$counter{results} || '0', $duration, $counter{files} || '0' ,$counter{folders} || '0');
	my $data = !$counter{results} ? $self->{cgi}->div($self->tl('search.noresult')) : undef; 
	my %messages = ();
	$messages{warn} = $self->{cgi}->escapeHTML(sprintf($self->tl('search.limitsreached'), $self->{resultlimit}, $self->{searchtimeout}, $self->{maxdepth})) if $self->limitsReached(\%counter) || $counter{maxlevel} >= $self->{maxdepth};
	$self->getSearchResult($status, $data, \%messages);
	unlink $self->getTempFilename('result');
	return 1;
}
sub getSearchResult {
	my ($self, $status, $data, $messages) = @_;
	my %jsondata = $messages ? %{$messages} : ();
	my $tmpfn = $self->getTempFilename('result');
	$jsondata{status} = $status || $self->tl('search.inprogress');
	if ($data) {
		$jsondata{data} = $data;
	} else {
		if (open(my $fh, "<", $tmpfn)) {
			$jsondata{data} = $self->{cgi}->div(join('', <$fh>));
			close($fh);
		}
	} 	
	my $json = new JSON();
	main::print_compressed_header_and_content('200 OK','application/json', $json->encode(\%jsondata),'Cache-Control: no-cache, no-store');
	return 1;
}
sub renderSelectedFiles{
	my ($self, $format) = @_;
	my $ret = "";
	foreach my $file ($self->{cgi}->param('files')) {
		my $f = $format;
		$f=~s/\$v/$self->{cgi}->escapeHTML($file)/egs;
		$ret.=$f;
	}	
	return $ret;
}
sub exec_template_function {
	my ($self, $fn, $ru, $func, $param) = @_;
	my $content;
	$content = $self->renderSelectedFiles($param) if $func eq 'renderSelectedFiles';
	$content = time() if $func eq 'getSearchId';
	$content = $self->SUPER::exec_template_function($fn,$ru,$func,$param) unless defined $content;
	return $content;
}
sub printOpenSearch {
        my ($self) = @_;
        my $type = $self->{cgi}->param('searchin') eq 'content' && $self->config('allow_contentsearch',0) ? 'content' : 'filename';
        my $template = $type eq 'content' ? qq@$ENV{SCRIPT_URI}?action=search&amp;query={searchTerms}&amp;searchin=content@ : qq@$ENV{SCRIPT_URI}?action=search&amp;query={searchTerms}&amp;searchin=filename@;
        my $content = qq@<?xml version="1.0" encoding="utf-8" ?><OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">
        			<ShortName>WebDAV CGI $type search in $main::REQUEST_URI</ShortName>
        			<Description>WebDAV CGI $type search in $main::REQUEST_URI</Description>
        			<InputEncoding>utf-8</InputEncoding><Url type="text/html" template="$template" />
        			<Image height="16" width="16" type="image/x-icon">https://$ENV{HTTP_HOST}@.$self->getExtensionUri('Search','htdocs/search.ico').qq@</Image>
        			<Image height="64" width="64" type="image/png">https://$ENV{HTTP_HOST}@.$self->getExtensionUri('Search','htdocs/search64x64.png').qq@</Image>
        		</OpenSearchDescription>@;
        $content=~s/[\r]\n//sg;
        main::print_header_and_content("200 OK", 'text/xml', $content);
        return 1;
}
1;