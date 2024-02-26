#!/usr/bin/perl

use strict;
use Data::Dumper;

# results/benchmark-coarmochi.2024-02-25_10-16-09.results.default.mochibenchmarks.csv

# results/results.2024-02-25_12-18-59.table.csv
# run set		drift-new-len0.effects	drift-new-len0.effects	drift-new-len0.effects	drift-new-len0.effects	drift-new-len1.effects	drift-new-len1.effects	drift-new-len1.effects	drift-new-len1.effects	drift-trans-len0.effects	drift-trans-len0.effects	drift-trans-len0.effects	drift-trans-len0.effects	drift-trans-len1.effects	drift-trans-len1.effects	drift-trans-len1.effects	drift-trans-len1.effects
sub cleanRes {
    my ($r) = @_;
    return '\Chk' if $r eq 'true';
    return '\TO' if $r eq 'TIMEOUT';
    return '\MO' if $r eq 'OUT OF MEMORY';
    return '\Unk' if $r eq 'unknown';
    return $r;    
}
my %run2tool = (
    'drift-new-len0.effects' => 'EDrift len0',
    'drift-new-len1.effects' => 'EDrift len1',
    'drift-trans-len0.effects' => 'Trans+Drift len0',
    'drift-trans-len1.effects' => 'Trans+Drift len1',
    'default.mochibenchmarks' => 'CPS+Mochi'
);
my $d;
sub parseResultsFile {
    my ($fn) = @_;
    open F, $fn or die "opening $fn - $!";
    # unfortunately the mochi output is a little different (one fewer column) then the other CSV
    my $isMochi = ($fn =~ /mochi/ ? 1 : 0);

    my @runSets; 
    while(<F>) {
        next if /\tstatus\t/;
        next if /^tool/;
        if (/^run set/) {
            @runSets = split /\t/, $_;
            shift @runSets;
            shift @runSets unless $isMochi;

        } else {
            my ($bench,@RCWMs) = split /\t/, $_;
            $bench =~ s/cps_// if $isMochi;
            $bench =~ s/\.y?ml$//;
            shift @RCWMs unless $isMochi;
            for(my $i=0; $i <= $#RCWMs; $i+=4) {
                $d->{$bench}->{$runSets[$i]}->{res} = $RCWMs[$i];
                $d->{$bench}->{$runSets[$i]}->{cpu} = $RCWMs[$i+1];
                $d->{$bench}->{$runSets[$i]}->{wall} = $RCWMs[$i+2];
                $d->{$bench}->{$runSets[$i]}->{mem} = $RCWMs[$i+3];
            }
            #my ($fn,$res,$cpu,$wall,$mem) = split /\t/, $_;
            # $fn =~ s/^cps_//;
            # $fn =~ s/_/\\_/g;
            # printf("%-30s & %-5s & %0.2f & %0.2f & %0.2f \\\\\n",
            #     $fn, cleanRes($res), $cpu, $wall, $mem);
        }
    }
}




parseResultsFile("results/benchmark-coarmochi.2024-02-25_10-16-09.results.default.mochibenchmarks.csv");
parseResultsFile("results/results.2024-02-25_12-18-59.table.csv");

my @TOOLS = qw/drift-new-len0.effects drift-new-len1.effects drift-trans-len1.effects drift-trans-len1.effects default.mochibenchmarks/;
print "{\\bf Bench} ";
foreach my $tool (@TOOLS) {
    print " & \\multicolumn{3}{|c|}{$run2tool{$tool}}";
}
print "\\\\ \n";
print "\\hline\\\\\n";
foreach my $b (keys %$d) {
    my $tt = $b; $tt =~ s/\_/\\_/g;
    $tt =~ s/negated/neg/;
    print "\\texttt{\\scriptsize $tt} ";
    foreach my $tool (@TOOLS) {
        printf("& %-5s & %3.2f & %3.2f ",
           cleanRes($d->{$b}->{$tool}->{res}),
           $d->{$b}->{$tool}->{cpu},
#           $d->{$b}->{$tool}->{wall},
           $d->{$b}->{$tool}->{mem});
    }
    print "\\\\ \n";
}

# while(<DATA>) {
#     next if /^tool/;
#     next if /^run set/;
#     next if /\tstatus\t/;
#     my ($fn,$res,$cpu,$wall,$mem) = split /\t/, $_;
#     $fn =~ s/^cps_//;
#     $fn =~ s/_/\\_/g;
#     printf("%-30s & %-5s & %0.2f & %0.2f & %0.2f \\\\\n",
#         $fn, cleanRes($res), $cpu, $wall, $mem);
# }

__DATA__
tool	coarmochi NO_VERSION_UTIL	coarmochi NO_VERSION_UTIL	coarmochi NO_VERSION_UTIL	coarmochi NO_VERSION_UTIL
run set	default.mochibenchmarks	default.mochibenchmarks	default.mochibenchmarks	default.mochibenchmarks
../../tests/effects/mochi/	status	cputime (s)	walltime (s)	memory (MB)
cps_acc-pos-net0-negated.ml	OUT OF MEMORY	39.561118434	39.52044827118516	999.997440
cps_acc-pos-net0-similar-negated.ml	OUT OF MEMORY	40.443142798	40.41010303609073	999.997440
cps_acc-pos-net0-similar.ml	TIMEOUT	900.251731749	900.2475049868226	454.119424
cps_acc-pos-net0.ml	TIMEOUT	900.254324895	900.2498775236309	448.516096
cps_all-ev-even-sink.ml	unknown	0.031445387	0.0340123288333416	35.680256
cps_assert-true.ml	unknown	4.797628357	4.7890766356140375	92.082176
cps_depend.ml	OUT OF MEMORY	57.696388143	57.63335299119353	999.997440
cps_disj.ml	OUT OF MEMORY	237.340026792	237.0736487712711	999.997440
cps_ho-shrink.ml	TIMEOUT	900.261575017	900.1133371777833	999.997440
cps_last-ev-even.ml	unknown	3.632835373	3.6285442896187305	99.291136
cps_max-min.ml	TIMEOUT	900.272918367	900.2402329705656	999.997440
cps_min-max.ml	TIMEOUT	900.2684614	900.2167596127838	999.997440
cps_order-irrel.ml	unknown	18.950768298	18.91433823108673	143.339520
cps_resource-analysis.ml	TIMEOUT	900.253579096	900.2900423351675	270.442496
cps_sum-appendix.ml	unknown	0.036942231	0.03894921950995922	36.855808
cps_sum-of-ev-even.ml	unknown	3.27330404	3.268652807921171	88.887296
cps_traffic_light_fo_simple.ml	OUT OF MEMORY	254.436113917	254.29541855305433	999.997440
table-generator results/benchmark-drift.2024-02-25_12-16-28.results.drift-new-len0.effects.xml.bz2 results/benchmark-drift.2024-02-25_12-16-28.results.drift-new-len1.effects.xml.bz2 results/benchmark-drift.2024-02-25_12-16-28.results.drift-trans-len0.effects.xml.bz2 results/benchmark-drift.2024-02-25_12-16-28.results.drift-trans-len1.effects.xml.bz2