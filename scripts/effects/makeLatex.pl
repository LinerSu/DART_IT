#!/usr/bin/perl

use strict;
use Data::Dumper;


######################################################################
# CONFIGURATION

# 1) Which CSVs were generated by table-generator
my @resultsfiles = (
    #"results/benchmark-coarmochi.2024-02-25_10-16-09.results.default.mochibenchmarks.csv",
    #"results/benchmark-coarmochi.2024-03-25_16-47-09.results.default.mochibenchmarks.csv",
    #"results/benchmark-coarmochi.2024-04-03_12-51-55.results.default.mochibenchmarks.csv",
    "results/benchmark-coarmochi.2024-05-09_09-54-42.results.default.mochibenchmarks.csv",
    #"results/results.2024-02-25_12-18-59.table.csv",
    #"results/results.2024-03-20_12-38-14.table.csv"
    #"results/results.2024-03-25_13-16-55.table.csv"
    #"results/results.2024-03-25_15-35-29.table.csv"
    #    "results/results.2024-04-03_12-36-18.table.csv"
    #"results/results.2024-04-04_10-01-41.table.csv"
    "results/results.2024-05-09_09-15-34.table.csv"
);

# 2) load the RunDefinitions defined in the autogen XML file
my @RUNDEFINITIONS = ('default.mochibenchmarks');
open T, "benchmark-drift-autogenerated.xml" or die $!;
while(<T>) {
    if (/rundefinition name="([^"]+)">/) {
        push @RUNDEFINITIONS, $1;
    }
}
close T;
print "- loaded rundef names: ".join(", ", @RUNDEFINITIONS)."\n";

# 3) which one to use for mochi?
my $MOCHI_RD = 'default.mochibenchmarks';

# 4) Give human-readible names for these rundefinitions for column headers:
sub run2tool {
    my ($rdName) = @_;
    return 'CPS+Mochi' if $rdName eq 'default.mochibenchmarks';
    if($rdName =~ /NOTE(.*)-TL(.*)-TP(.*)-DM(.*)-TR([^\.]*)(\.effects)?/) {
        my $tp = ($3 eq 'true' ? 'T' : 'F');
        my $isTrans = $5;
        return "\\humanCfg".$isTrans."{$1}{$2}{$tp}{$4}"
    } else {
        die "don't know how to parse rundef: $rdName\n";
    }
}
# my %run2tool = (
#     'drift-new-len0.effects' => 'EDrift len0',
#     'drift-new-len1.effects' => 'EDrift len1',
#     'drift-trans-len0.effects' => 'Trans+Drift len0',
#     'drift-trans-len1.effects' => 'Trans+Drift len1',
#     'default.mochibenchmarks' => 'CPS+Mochi',
#     'CA-March20.effects' => '3/20/24 TP',
#     'CA-March20-trans.effects' => '3/20/24 TP + trans'
# );
######################################################################
use List::Util qw(product);
use Math::Complex;
sub geometric_mean {
    my @numbers = @_; # Get the list of integers passed to the function
    return 0 unless @numbers; # Return 0 if the list is empty

    my $product = product(@numbers); # Calculate the product of all integers in the list
    my $n = scalar @numbers; # Count the total number of integers
    return sprintf("%0.1f", exp(log($product)/$n));
}
######################################################################

sub cleanRes {
    my ($r) = @_;
    return '\Chk' if $r eq 'true';
    return '\TO' if $r eq 'TIMEOUT';
    return '\MO' if $r eq 'OUT OF MEMORY';
    return '\Unk' if $r eq 'unknown';
    return $r;    
}
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
            next if $bench =~ /lics18-web/;
            next if $bench =~ /higher-order-disj/;
            next if $bench =~ /traffic/;
            next if $bench =~ /reentr/;
            $bench =~ s/cps_// if $isMochi;
            $bench =~ s/\.y?ml$//;
            shift @RCWMs unless $isMochi;
            for(my $i=0; $i <= $#RCWMs; $i+=4) {
                $d->{$bench}->{$runSets[$i]}->{res} = $RCWMs[$i];
                $d->{$bench}->{$runSets[$i]}->{cpu} = $RCWMs[$i+1];
                $d->{$bench}->{$runSets[$i]}->{wall} = $RCWMs[$i+2];
                $d->{$bench}->{$runSets[$i]}->{mem} = $RCWMs[$i+3];
                $d->{$bench}->{$runSets[$i]}->{rd}  = $runSets[$i];
            }
            #my ($fn,$res,$cpu,$wall,$mem) = split /\t/, $_;
            # $fn =~ s/^cps_//;
            # $fn =~ s/_/\\_/g;
            # printf("%-30s & %-5s & %0.2f & %0.2f & %0.2f \\\\\n",
            #     $fn, cleanRes($res), $cpu, $wall, $mem);
        }
    }
}

foreach my $fn (@resultsfiles) {
    parseResultsFile($fn);
}


sub newBest {
    my ($BEST,$bench,$rd) = @_;
    $d->{$bench}->{$BEST}->{res}  = $d->{$bench}->{$rd}->{res};
    $d->{$bench}->{$BEST}->{cpu}  = $d->{$bench}->{$rd}->{cpu};
    $d->{$bench}->{$BEST}->{wall} = $d->{$bench}->{$rd}->{wall};
    $d->{$bench}->{$BEST}->{mem}  = $d->{$bench}->{$rd}->{mem};
    $d->{$bench}->{$BEST}->{rd}   = $rd;
}
# compute the best (non-mochi) run set
foreach my $bench (sort keys %$d) {
    # choose a starting point for both BEST_TRANS and BEST_DRIFTEV
    # my $someRD = (grep($_ !~ /mochi/ && $_ =~ /trans/,keys %{$d->{$bench}}))[0];
    # newBest('BEST_TRANS',$bench,$someRD);
    # my $someRD = (grep($_ !~ /mochi/ && $_ !~ /trans/,keys %{$d->{$bench}}))[0];
    # newBest('BEST_DRIFTEV',$bench,$someRD);
    my $done = 0;
    foreach my $rd (keys %{$d->{$bench}}) {
        next if $rd =~ /BEST/;
        next if $rd =~ /mochi/i;
#        next unless $d->{$bench}->{$rd}->{res} eq 'true';
        # which are we improving?
        my $BEST = ($rd =~ /trans/i ? 'BEST_TRANS' : 'BEST_DRIFTEV');
        # we have nothing yet, so we take it
        if ($d->{$bench}->{$BEST}->{rd} !~ /[a-z]/) {
            if ($BEST eq 'BEST_DRIFTEV') { ++$done; die "bad" if $done++ > 1; }
            newBest($BEST,$bench,$rd);
        # does it improve because previously BEST coudln't prove it?
        } elsif ($d->{$bench}->{$BEST}->{res} ne 'true') {
            newBest($BEST,$bench,$rd);
        # does it improve because it's faster?
        } elsif ($d->{$bench}->{$rd}->{res} eq 'true'
                && $d->{$bench}->{$rd}->{cpu} < $d->{$bench}->{$BEST}->{cpu}) {
            newBest($BEST,$bench,$rd);
        } else {
            # warn "not better\n";
        }
    }
}
#print Dumper($d);

open EXT, ">exp-apx.tex" or die $!;
# print EXT "     ";
# foreach my $tool (@RUNDEFINITIONS) {
#     print EXT " & \\multicolumn{3}{|c||}{$run2tool{$tool}}";
# }
# print EXT "\\\\ \n";
# print EXT "{\\bf Bench} ";
# foreach my $tool (@RUNDEFINITIONS) {
#     print EXT " & {\\bf Res} & {\\bf CPU} & {\\bf Mem} ";
# }
# print EXT "\\\\ \n";
# print EXT "\\hline\n";
my $ct = 1;
foreach my $b (sort keys %$d) {
    my $tt = $b; $tt =~ s/\_/\\_/g;
    $tt =~ s/negated/neg/;
    print EXT "$ct. \\texttt{\\scriptsize $tt} \\\\\n"; ++ $ct;
    foreach my $tool (@RUNDEFINITIONS) {
        my $isBest = ($d->{$b}->{BEST_DRIFTEV}->{rd} eq $tool ? '\hl ' : '    ');
        print EXT sprintf("& $isBest %-5s & %3.2f & %3.2f & %s \\\\\n",
           cleanRes($d->{$b}->{$tool}->{res}),
           $d->{$b}->{$tool}->{cpu},
#           $d->{$b}->{$tool}->{wall},
           $d->{$b}->{$tool}->{mem},
           run2tool($tool)); # d->{$b}->{$tool}->{rd}));
    }
    print  EXT "\\hline\n";
}
close EXT;
print "wrote: exp-apx.tex\n";

### Generate paper body table showing only the best

open BODY, ">exp-body.tex" or die $!;
# print BODY "     ";
# foreach my $tool (@RUNDEFINITIONS) {
#     print BODY " & \\multicolumn{3}{|c||}{$run2tool{$tool}}";
# }
# print BODY "\\\\ \n";
# print BODY "{\\bf Bench} ";
# foreach my $tool (@RUNDEFINITIONS) {
#     print BODY " & {\\bf Res} & {\\bf CPU} & {\\bf Mem} ";
# }
# print BODY "\\\\ \n";
# print BODY "\\hline\n";
my @geos_mochi; my @geos_evtrans; my @geos_direct;
my $newOverMochi = 0; my $newOverTrans = 0; my $benchCount = 0; $ct = 1;
print Dumper($d->{overview1});
foreach my $b (sort keys %$d) {
    #next if $b =~ /amortized/;
    next if $b =~ /ho-shrink/; # old name;
    my $tt = $b; $tt =~ s/\_/\\_/g;
    $tt =~ s/negated/neg/;
    #warn "b: $b\n".Dumper($d->{$b});
    print BODY "$ct. \\texttt{\\scriptsize $tt} "; ++$ct;
    #warn "tool rd: ".Dumper($b,$d->{$b},$d->{$b}->{BEST_TRANS},$d->{$b}->{BEST_TRANS}->{rd});
    die "don't have a BEST_TRANS rundef for $b" unless $d->{$b}->{BEST_TRANS}->{rd} =~ /[a-z]/;
    die "don't have a $MOCHI_RD rundef for $b" unless $d->{$b}->{$MOCHI_RD}->{rd} =~ /[a-z]/;
    die "don't have a BEST_DRIFTEV rundef for $b" unless $d->{$b}->{BEST_DRIFTEV}->{rd} =~ /[a-z]/;
    # Trans-Drift
    print BODY sprintf("& %-5s & %3.2f & %3.2f & %s ",
           cleanRes($d->{$b}->{BEST_TRANS}->{res}),
           $d->{$b}->{BEST_TRANS}->{cpu},
           $d->{$b}->{BEST_TRANS}->{mem},
           run2tool($d->{$b}->{BEST_TRANS}->{rd}));
    # Trans-Mochi
    print BODY sprintf("& %-5s & %3.2f & %3.2f ",
           cleanRes($d->{$b}->{$MOCHI_RD}->{res}),
           $d->{$b}->{$MOCHI_RD}->{cpu},
           $d->{$b}->{$MOCHI_RD}->{mem});
    # DriftEV
    print BODY sprintf("& %-5s & %3.2f & %3.2f & %s \\\\ \n",
           cleanRes($d->{$b}->{BEST_DRIFTEV}->{res}),
           $d->{$b}->{BEST_DRIFTEV}->{cpu},
           $d->{$b}->{BEST_DRIFTEV}->{mem},
           run2tool($d->{$b}->{BEST_DRIFTEV}->{rd}));
    printf "best EDrift result for %-40s : %-10s : %s\n", $b, $d->{$b}->{BEST_DRIFTEV}->{res}, $d->{$b}->{BEST_DRIFTEV}->{rd};
    # save the runtimes for statistics
    push @geos_evtrans, $d->{$b}->{BEST_TRANS}->{cpu}
      if $d->{$b}->{BEST_TRANS}->{cpu} < 900 && $d->{$b}->{BEST_TRANS}->{cpu} > 0;
    push @geos_mochi, $d->{$b}->{$MOCHI_RD}->{cpu}
      if $d->{$b}->{$MOCHI_RD}->{cpu} < 900 && $d->{$b}->{$MOCHI_RD}->{cpu} > 0;
    push @geos_direct, $d->{$b}->{BEST_DRIFTEV}->{cpu}
      if $d->{$b}->{BEST_DRIFTEV}->{cpu} < 900 && $d->{$b}->{BEST_DRIFTEV}->{cpu} > 0;
    #
    $newOverMochi++ if $d->{$b}->{BEST_DRIFTEV}->{res} eq 'true' && $d->{$b}->{$MOCHI_RD}->{res} ne 'true';
    $newOverTrans++ if $d->{$b}->{BEST_DRIFTEV}->{res} eq 'true' && $d->{$b}->{BEST_TRANS}->{res} ne 'true';
    $benchCount++;
}
close BODY;
print "wrote: exp-body.tex\n";







### Generate trace partition comparison

# compute the best run set (only non-ev trans)
foreach my $bench (sort keys %$d) {
    # choose a starting point for both BEST_TRANS and BEST_DRIFTEV
    # my $someRD = (grep($_ !~ /mochi/ && $_ =~ /trans/,keys %{$d->{$bench}}))[0];
    # newBest('BEST_TRANS',$bench,$someRD);
    # my $someRD = (grep($_ !~ /mochi/ && $_ !~ /trans/,keys %{$d->{$bench}}))[0];
    # newBest('BEST_DRIFTEV',$bench,$someRD);
    
    foreach my $rd (keys %{$d->{$bench}}) {
        next if $rd =~ /BEST/;
        next if $rd =~ /mochi/i;
        next if $rd =~ /TRtrans/;
        my $BEST = ($rd =~ /TPfalse/i ? 'BEST_TPOFF' : 'BEST_TPON');
        # we have nothing yet, so we take it
        if (not defined $d->{$bench}->{$BEST}) {
            newBest($BEST,$bench,$rd);
        # does it improve because previously BEST coudln't prove it?
        } elsif ($d->{$bench}->{$BEST}->{res} ne 'true') {
            newBest($BEST,$bench,$rd);
        # does it improve because it's faster?
        } elsif ($d->{$bench}->{$rd}->{res} eq 'true'
                && $d->{$bench}->{$rd}->{cpu} < $d->{$bench}->{$BEST}->{cpu}) {
            newBest($BEST,$bench,$rd);
        } else {
            # warn "not better\n";
        }
    }
}

open TP, ">exp-tp.tex" or die $!;
$ct = 1;
my $newTPOverNoTP = 0;
my @geos_notp; my @geos_tp;
foreach my $b (sort keys %$d) {
    my $tt = $b; $tt =~ s/\_/\\_/g;
    $tt =~ s/negated/neg/;
    print TP "$ct. \\texttt{\\scriptsize $tt} "; ++$ct;
    #warn "tool rd: ".Dumper($b,$d->{$b},$d->{$b}->{BEST_TRANS},$d->{$b}->{BEST_TRANS}->{rd});
    # Best with Trace Part
    print TP sprintf("& %-5s & %3.2f & %3.2f & %s ",
           cleanRes($d->{$b}->{BEST_TPON}->{res}),
           $d->{$b}->{BEST_TPON}->{cpu},
           $d->{$b}->{BEST_TPON}->{mem},
           run2tool($d->{$b}->{BEST_TPON}->{rd}));
    # Best without Trace Part
    print TP sprintf("& %-5s & %3.2f & %3.2f & %s \\\\ \n",
           cleanRes($d->{$b}->{BEST_TPOFF}->{res}),
           $d->{$b}->{BEST_TPOFF}->{cpu},
           $d->{$b}->{BEST_TPOFF}->{mem},
           run2tool($d->{$b}->{BEST_TPOFF}->{rd}));

    # save the runtimes for statistics
    push @geos_tp, $d->{$b}->{BEST_TPON}->{cpu}
      if $d->{$b}->{BEST_TPON}->{cpu} < 900 && $d->{$b}->{BEST_TPON}->{cpu} > 0;
    push @geos_notp, $d->{$b}->{BEST_TPOFF}->{cpu}
      if $d->{$b}->{BEST_TPOFF}->{cpu} < 900 && $d->{$b}->{BEST_TPOFF}->{cpu} > 0;
    #
    $newTPOverNoTP++ if $d->{$b}->{BEST_TPON}->{res} eq 'true' && $d->{$b}->{BEST_TPOFF}->{res} ne 'true';
}
close TP;
print "wrote: exp-tp.tex\n";


use Statistics::Basic qw(:all);
open STATS, ">exp-stats.tex" or die $!;
print STATS join("\n", (
   ('\newcommand\expGMevtrans{'.geometric_mean(@geos_evtrans).'}'),
   ('\newcommand\expGMmochi{'.geometric_mean(@geos_mochi).'}'),
   ('\newcommand\expGMdirect{'.geometric_mean(@geos_direct).'}'),
   ('\newcommand\expSpeedupEvtrans{'.sprintf("%0.1f", geometric_mean(@geos_evtrans)/geometric_mean(@geos_direct)).'}'),
   ('\newcommand\expSpeedupMochi{'.sprintf("%0.1f", geometric_mean(@geos_mochi)/geometric_mean(@geos_direct)).'}'),
   ('\newcommand\expNewOverMochi{'.$newOverMochi.'}'),
   ('\newcommand\expNewOverTrans{'.$newOverTrans.'}'),
   ('\newcommand\expBenchCount{'.$benchCount.'}'),
   "% TP Improvements:",
   ('\newcommand\expTPGMoff{'.geometric_mean(@geos_tp).'}'),
   ('\newcommand\expTPGMon{'.geometric_mean(@geos_notp).'}'),
   ('\newcommand\expTPSpeedup{'.sprintf("%0.1f", geometric_mean(@geos_notp)/geometric_mean(@geos_tp)).'}'),
   ('\newcommand\expTPNew{'.$newTPOverNoTP.'}'),
))."\n";
close STATS;
print "wrote: exp-stats.tex\n" or die $!;


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
