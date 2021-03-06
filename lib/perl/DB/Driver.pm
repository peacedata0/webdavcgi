#########################################################################
# (C) ZE CMS, Humboldt-Universitaet zu Berlin
# Written 2010-2011 by Daniel Rohde <d.rohde@cms.hu-berlin.de>
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
package DB::Driver;

use strict;
use warnings;

our $VERSION = '1.0';

use vars qw( $PREFIX);

$PREFIX = '///-/';

use DBI;
use List::MoreUtils qw(any);
use CGI::Carp;

use DefaultConfig
  qw( $DBI_SRC $DBI_USER $DBI_PASS $CREATE_DB @DB_SCHEMA $DBI_PERSISTENT );
use HTTPHelper qw( get_parent_uri );

use vars qw( $DBI_INIT );

sub new {
    my $this  = shift;
    my $class = ref($this) || $this;
    my $self  = {};
    bless $self, $class;
    $self->{config} = shift;
    $self->{cache}  = $self->{config}->{cache};
    return $self;
}
sub free {
    my ($self) = @_;
    delete $self->{config};
    delete $self->{cache};
    return $self;
}
sub finalize {
    my $self = shift;
    if ( !$DBI_PERSISTENT && $DBI_INIT ) {
        $DBI_INIT->disconnect();
        undef $DBI_INIT;
    }
    return;
}

sub db_handleUpdates {
    my ( $self, $dbh, $sth ) = @_;
    my $ret = 0;
    if ( $sth->err ) {
        carp( $sth->errstr );
        $sth->finish();

        # my $rc = $dbh->rollback();
        # warn ("rollback failed (rc=$rc)") unless $rc;
        #	} else {
        #		$ret = $dbh->commit();
        #		warn("commit failed (rc=$ret)") unless $ret;
    }
    return $ret;
}

sub db_handleSelect {
    my ( $self, $dbh, $sth ) = @_;
    my $ret = 0;
    if ( $sth->err ) {
        carp( $sth->errstr );
        $sth->finish();    # sqlite needs it
        $dbh->rollback();

        #	} else {
        #		$ret = $dbh->commit();
        #		warn("commit failed (rc=$ret)") unless $ret;
    }
    return $ret;
}

sub db_isRootFolder {
    my ( $self, $fn, $token ) = @_;
    my $rows = [];
    my $dbh  = $self->db_init();
    my $sth  = $dbh->prepare(
'SELECT basefn,fn,type,scope,token,depth,timeout,owner,timestamp FROM webdav_locks WHERE fn = ? AND basefn = ? AND token = ?'
    );
    if ( defined $sth ) {
        $sth->execute( $fn, $fn, $token );
        $rows = $sth->fetchall_arrayref();
        $self->db_handleSelect( $dbh, $sth );
    }
    return $#{$rows} >= 0;
}

sub db_getLike {
    my ( $self, $fn ) = @_;
    my $rows;
    my $dbh = $self->db_init();
    my $sth = $dbh->prepare(
'SELECT basefn,fn,type,scope,token,depth,timeout,owner,timestamp FROM webdav_locks WHERE fn like ?'
    );
    if ( defined $sth ) {
        $sth->execute($fn);
        $rows = $sth->fetchall_arrayref();
        $self->db_handleSelect( $dbh, $sth );
    }
    return $rows;
}

sub db_getCached {
    my ( $self, $fn, $token ) = @_;
    my $cm = $self->{cache};
    if ( defined $token
        && $cm->exists_entry( [ 'lockentry', $fn, 'token', $token ] ) )
    {
        return $cm->get_entry( [ 'lockentry', $fn, 'row' ] );
    }
    if ( $cm->exists_entry( [ 'lockentry', $fn, 'row' ] ) ) {
        return $cm->get_entry( [ 'lockentry', $fn, 'row' ] );
    }
    my $pfn = get_parent_uri($fn);
    if ( $cm->exists_entry( [ 'lockentry', $pfn, 'row' ] ) ) { return []; }
    $cm->set_entry( [ 'lockentry', $fn, 'row' ], [] );
    if ( defined $token ) {
        $cm->set_entry( [ 'lockentry', $fn, 'token', $token ], 0 );
    }
    my $rows = $self->db_getLike($pfn.q{/%});
    $cm->set_entry( [ 'lockentry', $pfn, 'row' ], [] );
    if ( defined $token ) {
        $cm->set_entry( [ 'lockentry', $pfn, 'token', $token ], 0 );
    }

    foreach my $row ( @{$rows} ) {
        $cm->set_entry( [ 'lockentry', $row->[1], 'row' ], [ $row ] );
        $cm->set_entry( [ 'lockentry', $row->[1], 'token', $row->[4] ], 1 );
    }
    if (
           defined $fn
        && $cm->exists_entry( [ 'lockentry', $fn, 'row' ] )
        && ( !defined $token
            || $cm->exists_entry( [ 'lockentry', $fn, 'token', $token ] ) )
      )
    {
        return $cm->get_entry( [ 'lockentry', $fn, 'row' ] );
    }
    return [];
}

sub db_get {
    my ( $self, $fn, $token ) = @_;
    my $rows;
    my $dbh = $self->db_init();
    my $sel =
'SELECT basefn,fn,type,scope,token,depth,timeout,owner,timestamp FROM webdav_locks WHERE fn = ?';
    my @params;
    push @params, $fn;
    if ( defined $token ) {
        $sel .= ' AND token = ?';
        push @params, $token;
    }

    my $sth = $dbh->prepare($sel);
    if ( defined $sth ) {
        $sth->execute(@params);
        $rows = $sth->fetchall_arrayref();
        $self->db_handleSelect( $dbh, $sth );
    }
    return $rows;
}

sub db_insertProperty {
    my ( $self, $fn, $propname, $value ) = @_;
    my $ret = 0;
    my $dbh = $self->db_init();
    my $sth = $dbh->prepare(
        'INSERT INTO webdav_props (fn, propname, value) VALUES ( ?,?,?)');
    if ( defined $sth ) {
        $sth->execute( $PREFIX . $fn, $propname, $value );
        $ret = ( $sth->rows > 0 ) ? 1 : 0;
        $self->db_handleUpdates( $dbh, $sth );
        $self->{cache}->set_entry( [ 'Properties', $fn, $propname ], $value );
    }
    return $ret;
}
sub db_insertProperties {
    my ( $self, @triplets) = @_;
    my $ret = 0;
    my $dbh = $self->db_init();
    my $tc = ($#triplets+1) / 3;
    foreach my $i (1..$tc) {
        my $j = ($i-1) * 3;
        $triplets[$j] = $PREFIX . $triplets[$j];
        $self->{cache}->set_entry( [ 'Properties', $triplets[$j], $triplets[$j + 1] ], $triplets[$j + 2] );
    }
    my $sth = $dbh->prepare(
        'INSERT INTO webdav_props (fn, propname, value) VALUES ( ?, ?, ? ) '
        . (  ' , ( ?, ?, ? )' x ($tc - 1) )
        );
    if ( defined $sth ) {
        $sth->execute( @triplets );
        $ret = ( $sth->rows > 0 ) ? 1 : 0;
        $self->db_handleUpdates( $dbh, $sth );
    }
    return $ret;
}

sub db_updateProperty {
    my ( $self, $fn, $propname, $value ) = @_;
    my $ret = 0;
    my $dbh = $self->db_init();
    my $sth = $dbh->prepare(
'UPDATE webdav_props SET value = ? WHERE (fn = ? OR fn = ?) AND propname = ?'
    );
    if ( defined $sth ) {
        $sth->execute( $value, $fn, $PREFIX . $fn, $propname );
        $ret = ( $sth->rows > 0 ) ? 1 : 0;
        $self->db_handleUpdates( $dbh, $sth );
        $self->{cache}->set_entry( [ 'Properties', $fn, $propname ], $value );
    }
    return $ret;
}

sub db_moveProperties {
    my ( $self, $src, $dst ) = @_;
    my $dbh = $self->db_init();
    my $sth =
      $dbh->prepare('UPDATE webdav_props SET fn = ? WHERE fn = ? OR fn = ?');
    my $ret = 0;
    if ( defined $sth ) {
        $sth->execute( $PREFIX . $dst, $PREFIX . $src, $src );
        $ret = ( $sth->rows > 0 ) ? 1 : 0;
        $self->db_handleUpdates( $dbh, $sth );
        $self->{cache}->remove_entry( [ 'Properties',      $src ] );
        $self->{cache}->remove_entry( [ 'Properties_flag', $src ] );
    }
    return $ret;
}

sub db_movePropertiesRecursive {
    my ( $self, $src, $dst ) = @_;
    my $dbh = $self->db_init();
    my $sth = $dbh->prepare(
'UPDATE webdav_props SET fn = REPLACE(fn, ?, ?) WHERE fn = ? OR fn = ? OR fn LIKE ? OR fn LIKE ?'
    );
    my $ret = 0;
    if ( defined $sth ) {
        $sth->execute(
            $PREFIX . $src,
            $PREFIX . $dst,
            $src, $PREFIX . $src,
            "$src/\%", "$PREFIX$src/\%"
        );
        $ret = ( $sth->rows > 0 ) ? 1 : 0;
        $self->db_handleUpdates( $dbh, $sth );
        $self->{cache}->remove_entry( [ 'Properties',      $src ] );
        $self->{cache}->remove_entry( [ 'Properties_flag', $src ] );
    }
    return $ret;
}

sub db_copyProperties {
    my ( $self, $src, $dst ) = @_;
    my $dbh = $self->db_init();
    my $sth = $dbh->prepare(
'INSERT INTO webdav_props (fn,propname,value) SELECT ?, propname, value FROM webdav_props WHERE fn = ? OR fn = ?'
    );
    my $ret = 0;
    if ( defined $sth ) {
        $sth->execute( $PREFIX . $dst, $src, $PREFIX . $src );
        $ret = ( $sth->rows > 0 ) ? 1 : 0;
        $self->db_handleUpdates( $dbh, $sth );
    }
    return $ret;
}

sub db_deleteProperties {
    my ( $self, $fn ) = @_;
    my $dbh = $self->db_init();
    my $sth = $dbh->prepare('DELETE FROM webdav_props WHERE fn = ? OR fn = ?');
    my $ret = 0;
    if ( defined $sth ) {
        $sth->execute( $fn, $PREFIX . $fn );
        $self->db_handleUpdates( $dbh, $sth );
        $self->{cache}->remove_entry( [ 'Properties', $fn ] );
        $ret = 1;    # bugfix by Harald Strack <hstrack@ssystems.de>
    }
    return $ret;

}

sub db_deletePropertiesRecursive {
    my ( $self, $fn ) = @_;
    my $dbh = $self->db_init();
    my $sth = $dbh->prepare(
'DELETE FROM webdav_props WHERE fn = ? OR fn = ? OR fn like ? OR fn like ?'
    );
    my $ret = 0;
    if ( defined $sth ) {
        $sth->execute( $fn, $PREFIX . $fn, "$fn/\%", "$PREFIX$fn/\%" );
        $self->db_handleUpdates( $dbh, $sth );
        $self->{cache}->remove_entry( [ 'Properties', $fn ] );
        $ret = 1;    # bugfix by Harald Strack <hstrack@ssystems.de>
    }
    return $ret;

}

sub db_deletePropertiesRecursiveByName {
    my ( $self, $fn, $propname ) = @_;
    my $dbh = $self->db_init();
    my $sth = $dbh->prepare(
'DELETE FROM webdav_props WHERE propname = ? AND (fn = ? OR fn = ? OR fn like ? OR fn like ?)'
    );
    my $ret = 0;
    if ( defined $sth ) {
        $sth->execute( $propname, $fn, $PREFIX . $fn,
            "$fn/\%", "$PREFIX$fn/\%" );
        $self->db_handleUpdates( $dbh, $sth );
        $self->{cache}->remove_entry( [ 'Properties', $fn ] );
        $ret = 1;    # bugfix by Harald Strack <hstrack@ssystems.de>
    }
    return $ret;

}

sub db_getProperties {
    my ( $self, $fn ) = @_;
    my $cm = $self->{cache};
    if (   $cm->exists_entry( [ 'Properties', $fn ] )
        || $cm->exists_entry( [ 'Properties_flag', $fn ] ) )
    {
        return $cm->get_entry( [ 'Properties', $fn ] );
    }
    my $dbh = $self->db_init();
    my $sth = $dbh->prepare(
'SELECT REPLACE(fn,?,?), propname, value FROM webdav_props WHERE fn like ? OR fn like ?'
    );
    if ( defined $sth ) {
        $sth->execute( $PREFIX, q{}, "$fn\%", "$PREFIX$fn\%" );
        if ( !$sth->err ) {
            my $rows = $sth->fetchall_arrayref();
            $self->db_handleSelect( $dbh, $sth );
            foreach my $row ( @{$rows} ) {
                $cm->set_entry( [ 'Properties', ${$row}[0], ${$row}[1] ],
                    ${$row}[2] );
            }
        }
        else {
            $self->db_handleSelect( $dbh, $sth );
        }
    }
    $cm->set_entry( [ 'Properties_flag', $fn ], 1 );
    return $cm->get_entry( [ 'Properties', $fn ] );
}

sub db_getPropertyFromCache {
    my ( $self, $fn, $propname ) = @_;
    return $self->{cache}->get_entry( [ 'Properties', $fn, $propname ] );
}

sub db_getProperty {
    my ( $self, $fn, $propname ) = @_;
    my $props = $self->db_getProperties($fn);
    return $props->{$propname};
}

sub db_removeProperty {
    my ( $self, $fn, $propname ) = @_;
    my $dbh = $self->db_init();
    my $sth = $dbh->prepare(
        'DELETE FROM webdav_props WHERE (fn = ? OR fn = ?) AND propname = ?');
    my $ret = 0;
    if ( defined $sth ) {
        $sth->execute( $fn, $PREFIX . $fn, $propname );
        $ret = ( $sth->rows > 0 ) ? 1 : 0;
        $self->db_handleUpdates( $dbh, $sth );
        $self->{cache}->remove_entry( [ 'Properties', $fn, $propname ] )
          ;
    }
    return $ret;
}
sub db_removeProperties {
    my ($self, $fn, @propertynames ) = @_;
    if ($#propertynames < 0) {
        return 0;
    }
    my $dbh = $self->db_init();
    my $sth = $dbh->prepare(
        'DELETE FROM webdav_props WHERE (fn = ? OR fn = ?) AND ( propname = ?'
        . ( ' OR propname = ? ' x $#propertynames ) . ' )'
        );
    my $ret = 0;
    if ( defined $sth ) {
        $sth->execute( $fn, $PREFIX . $fn, @propertynames );
        $ret = ( $sth->rows > 0 ) ? 1 : 0;
        $self->db_handleUpdates( $dbh, $sth );
        foreach my $propname ( @propertynames) {
            $self->{cache}->remove_entry( [ 'Properties', $fn, $propname ] );
        }
    }
    return $ret;
}

sub db_getPropertyFnByValue {
    my ( $self, $propname, $value ) = @_;
    my $dbh = $self->db_init();
    my $sth = $dbh->prepare(
'SELECT REPLACE(fn,?,?) FROM webdav_props WHERE propname = ? and value = ?'
    );
    if ( defined $sth ) {
        $sth->execute( $PREFIX, q{}, $propname, $value );
        if ( !$sth->err ) {
            my $rows = $sth->fetchall_arrayref();
            $self->db_handleSelect( $dbh, $sth );
            return $rows->[0] if $rows;
        }
        $self->db_handleSelect( $dbh, $sth );
    }
    return;
}

sub db_insert {
    my ( $self, $basefn, $fn, $type, $scope, $token, $depth, $timeout, $owner )
      = @_;
    my $ret = 0;
    my $dbh = $self->db_init();
    my $sth = $dbh->prepare(
'INSERT INTO webdav_locks (basefn, fn, type, scope, token, depth, timeout, owner) VALUES ( ?,?,?,?,?,?,?,?)'
    );
    if ( defined $sth ) {
        $sth->execute( $basefn, $fn, $type, $scope, $token, $depth, $timeout,
            $owner );
        $ret = ( $sth->rows > 0 ) ? 1 : 0;
        $self->db_handleUpdates( $dbh, $sth );
    }
    return $ret;
}

sub db_update {
    my ( $self, $basefn, $fn, $timeout ) = @_;
    my $ret = 0;
    my $dbh = $self->db_init();
    my $sth = $dbh->prepare(
        'UPDATE webdav_locks SET timeout=? WHERE basefn = ? AND fn = ?');
    if ( defined $sth ) {
        $sth->execute( $timeout, $basefn, $fn );
        $ret = ( $sth->rows > 0 ) ? 1 : 0;
        $self->db_handleUpdates( $dbh, $sth );
    }
    return $ret;
}

sub db_delete {
    my ( $self, $fn, $token ) = @_;
    my $ret    = 0;
    my $dbh    = $self->db_init();
    my $sel    = 'DELETE FROM webdav_locks WHERE ( basefn = ? OR fn = ? )';
    my @params = ( $fn, $fn );
    if ( defined $token ) {
        $sel .= ' AND token = ?';
        push @params, $token;
    }
    my $sth = $dbh->prepare($sel);
    if ( defined $sth ) {
        $sth->execute(@params);
        $ret = $sth->rows > 0 ? 1 : 0;
        $self->db_handleUpdates( $dbh, $sth );
    }

    return $ret;
}

sub db_modify {
    my ( $self, $prepstmt, @params ) = @_;
    my $ret = 0;
    my $dbh = $self->db_init();
    my $sth = $dbh->prepare($prepstmt);
    if ( defined $sth ) {
        $ret = $sth->execute(@params);
        $self->db_handleUpdates( $dbh, $sth );
    }
    return $ret;
}

sub db_select {
    my ( $self, $prepstmt, $paramsref, $slice, $max_rows ) = @_;
    my $dbh = $self->db_init();
    my $sth = $dbh->prepare($prepstmt);
    return
      defined $sth && $sth->execute( @{$paramsref} )
      ? $sth->fetchall_arrayref( $slice, $max_rows )
      : undef;
}

sub db_selecth {
    my ( $self, $prepstmt, $paramsref, $key ) = @_;
    my $dbh = $self->db_init();
    my $sth = $dbh->prepare($prepstmt);
    return
      defined $sth && $sth->execute( @{$paramsref} )
      ? $sth->fetchall_hashref($key)
      : undef;
}

sub db_table_exists {
    my ( $self, $table ) = @_;
    my $dbh = $self->db_init();
    my @tables = $dbh->tables( q{}, q{}, $table, 'TABLE' );
    if (@tables) {
        foreach (@tables) {
            if ( $_ && /\Q${table}\E$/xms ) {
                return 1;
            }
        }
    }
    return 0;
}

sub db_init {
    my $self = shift;
    return $DBI_INIT if defined $DBI_INIT;

    my $dbh =
      DBI->connect( $DBI_SRC, $DBI_USER, $DBI_PASS,
        { RaiseError => 0, PrintError => 0, AutoCommit => 1 } )
      || croak('You need a database (see $DBI_SRC configuration)');
    if ( defined $dbh && $CREATE_DB ) {
        foreach my $query (@DB_SCHEMA) {
            my $sth = $dbh->prepare($query);
            if ( defined $sth ) {
                $sth->execute();

                #                if ( $sth->err ) {
                #                    $sth->finish();
                #                    $dbh->rollback();
                #                    $dbh = undef;
                #                }
                #                else {
                #                    $dbh->commit();
                #                }
            }
            else {
                carp("db_init: '$query' preparation failed!");
            }
        }
    }
    $DBI_INIT = $dbh;
    return $dbh;
}

sub db_rollback {
    my ( $self, $dbh ) = @_;
    return $dbh->rollback();
}

sub db_commit {
    my ( $self, $dbh ) = @_;
    return $dbh->commit();
}
1;
