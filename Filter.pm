package Bloom::Filter;

use strict;
use warnings;
use Carp;
use Digest::MD5 qw/md5/;

our $VERSION = '1.1';

=head1 NAME
    
Bloom::Filter - Sample Perl Bloom filter implementation
    
=head1 DESCRIPTION

A Bloom filter is a probabilistic algorithm for doing existence tests
in less memory than a full list of keys would require.  The tradeoff to
using Bloom filters is a certain configurable risk of false positives. 
This module implements a simple Bloom filter with configurable capacity
and false positive rate. Bloom filters were first described in a 1970 
paper by Burton Bloom, see L<http://portal.acm.org/citation.cfm?id=362692&dl=ACM&coll=portal>.

=head1 SYNOPSIS

	use Bloom::Filter

	my $bf = Bloom::Filter->new( capacity => 10, error_rate => .001 );

	$bf->add( @keys );

	while ( <> ) {
		chomp;
		print "Found $_\n" if $bf->check( $_ );
	}

=head1 CONSTRUCTORS

=over 

=item new %PARAMS

Create a brand new instance.  Allowable params are C<error_rate>, C<capacity>.

=cut

sub new 
{
	my ( $class, %params ) = @_;

	my $self = 
	{  
		 # some defaults
		 error_rate     => 0.001, 
		 capacity       => 100, 
			 
		 %params,
		 
		 # internal data
		 key_count      => 0,
		 filter_length 	=> 0,
		 num_hash_funcs => 0,
		 salts 	        => [],
	};
	bless $self, $class;
	$self->init();
	return $self;
}


=item init

Calculates the best number of hash functions and optimum filter length,
creates some random salts, and generates a blank bit vector.  Called
automatically by constructor.

=cut

sub init 
{
	my ( $self ) = @_;
	
	# some sanity checks
	croak "Capacity must be greater than zero" unless $self->{capacity};
	croak "Error rate must be greater than zero" unless $self->{error_rate};
	croak "Error rate cannot exceed 1" unless $self->{error_rate} < 1;
                                     	
	my ( $length, $num_funcs ) = $self->_calculate_shortest_filter_length
	    ($self->{capacity}, $self->{error_rate} );
	
	$self->{num_hash_funcs} = $num_funcs;
	$self->{filter_length} = $length;
	
	# create some random salts;
	my %collisions;
	while ( scalar keys %collisions < $self->{num_hash_funcs} ) {
		$collisions{rand()}++;
	}
	$self->{salts} = [ keys %collisions ];
	
	# make an empty filter
	$self->{filter} = pack( "b*", '0' x $self->{filter_length} );
	
	# make some blank vectors to use
	$self->{blankvec} = pack( "N", 0 ); 
	
	return 1;
}


=back

=head1 ACCESSORS

=over 

=item capacity

Returns the total capacity of the Bloom filter

=cut

sub capacity { $_[0]->{capacity} };

=item error_rate

Returns the configured maximum error rate

=cut

sub error_rate { $_[0]->{error_rate} };

=item length

Returns the length of the Bloom filter in bits

=cut

sub length { $_[0]->{filter_length} };

=item key_count

Returns the number of items currently stored in the filter

=cut

sub key_count { $_[0]->{key_count} };


=item on_bits

Returns the number of 'on' bits in the filter

=cut

sub on_bits 
{
	my ( $self ) = @_;
	return unless $self->{filter};
	return unpack( "%32b*",  $self->{filter})
}

=item salts 

Returns the list of salts used to create the hash functions

=cut

sub salts 
{ 
	my ( $self ) = @_;
	return unless exists $self->{salts}
		and ref $self->{salts}
		and ref $self->{salts} eq 'ARRAY';

	return @{ $self->{salts} };
}


=back

=head1 PUBLIC METHODS

=over

=item add @KEYS

Adds the list of keys to the filter.   Will fail, return C<undef> and complain
if the number of keys in the filter exceeds the configured capacity.

=cut

sub add 
{
  my ( $self, @keys ) = @_;
  return unless @keys;
  my $hashnum = @{ $self->{salts} } or croak "No salts found, cannot make bitmask";
  my $len=$self->{filter_length} or  croak "Filter length is undefined";
  for my $key ( @keys ) {
    $self->{key_count} >= $self->{capacity} and carp "Exceeded filter capacity" and return;
    $self->{key_count}++;
    my @hash; push @hash, unpack "N*", md5($key,0+@hash) while @hash<$hashnum;
    vec($self->{filter}, shift(@hash) % $len, 1) = 1 for 1..$hashnum;
  }
  return 1;
}



=item check @KEYS

Checks the provided key list against the Bloom filter,
and returns a list of equivalent length, with true or
false values depending on whether there was a match.

=cut 

sub check 
{	
  my ( $self, @keys ) = @_;
  return unless @keys;
  my $hashnum = 0+@{ $self->{salts} } or croak "No salts found, cannot make bitmask";
  my $len=$self->{filter_length}  or croak "Filter length is undefined";
  my $wa=wantarray();
  return map {
    my $key=$_;
    my $match = 1; # match if every bit is on
    my @hash; push @hash, unpack "N*", md5($key,0+@hash) while @hash<$hashnum;
    vec($self->{filter},shift(@hash)%$len,1) or $match=0 or last for 1..$hashnum;
    return $match if not $wa;
    $match;
  } @keys;
}




=back

=head1 INTERNAL METHODS

=over


=item _calculate_shortest_filter_length CAPACITY ERR_RATE

Given a desired error rate and maximum capacity, returns the optimum
combination of vector length (in bits) and number of hash functions
to use in building the filter, where "optimum" means shortest vector length.

=cut

sub _calculate_shortest_filter_length 
{
        my ( $self, $num_keys, $error_rate ) = @_;
        my $lowest_m;
        my $best_k = 1;

        foreach my $k ( 1..100 ) {
                my $m = (-1 * $k * $num_keys) / 
                        ( log( 1 - ($error_rate ** (1/$k))));

                if ( !defined $lowest_m or ($m < $lowest_m) ) {
                        $lowest_m = $m;
                        $best_k   = $k;
                }
        }
        $lowest_m = int( $lowest_m ) + 1;
        return ( $lowest_m, $best_k );
} 



=item _get_cells KEY

Given a key, hashes it using the list of salts and returns 
an array of cell indexes corresponding to the key.

Inlined in add() and check(), no longer used internally.

=cut

sub _get_cells 
{
  my ( $self, $key ) = @_;
  croak "Filter length is undefined" unless $self->{filter_length};
  my $hashnum = @{ $self->{salts} } or croak "No salts found, cannot make bitmask";
  my @hash; push @hash, unpack "N*", md5($key,0+@hash) while @hash<$hashnum;
  return [ map shift(@hash) % $self->{filter_length}, 1..$hashnum ];
}

=back

=head1 AUTHOR

Maciej Ceglowski E<lt>maciej@ceglowski.comE<gt>

=head1 CHANGELOG 

Feb 2007 big speedup by Dmitriy Ryaboy E<lt>dmitriy.ryaboy@ask.comE<gt> (thanks!) 

Dec 2008 Version 1.0 -> 1.1. Up to eight times faster*) by Kjetil Skotheim E<lt>kjetil.skotheim@usit.uio.noE<gt> by using and reusing MD5s instead of too many SHA1-calls. Also perl-speedup.

*) time perl -Iblib/lib t/lots.t 10000 5000 0.01 1000000

=head1 COPYRIGHT AND LICENSE

(c) 2004 Maciej Ceglowski

This is free software, distributed under version 2
of the GNU Public License (GPL).

=cut

1;

