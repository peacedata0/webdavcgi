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
# ooffice - path to ooffice (default: /usr/bin/soffice)

package WebInterface::Extension::ODFConverter;

use strict;
#use warnings;

our $VERSION = '1.0';

use base qw( WebInterface::Extension  );

use File::Temp qw( tempdir );
use JSON;

use FileUtils qw( rcopy );


sub init { 
	my($self, $hookreg) = @_; 
	my @hooks = ('css','locales','javascript', 'fileactionpopup', 'fileattr', 'posthandler');
	
	$$self{ooffice} = $self->config('ooffice','/usr/bin/soffice');
	
	$hookreg->register(\@hooks, $self) if -x $$self{ooffice};
	
	
	$$self{oofficeparams} = $self->config('oofficeparams', ['--headless', '--invisible','--convert-to','%targetformat','--outdir','%targetdir','%sourcefile']);
	
	$$self{types} = ['odt','odp','ods','doc','docx','ppt','pptx','xls','xlsx','csv','html','pdf','swf'];
	$$self{typesregex} = '('.join('|',@{$$self{types}}).')';
	$$self{groups} = {  t=> ['odt','doc','docx','pdf','html'], p=>['odp','ppt','pptx','pdf','swf'],s=>['ods','xls','xlsx','csv','pdf','html'] };
	$$self{unconvertible} = qq@(swf)@;
	
	$$self{popupcss}='<style>';
	foreach my $group ( keys  %{$$self{groups}}) {
		my @d = map { $$self{memberof}{$_}.=" c-$group"  } @{$$self{groups}{$group}};
		$$self{popupcss}.=".c-${group} .c-${group}\{display:list-item\} ";	
	}
	foreach my $suffix (@{$$self{types}}) {
		$$self{popupcss}.=".cs-${suffix} .cs-${suffix}\{display:none\} ";
	}
	$$self{popupcss}.='</style>';
	
}
sub handle { 
	my ($self, $hook, $config, $params) = @_;
	if ($hook eq 'fileattr') {
		my $suffix = $$params{path} =~ /\.(\w+)$/ ? $1 : 'unknown';
		return { ext_classes=> ($suffix =~ /$$self{typesregex}/ ? 'c' : '')." $$self{memberof}{$suffix} cs-$suffix"} unless $suffix=~/$$self{unconvertible}/;
	}
	my $ret = $self->SUPER::handle($hook, $config, $params);
	$ret.=$$self{popupcss} if ($hook eq 'css'); 
	return $ret if $ret;
	if ($hook eq 'fileactionpopup') {
		my @subpopup = map { { action=>'odfconvert',  label=>$_, type=>'li', classes=>"access-writeable $$self{memberof}{$_} cs-$_", data=>{ ct=>$_ }  } } @{$$self{types} };
		$ret = { title=>$self->tl('odfconverter'), classes=>'odfconverter',type=>'li', subpopupmenu =>\@subpopup };
		
	} elsif ($hook eq 'posthandler' && $$self{cgi}->param('action') eq 'odfconvert') {
		$ret=$self->convertFile();
	}
	return $ret;
}
sub convertFile {
	my ($self) = @_;
	my $cgi = $$self{cgi};
	my $targetformat = $cgi->param("ct");
	return 0 unless $targetformat =~/$$self{typesregex}/;
	my $file = $cgi->param("file");
	return 0 unless $$self{backend}->exists($main::PATH_TRANSLATED.$file);
	my $full = $$self{backend}->getLocalFilename($main::PATH_TRANSLATED.$file);
	my $tmpdirn = tempdir(CLEANUP=>1);
	my $tmpdir = $tmpdirn.'/';
	mkdir $tmpdir;
	
	my $tmphomedir = "/tmp/_webdavcgi_odfconverter_$main::REMOTE_USER";
	mkdir $tmphomedir unless -d $tmphomedir;
	$ENV{HOME}=$tmphomedir;
	
	my @params = @{$$self{oofficeparams}};
	for (my $i=0; $i<=$#params; $i++) {
		$params[$i]=~s/\%targetformat/$targetformat/g;
		$params[$i]=~s/\%sourcefile/$full/g;
		$params[$i]=~s/\%targetdir/$tmpdirn/g;	
	}
	
	my %jsondata;
	if (open(my $fh, "-|",$$self{ooffice},@params)) {
		my @output = <$fh>;
		close($fh);
		my $targetfile=($file=~/(^.*)\.\w+$/ ? $1 : $file).".$targetformat"; 
		if ($self->saveAllLocal($tmpdir,$full,$targetfile)) {
			$jsondata{message} = sprintf($self->tl('odfconverter.success'), $cgi->escapeHTML($file), $cgi->escapeHTML($targetfile));
		} else {
			$jsondata{error} = sprintf($self->tl('odfconverter.savefailed'), $targetfile);
		}
	} else {
		warn($$self{ooffice}.' '.join(' ',@params).' failed.');
		$jsondata{error} = sprintf($self->tl('odfconverter.failed'), $cgi->escapeHTML($file));
	}
	unlink($tmpdir);
	my $json = new JSON();
	main::print_header_and_content('200 OK', 'application/json', $json->encode(\%jsondata));
	return 1;
}
sub saveAllLocal {
	my ($self, $tmpdir, $localfile, $targetfilename) = @_;
	my $ret = 1;
	my $count = 0;
	my $localtargetfilename = $$self{backend}->basename($localfile);
	$localtargetfilename=~s/\.\w+$//;
	$localtargetfilename.='.'.$$self{cgi}->param('ct');
	if (opendir(my $dir, $tmpdir)) {
		while (my $file = readdir($dir) ) {
			my $targetlocal = $tmpdir.$file;
			next if $file=~/^\.{1,2}$/ || -d $targetlocal;
			my $targetfull = $main::PATH_TRANSLATED. ($file eq $localtargetfilename ? $targetfilename : $file);
			$ret = rcopy($targetfull, $targetfull.'.backup') if $$self{backend}->exists($targetfull);
			
			if ($ret && open(my $fh,"<",$targetlocal)) {
				$ret = $$self{backend}->saveStream($targetfull, $fh);
				$count++ if $ret;
				close($fh);
			} else {
				$ret = 0;
			}
			unlink($targetlocal);
			last if !$ret;
		}
		closedir($dir);
	}	
	return $count > 0;
}
1;