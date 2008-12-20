#!/usr/bin/perl -w
# perl Makefile.PL;make; time perl -Iblib/lib t/lots.t 10000 5000 0.01 1000000

use strict;
use warnings;
use Test::More; plan tests => 5;
use Bloom::Filter;
srand(007); #same every time

my $cap   = shift() || 10000;
my $tests = shift() || 5000;
my $erate = shift() || 0.01;         # 1%
my $max   = shift() || 1_000_000;

elapsed();
my $bf=Bloom::Filter->new( capacity => $cap, error_rate => $erate );elapsed("new");
my %h;$h{1+int(rand($max))}++ while keys(%h)<$cap;                  elapsed("init \%h");
my @k=sort keys %h;                                                 elapsed("Made ".@k." random keys, 1-$max");
$bf->add( @k );                                                     elapsed("Added ".@k." elements");
ok(@k==sum(map $bf->check($_),@k));                                 elapsed("Checked all ".@k." one by one");
ok(@k==sum($bf->check(@k)));                                        elapsed("Checked all ".@k." all at once");
my @test=map 1+int(rand($max)), 1..$tests;                          elapsed("Made ".@test." random testnumbers 1-$max");
my(@fapos,@faneg);
my $found1=0;
for(@test){
  my $check=$bf->check($_);
  $found1++ if $check;
  push @fapos,$_ if not exists $h{$_} and     $check;
  push @faneg,$_ if     exists $h{$_} and not $check;
}
elapsed("Checked ".@test." random items one by one, got ".@fapos." false positives and ".@faneg." false negatives.");
my $found2=sum($bf->check(@test));
ok(@faneg==0);
ok($found1==$found2);
my $erategot=@fapos/@test;
my $factor=$erategot/$erate;
ok($factor>=0.5 && $factor<=2, "Error-rate-factor = $factor, is within 0.5 - 2.0"); #hmm, to wide?
elapsed("Checked ".@test." random items all at once, found $found2 of them");
printf "Random tests: ".@test."   ".
       "Error rate wanted: $erate   ".
       "Error rate gotten: %0.5f   ".
       "Factor: %0.2f   ".
       "False positives: ".@fapos."   \n",
	$erategot,$factor;
printf "%-13s ".eval("\$bf->$_()")."\n","\u$_:" for qw/capacity error_rate length key_count on_bits salts/;


my $elapsed_time;
my $elapsed_time_last;
my $elapsed_start;
sub elapsed
{
  my $msg=shift()||'';
  $elapsed_time=time_fp();
  $elapsed_start||=$elapsed_time;
  my $r=sprintf("Elapsed: %8.3fs %10s  %s L%s: ",
                $elapsed_time - $elapsed_start,
                ($elapsed_time_last ? sprintf("%8.3fs",$elapsed_time-$elapsed_time_last)  : "".(time()-$^T)."s"),
                (caller())[0,2]).
	"$msg\n";
  $elapsed_time_last=$elapsed_time;
  print $r;
  return $r;
}

sub time_fp {
  eval{require Time::HiRes} or return time();
  my($sec,$mic)=Time::HiRes::gettimeofday();
  return $sec+$mic/1e6; #1e6 not portable?
}
sub sum { my $sum; $sum+=$_ for @_; $sum}