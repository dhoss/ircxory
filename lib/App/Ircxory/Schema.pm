package App::Ircxory::Schema;

use strict;
use warnings;
use App::Ircxory::Robot::Parser;
use List::MoreUtils qw(uniq);
use Carp;

use base 'DBIx::Class::Schema';
__PACKAGE__->load_classes;

=head1 NAME

App::Ircxory::Schema - database for Ircxory

=head1 SYNOPSIS

    my $schema = App::Ircxory::Schema->connect

    # record an "opinion"
    my $action = App::Ircxory::Robot::Action->new({...});
    $schema->record($action);

=head1 METHODS

=head2 record($action)

Record a App::Ircxory::Robot::Action to the database

Insert an action into the database, creating people, nicknames, and
things if necessary.

=cut

sub record {
    my $self   = shift;
    my $action = shift;

    my $nickname = $self->_get_nickname(parse_nickname($action->who));
    my $thing    = $self->resultset('Things')->
      find_or_create({ thing => $action->word });

    my $channel  = $self->resultset('Channels')->
      find_or_create({ channel => $action->channel });
    
    return $self->resultset('Opinions')->
      create({ nickname => $nickname,
               thing    => $thing,
               points   => $action->points,
               message  => $action->message,
               reason   => $action->reason,
               channel  => $channel,
             });
}

=head2 _get_nickname($nick, $user, $host)

Given nick/username/host, try to find a nickname object that matches.
If there isn't one, we'll create one and return that.

If the nickname isn't associated with a Person object yet, one will
be created.

=cut

sub _get_nickname {
    my $self = shift;
    my ($nick, $user, $host) = @_;
    
    my $nickname = $self->resultset('Nicknames')->
      find_or_create({ nick     => $nick, 
                       username => $user,
                       host     => $host,
                     });

    my $person = $nickname->person;
    if (!$person) {
        # TODO: be smarter about hostmasks etc.
        my $person = $self->resultset('People')->
          find_or_create({ name => $nick });
        $nickname->person($person);
        $nickname->update;
    }
    
    return $nickname;
}

=head2 karma_for($thing [, $direction])

Returns the sum of points for C<$thing>.  If C<$direction> is
specified, the number of times $thing was modded in $direction is
returned.

=cut

sub karma_for {
    my $schema = shift;
    my $thing  = shift;
    my $dir    = shift;
    
    my @points;
    if (defined $dir && $dir == -1) {
        @points = ('points' => {'<=', -1});
    }
    elsif (defined $dir && $dir == 1) {
        @points = ('points' => {'>=', 1});
    }
    elsif (defined $dir && $dir == 0) {
        @points = ('points' => {'==', 0});
    }
    
    my $col = 
      $schema->resultset('Opinions')->
        search({ 'thing.thing' => lc $thing,
                 @points,
               },
               { include_columns => 'thing.thing',
                 join            => ['thing'],
               })->get_column('points');
    
    if (defined $dir) {
        return $col->func('count');
    }
    return $col->sum || 0;
}


=head2 reasons_for($thing, [$good])

Returns a list of reasons why a certian thing was karama'd.  If
good is 1, then only ++s will be shown; if good is -1, then only --s
will be returned.

=cut

sub reasons_for {
    my $schema = shift;
    my $thing  = shift;
    my $good   = shift;
    
    my @points;
    if (defined $good && $good == -1) {
        @points = ('points' => {'<=', -1});
    }
    elsif (defined $good && $good == 1) {
        @points = ('points' => {'>=', 1});
    }
    
    my @reasons = $schema->resultset('Opinions')->
      search({ 'thing.thing' => lc $thing,
               reason        => {'<>', ""},
               @points,
             },
             { include_columns => 'thing.thing',
               join            => ['thing'],
             })->get_column('reason')->all;
    
    return uniq @reasons;
}

=head2 detailed_reasons_for($thing)

Returns a list of [reason, person, points] tuples.

=cut

sub detailed_reasons_for {
    my $schema = shift;
    my $thing  = shift;
    
    my $rs = $schema->resultset('Opinions')->
      search({ 'thing.thing' => lc $thing,
               reason        => {'<>', ""},
             },
             { join            => ['thing'],
             });

    my @result;
    while (my $row = $rs->next) {
        push @result, [$row->reason, 
                       $row->nickname->person->name, 
                       $row->points];
    }
    return @result;

}


=head2 everything

Returns a list of (thing, points) tuples for every thing in the
database.

=cut

sub everything {
    my $schema = shift;
    
    my @rs = $schema->resultset('Opinions')->
      search({},
             { join     => 'thing',
               group_by => 'thing.thing',
               order_by => 'SUM(points) DESC',
               select   => ['thing.thing', {SUM => 'points'}],
               as       => ['thing', 'points'],
             }
            );
    
    return map {[$_->get_column('thing'), $_->get_column('points')]} @rs;
}

1;

