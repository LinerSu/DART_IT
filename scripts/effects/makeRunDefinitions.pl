#!/usr/bin/perl

my $prefix = 'NOTEmay9';
my $rdout = '';

my %domName = (
  PolkaGrid => 'pg',
  Polka_ls => 'ls', 
  Polka_st => 'st',
  Oct => 'oct'
);
print "Adding run definitions:\n";
foreach my $evTrans (qw/true false/) {
foreach my $tracelen (qw/0 1 2/) {
foreach my $ifPart (qw/true false/) {
    # for ev-trans, only use TL=1 and ifPart=false
    next if $evTrans eq 'true' && ($tracelen ne '1' || $ifPart eq 'true');
foreach my $dom (qw/PolkaGrid Polka_ls Polka_st Oct/) {
    # CA says: "Although, there are some cases when with
    # ev-trans true, you need trace-len 2. Also, ev-trans
    # still doesn't work properly with if-part true"

    # CA on Mar 27: should now work
    # next if $ifPart eq 'true' and $evTrans eq 'true';

    next if $tracelen eq '2' and $evTrans eq 'false';
    my $rdName = join('-',
        $prefix,
        "TL$tracelen",
        "TP$ifPart",
        "DM$domName{$dom}",
        "TR".($evTrans eq 'true' ? 'trans' : 'direct')
    );
    print "   $rdName\.effects\n";
    my $thold = ($dom eq 'PolkaGrid' ? 'false' : 'true');
    $rdout .= <<EOT;
  <rundefinition name="$rdName">
    <option name="-ev-trans">$evTrans</option>
    <option name="-trace-len">$tracelen</option>
    <option name="-if-part">$ifPart</option>
    <option name="-out">0</option>
    <option name="-domain">$dom</option>
    <option name="-thold">$thold</option>
  </rundefinition> 
EOT
}
}
}
}

open OUT, ">benchmark-drift-autogenerated.xml" or die $!;
while(<DATA>) {
    if(/RUN_DEFINITIONS_HERE/) { print OUT $rdout; } else { print OUT $_; }
}
close OUT;
chmod 0666, "benchmark-drift-autogenerated.xml";
print "wrote: benchmark-drift-autogenerated.xml\n"

__DATA__
<?xml version="1.0"?>

<!--

AUTOGENERATED BY makeRunDefinitions.pl

-->
<!--
This file is part of BenchExec, a framework for reliable benchmarking:
https://github.com/sosy-lab/benchexec

SPDX-FileCopyrightText: 2007-2020 Dirk Beyer <https://www.sosy-lab.org>

SPDX-License-Identifier: Apache-2.0
-->

<!DOCTYPE benchmark PUBLIC "+//IDN sosy-lab.org//DTD BenchExec benchmark 2.3//EN" "https://www.sosy-lab.org/benchexec/benchmark-2.2.3dtd">
<!-- Example file for benchmark definition for BenchExec,
     using tool "cbmc" with a CPU time limit of 60s,
     1000 MB of RAM, and 1 CPU core.
     To use this file, CBMC needs to be on PATH
     and C programs from SV-COMP need to be available in directory programs/
     (or input files need to be changed). -->
<benchmark tool="drifttoolinfo.drift"
           timelimit="60s"
           hardtimelimit="90s"
           memlimit="1000 MB"
           cpuCores="1">

RUN_DEFINITIONS_HERE

  <tasks name="effects">
    <include>../../tests/effects/*.yml</include>
    <propertyfile>${taskdef_path}/${taskdef_name}.prp</propertyfile>
  </tasks>

</benchmark>