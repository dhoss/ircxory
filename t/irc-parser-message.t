#!/usr/bin/env perl
# Copyright (c) 2007 Jonathan Rockway <jrockway@cpan.org>

use strict;
use warnings;
use Test::More;
use App::Ircxory::Robot::Action;
use App::Ircxory::Robot::Parser;
use Data::Dumper;
use Readonly;

my $BOT = {nick => 'foobot'};
Readonly my $USER    => 'jrockway!~jon@jrock.us';
Readonly my $CHANNEL => '#perl++';

my %OPINIONS = (
                # start with the basics
                'foo++ # bar' => mk_action('foo',  1, 'bar'),
                'foo++'       => mk_action('foo',  1),
                'foo-- # bar' => mk_action('foo', -1, 'bar'),
                'foo--'       => mk_action('foo', -1),
                
                # grouping
                '(foo)++'     => mk_action('foo',  1),
                '[foo]++'     => mk_action('foo',  1),
                '{foo}++'     => mk_action('foo',  1),
                
                # spaces
                '  foo++  '   => mk_action('foo',  1),
                '( foo )++'   => mk_action('foo',  1),
                '[ foo ]++'   => mk_action('foo',  1),
                '{ foo }++'   => mk_action('foo',  1),

                # capitals
                'FOO++'       => mk_action('foo',  1),
                
                # things with spaces
                '(something I like a whole darn lot)++ # i like it'
                => mk_action('something i like a whole darn lot', 
                             1, 'i like it'),

                # actual messages from IRC
                "I AM EATING SOME {CINNAMON ROLLS}++ RIGHT NOW"
                  => mk_action('cinnamon rolls', 1),
                "31337++" 
                  => mk_action('31337', 1),
                "db2--"
                => mk_action('db2', -1),

                # Perl::Modules
                'Acme::Read::Like::A::Monger++' 
                => mk_action('acme::read::like::a::monger', 1),

                # websites
                'search.cpan.org++' => mk_action('search.cpan.org', 1),
                
                # weird stuff
                '++++' => undef,
                '----' => undef,
                '+-+-' => undef,
                'this is totally irrelevant' => undef,
               );
                
plan tests => scalar keys %OPINIONS;

while (my ($k, $v) = each %OPINIONS) {
    my $got = parse($BOT, $USER, $k, $CHANNEL);
    my $exp = $v;
    
    is_same($got, $exp, "$k parsed to the correct action");
}

sub is_same {
    no warnings 'uninitialized';
    my $got      = shift;
    my $expected = shift;
    my $message  = shift;

    # undef == undef
    if (!defined $got && !defined $expected) {
        pass($message);
        return;
    }

    # something undef? not good.
    unless (defined $got && defined $expected){
        fail($message);
        diag("dump: ". Dumper(defined $got ? $got : $expected));
        return;
    }
    
    # compare two hashes
    my %g = %$got;
    my %x = %$expected;

    delete $g{message}; # we don't care about this really
    delete $x{message}; 
    
    foreach (keys %g, keys %x) { # make sure one hash doesn't have an extra key
        if ($g{$_} ne $x{$_}){
            fail($message);
            diag("Compare failed on key '$_'");
            diag("      got: ". $g{$_});
            diag(" expected: ". $x{$_});
            return;
        }
        $got->      $_; # make sure accessors work too
        $expected-> $_; 
    }
    
    # didn't fail in there? pass.
    pass($message);
    return;
}

sub mk_action {
    my $word   = shift;
    my $points = shift;
    my $reason = shift;

    return App::Ircxory::Robot::Action->
      new({ who     => $USER,
            channel => $CHANNEL,
            word    => $word,
            reason  => $reason,
            points  => $points,
          });
}
