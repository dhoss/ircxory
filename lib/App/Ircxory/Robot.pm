# Copyright (c) 2007 Jonathan Rockway <jrockway@cpan.org>

package App::Ircxory::Robot;
use strict;
use warnings;

use Carp;
use Log::Log4perl;
use POE qw(Component::IRC);
use POE::Kernel;
use Regexp::Common qw/balanced/;
use App::Ircxory::Robot::Action;

=head1 NAME

App::Ircxory::Robot - the ircbot to collect ratings

=head1 SYNOPSIS

    my $bot = App::Ircxory::Robot->
        new({ nick     => 'spybot',
              server   => 'irc.perl.org',
              channels => [qw|#chicago.pm #dongs #catalyst|],
              callback => \&callme, 
            });
 
    $bot->go; # blocks

    sub callme {
        my $action = shift; # App::Ircxory::Robot::Action object
        my $who    = $action->nick;
        my $what   = $action->word;
        print "Wow, did you know that $who likes $what?" 
          if $action->points > 0
    }

=head1 DESCRIPTION

It's an IRC bot.  It sits and listens to the channels, looking for
people plusplus and minusminus-ing things.  When that happens, your
callback sub gets a
L<App::Ircxory::Robot::Action|App::Ircxory::Robot::Action> object with
info about the action.

=head1 METHODS

=head2 new({server => 'irc.perl.org', ...});

Create a new IRC bot.  Required args are C<nick>, C<server>,
C<channels> (and arrayref), and C<callback>.  C<callback> is a coderef
that is called with a App::Ircxory::Robot::Action when the bot detects
some relevant activity.

=head2 go

Start the bot.  Returns when the bot is asked to quit.

=head1 INTERNAL METHODS

These are for POE.

=head2 irc_001

Init connection.

=head2 irc_public

Recieve a public message (in a channel), parse it, and call the
callback if necessary.

=head2 _default

Nothing really.

=head2 _start

Start the IRC bot.

=cut

sub new {
    my $class = shift;
    my $self  = shift;
    
    # read args
    croak 'need nick'     unless $self->{nick};
    croak 'need server'   unless $self->{server};
    croak 'need channels' unless ref $self->{channels} eq 'ARRAY';
    croak 'need callback' unless ref $self->{callback} eq 'CODE';
    
    # init bot
    my $irc = POE::Component::IRC->
      spawn( 
            nick    => $self->{nick},
            server  => $self->{server},
            port    => $self->{port} || 6667,
            ircname => __PACKAGE__,
           ) or croak "Failed to create IRC Bot: $!";

    # init session (based on this object)
    $self = bless $self => $class;
    my $session = POE::Session->
      create(
             object_states => [$self => 
                               { '_default'   => '_default',
                                 '_start'     => '_start',
                                 'irc_001'    => 'irc_001',
                                 'irc_public' => 'irc_public',
                               },
                              ],
             heap => { irc => $irc, instance => $self },
            );
    
    $self->{session} = $session;
    return $self;
}

sub go {
    my $self = shift;
    POE::Kernel->run();
}

sub _start {
    my ($kernel,$heap) = @_[KERNEL,HEAP];
    my $irc_session = $heap->{irc}->session_id();
    
    $kernel->post( $irc_session => register => 'all' );
    $kernel->post( $irc_session => connect => { } );
    
    return;
}

sub irc_001 {
    my ($kernel,$sender,$heap) = @_[KERNEL,SENDER,HEAP];
    my $poco_object = $sender->get_heap();
    my $log = Log::Log4perl->get_logger(__PACKAGE__);
    
    $log->info("Connected to ", $poco_object->server_name());
    
    my @channels = @{$heap->{instance}->{channels}||[]};
    for (@channels){
        $log->info("Joining $_");
        $kernel->post( $sender => join => $_ );
    }
    
    return;
}

sub irc_public {
    my ($kernel,$sender,$heap,$who,$where,$what) = 
      @_[KERNEL,SENDER,HEAP,ARG0,ARG1,ARG2];
    if ($who =~ /jrockway/ && $what =~ /go away/) {
        $kernel->post($sender => 'shutdown');
    }
    $heap->{instance}->_parse_message($what, $who, $where);
}

sub _default {
    my ($event, $args) = @_[ARG0 .. $#_];
    #my @output = ( "$event: " );
    # 
    #foreach my $arg ( @$args ) {
    #    if ( ref($arg) eq 'ARRAY' ) {
    #        push( @output, "[" . join(" ,", @$arg ) . "]" );
    #    } else {
    #        push ( @output, "'$arg'" );
    #    }
    #}
    #print STDOUT join ' ', @output, "\n";
    return 0;
}

sub _parse_message {
    my $self    = shift;
    my $message = shift;
    my $who     = shift;
    my $where   = shift;

    my $call    = $self->{callback};

    if ($message =~ /^ (.+)             # what we're voting on, possibly
                     ([+]{2}|[-]{2})    # the operation (inc or dec)
                     \s*                # spaces, who cares
                     (?:[#] \s* (.+))?  # and an optional reason
                     $/x
       )
      {
          my $vote   = $1;
          my $op     = $2;
          my $reason = $3;

          my $action = App::Ircxory::Robot::Action->
            new({ nick    => $who, # TODO nick parser
                  channel => $where,  
                  word    => $vote, # TODO
                  points  => ($op eq '++' ? 1 : -1),
                  reason  => $reason,
                });
          $call->($action);
      }
    
    return;
}

1;
