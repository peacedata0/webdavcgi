#########################################################################
# (C) ZE CMS, Humboldt-Universitaet zu Berlin
# Written 2016 by Daniel Rohde <d.rohde@cms.hu-berlin.de>
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

package Requests::DELETE;

use strict;
use warnings;

our $VERSION = '2.0';

use base qw( Requests::WebDAVRequest );

use URI::Escape;

use DefaultConfig qw( $PATH_TRANSLATED $ENABLE_TRASH $REQUEST_URI );
use FileUtils qw( move2trash );
use HTTPHelper qw( print_header_and_content );
use WebDAV::XMLHelper qw( create_xml );

sub handle {
    my ( $self ) = @_;
    $self->debug("_DELETE: $PATH_TRANSLATED");

    my $backend = $self->{backend};

    my @resps = ();
    if ( !$backend->exists($PATH_TRANSLATED) ) {
        return print_header_and_content('404 Not Found');
    }
    if ( ( $REQUEST_URI =~ /\#/xms && $PATH_TRANSLATED !~ /\#/xms )
        || ( defined $ENV{QUERY_STRING} && $ENV{QUERY_STRING} ne q{} ) )
    {
        return print_header_and_content('400 Bad Request');
    }
    if ( !$self->is_allowed($PATH_TRANSLATED) ) {
        return print_header_and_content('423 Locked');
    }
    $self->{event}->broadcast( 'DELETE', { file => $PATH_TRANSLATED } );
    if ( $ENABLE_TRASH && move2trash($self->{config}, $PATH_TRANSLATED) <= 0 ) {
        return print_header_and_content('404 Forbidden');

    }

    $backend->deltree( $PATH_TRANSLATED, \my @err );
    $self->logger("DELETE($PATH_TRANSLATED)");
    for my $diag (@err) {
        my ( $file, $message ) = each %{$diag};
        push @resps, { href => $file, status => "403 Forbidden - $message" };
    }

    my $status = $#resps >= 0 ? '207 Multi-Status' : '204 No Content';
    $self->{event}->broadcast( 'DELETED', { file => $PATH_TRANSLATED } );
    my $content =
      $#resps >= 0
      ? create_xml( { 'multistatus' => { 'response' => \@resps } } )
      : q{};
    $self->debug("_DELETE RESPONSE (status=$status): $content");
    return print_header_and_content(
        $status, $#resps >= 0 ? 'text/xml' : undef,
        $content
    );
}

1;
