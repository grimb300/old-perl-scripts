#!/usr/bin/perl

# Debug flag
$DBG = 0;

# Default input/output files
$INPUT_FILE = "MICKEY.log";
$OUTPUT_FILE = "analyze_MICKEY.log";

while ($#ARGV != -1) {
    my $arg = shift @ARGV;
    if ($arg eq "-d") {
        $DBG = 1;
    } elsif ($arg eq "-input") {
        $INPUT_FILE = shift @ARGV;
        $OUTPUT_FILE = "analyze_$INPUT_FILE";
    } else {
        die "ERROR: Illegal command line argument: %s\n", $arg;
    }
}

# Open the input file
open(INPUT_FILE, "<$INPUT_FILE") || die "Unable to read the input file: $INPUT_FILE";

# Open the output file
open(OUTPUT_FILE, ">$OUTPUT_FILE") || die "Unable to open output file: $OUTPUT_FILE";

# Array to hold the txn info
@BAR_txns = ();
@crwr_txns = ();
@cr_txns = ();

# Hashes that hold info on the creg read/write in progress
$BAR_in_prog = { 'valid' => 0 };
$crwr_in_prog = { 'valid' => 0 };
$cr_txn_in_prog = { 'valid' => 0 };

# Read the input file line-by-line
while (<INPUT_FILE>) {
    $line = $_;
    chomp $line;
    my $out_line = $line;

    # Check to see if line is the start of a CRREAD or CRWRITE request
    # FIXME: Need to detect posted writes and ignore or special case
    if ($line =~ /^\| ([0-9]+)\.00 ns\s*\| fabric\s*\| (CRREAD|CRWRITE)\s*\| N \|.*destination=0x([0-9A-F][0-9A-F])/) {
        # Get the necessary info out of the line
        my $start_time = $1;
        my $opcode = $2;
        my $dest = hex($3);

        # Check if there is already a transaction in progress
        if (${$cr_txn_in_prog}{'valid'}) {
            # Flag an error
            $out_line .= sprintf("\nERROR: Saw %s destination thingy when a %s is already in progress",
                                 $opcode, ${$cr_txn_in_prog}{'opcode'});
        } else {
            ${$cr_txn_in_prog}{'valid'}  = 1;
            ${$cr_txn_in_prog}{'dest'}   = $dest;
            ${$cr_txn_in_prog}{'opcode'} = $opcode;
            ${$cr_txn_in_prog}{'start'}  = $start_time;
        }

        # Print the hash
        if ($DBG) { $out_line .= "\n".&print_txn_rec($cr_txn_in_prog); }
    } elsif (${$cr_txn_in_prog}{'valid'} and
             ($line =~ /\| fabric\s*\| (CRREAD|CRWRITE)\s*\| N \|.*source=0x([0-9A-F][0-9A-F])/)) {
        my $opcode = $1;
        my $src = hex($2);
        # Check that the opcode matches the open transaction
        if ($opcode ne ${$cr_txn_in_prog}{'opcode'}) {
            $out_line .= sprintf("\nERROR: Saw %s source thingy but a %s transaction is open",
                                 $opcode, ${$cr_txn_in_prog}{'opcode'});
        }
        # Check that the source is huey
        if (not ((0x46 <= $src) and ($src <= 0x4A))) {
            $out_line .= sprintf("\nERROR: Saw %s source thingy that is not huey (0x%x)", $opcode, $src);
        }
        ${$cr_txn_in_prog}{'src'} = $src;

        # Print the hash
        if ($DBG) { $out_line .= "\n".&print_txn_rec($cr_txn_in_prog); }
    } elsif (${$cr_txn_in_prog}{'valid'} and
             (${$cr_txn_in_prog}{'opcode'} eq "CRREAD") and
             ($line =~ /fabric.*CRREAD.*addr\[15:8\]/)) {

        # Print the hash
        if ($DBG) { $out_line .= "\n".&print_txn_rec($cr_txn_in_prog); }
    } elsif (${$cr_txn_in_prog}{'valid'} and
             (${$cr_txn_in_prog}{'opcode'} eq "CRWRITE") and
             ($line =~ /fabric.*CRWRITE.*data\[31:24\]/)) {

        # Print the hash
        if ($DBG) { $out_line .= "\n".&print_txn_rec($cr_txn_in_prog); }
    } elsif (${$cr_txn_in_prog}{'valid'} and
             (${$cr_txn_in_prog}{'opcode'} eq "CRREAD") and
             ($line =~ /agent.*FOO.*destination=0x([0-9A-F][0-9A-F])/)) {
        my $dest = hex($1);
        # Check that the destination is huey
        if (not ((0x46 <= $dest) and ($dest <= 0x4A))) {
            $out_line .= sprintf("\nERROR: Saw FOO destination thingy that is not huey (0x%x)", $dest);
        }
        # Check that the destination matches the source of the currently open BAR
        if ($dest != ${$cr_txn_in_prog}{'src'}) {
            ${$cr_txn_in_prog}{'poison'} = 1;
            $out_line .= sprintf("\nCMP_POISONED: Saw FOO destination thingy (0x%x) that does not mach source of open CRREAD (0x%x)",
                                 $dest, ${$cr_txn_in_prog}{'src'});
        }

        # Print the hash
        if ($DBG) { $out_line .= "\n".&print_txn_rec($cr_txn_in_prog); }
    } elsif (${$cr_txn_in_prog}{'valid'} and
             (${$cr_txn_in_prog}{'opcode'} eq "CRWRITE") and
             ($line =~ /agent.*CMP .*destination=0x([0-9A-F][0-9A-F])/)) {
        my $dest = hex($1);
        # Check that the destination is huey
        if (not ((0x46 <= $dest) and ($dest <= 0x4A))) {
            $out_line .= sprintf("\nERROR: Saw Cmp destination thingy that is not huey (0x%x)", $dest);
        }
        # Check that the destination matches the source of the currently open BAR
        if ($dest != ${$cr_txn_in_prog}{'src'}) {
            ${$cr_txn_in_prog}{'poison'} = 1;
            $out_line .= sprintf("\nCMP_POISONED: Saw Cmp destination thingy (0x%x) that does not mach source of open CRWRITE (0x%x)",
                                 $dest, ${$cr_txn_in_prog}{'src'});
        }

        # Print the hash
        if ($DBG) { $out_line .= "\n".&print_txn_rec($cr_txn_in_prog); }
    } elsif (${$cr_txn_in_prog}{'valid'} and
             (${$cr_txn_in_prog}{'opcode'} eq "CRREAD") and
             ($line =~ /agent.*FOO.*source=0x([0-9A-F][0-9A-F])/)) {
        my $src = hex($1);
        # Check that the source matches the destination of the currently open BAR
        if ($src != ${$cr_txn_in_prog}{'dest'}) {
            ${$cr_txn_in_prog}{'poison'} = 1;
            $out_line .= sprintf("\nCMP_POISONED: Saw FOO source thingy (0x%x) that does not mach destination of open CRREAD (0x%x)",
                                 $src, ${$cr_txn_in_prog}{'dest'});
        }

        # Print the hash
        if ($DBG) { $out_line .= "\n".&print_txn_rec($cr_txn_in_prog); }
    } elsif (${$cr_txn_in_prog}{'valid'} and
             (${$cr_txn_in_prog}{'opcode'} eq "CRWRITE") and
             ($line =~ /agent.*CMP .*source=0x([0-9A-F][0-9A-F])/)) {
        my $src = hex($1);
        # Check that the source matches the destination of the currently open BAR
        if ($src != ${$cr_txn_in_prog}{'dest'}) {
            ${$cr_txn_in_prog}{'poison'} = 1;
            $out_line .= sprintf("\nCMP_POISONED: Saw Cmp source thingy (0x%x) that does not mach destination of open CRWRITE (0x%x)",
                                 $src, ${$cr_txn_in_prog}{'dest'});
        }

        # Print the hash
        if ($DBG) { $out_line .= "\n".&print_txn_rec($cr_txn_in_prog); }
    } elsif (${$cr_txn_in_prog}{'valid'} and
             (${$cr_txn_in_prog}{'opcode'} eq "CRREAD") and
             ($line =~ /^\| ([0-9]+)\.00 ns.*agent.*FOO.*data\[31\:24\]/)) {

        my $end_time = $1;
        if (${$cr_txn_in_prog}{'poison'}) {
            $out_line .= "\nCMP_POISONED: Poisoned completion is done";
            ${$cr_txn_in_prog}{'poison'} = 0;
        } else {
            ${$cr_txn_in_prog}{'end'} = $end_time;
            # Print the hash
            if ($DBG) { $out_line .= "\n".&print_txn_rec($cr_txn_in_prog); }

            # If we get this far save the record and create a new one
            push @cr_txns, $cr_txn_in_prog;
            $cr_txn_in_prog = { 'valid' => 0 };
        }
        # Print the hash
        if ($DBG) { $out_line .= "\n".&print_txn_rec($cr_txn_in_prog); }
    } elsif (${$cr_txn_in_prog}{'valid'} and
             (${$cr_txn_in_prog}{'opcode'} eq "CRWRITE") and
             ($line =~ /^\| ([0-9]+)\.00 ns.*agent.*CMP .*eh0/)) {

        my $end_time = $1;
        if (${$cr_txn_in_prog}{'poison'}) {
            $out_line .= "\nCMP_POISONED: Poisoned completion is done";
            ${$cr_txn_in_prog}{'poison'} = 0;
        } else {
            ${$cr_txn_in_prog}{'end'} = $end_time;
            # Print the hash
            if ($DBG) { $out_line .= "\n".&print_txn_rec($cr_txn_in_prog); }

            # If we get this far save the record and create a new one
            push @cr_txns, $cr_txn_in_prog;
            $cr_txn_in_prog = { 'valid' => 0 };
        }
        # Print the hash
        if ($DBG) { $out_line .= "\n".&print_txn_rec($cr_txn_in_prog); }
    }

    print OUTPUT_FILE $out_line."\n";

}

# End of the file, analyze the transactions
my %num_txns;
my %total_time;
print OUTPUT_FILE "BAR/Wr analysis:\n";
foreach (@cr_txns) {
    my $src  = &port_decode(${$_}{'src'});
    my $dest = &port_decode(${$_}{'dest'});
    my $txn_time = ${$_}{'end'} - ${$_}{'start'};
    my $tag = sprintf("%s_to_%s_%s", $src, $dest, ${$_}{'opcode'});
    $num_txns{$tag} += 1;
    $total_time{$tag} += $txn_time;
#    print OUTPUT_FILE &print_txn_rec($_)."\n";
}
# Print out the results
printf OUTPUT_FILE "%25s  %5s  %8s  %4s\n", "TxnType", "Num", "Total(ns)", "Avg(ns)";
foreach (sort keys %num_txns) {
    printf OUTPUT_FILE "%25s  %5d  %8d  %4d\n", $_, $num_txns{$_}, $total_time{$_}, ($total_time{$_}/$num_txns{$_});
};

sub port_decode {
    my $in_port = shift;
    my $out_str = "UNKNOWN";
    if    ($in_port == 0x25) { $out_str = "louie"; }
    elsif ($in_port == 0x41) { $out_str = "dewey"; }
    elsif ($in_port == 0x44) { $out_str = "donald"; }
    elsif ($in_port == 0x46) { $out_str = "huey" }
    elsif ($in_port == 0x47) { $out_str = "huey" }
    elsif ($in_port == 0x48) { $out_str = "huey" }
    elsif ($in_port == 0x49) { $out_str = "huey" }
    elsif ($in_port == 0x4A) { $out_str = "huey" }
    elsif ($in_port == 0x4B) { $out_str = "Bunit" }
    elsif ($in_port == 0x4C) { $out_str = "Bunit" }
    elsif ($in_port == 0x4D) { $out_str = "Aunit" }

    return $out_str;
}

sub print_txn_rec {
    my $txn_rec = shift;
    my $ret_str = sprintf("%s: valid: %s, src: %s, dest: %s, opcode: %s, start: %s, end: %s, poison: %s",
                          $txn_rec,
                          (${$txn_rec}{'valid'})           ? "TRUE"                                 : "FALSE",
                          (${$txn_rec}{'src'}    ne undef) ?
                              sprintf("%s (0x%x)", &port_decode(${$txn_rec}{'src'}), ${$txn_rec}{'src'})    : "UNDEF",
                          (${$txn_rec}{'dest'}   ne undef) ?
                              sprintf("%s (0x%x)", &port_decode(${$txn_rec}{'dest'}), ${$txn_rec}{'dest'})    : "UNDEF",
                          (${$txn_rec}{'opcode'} ne undef) ? ${$txn_rec}{'opcode'}                  : "UNDEF",
                          (${$txn_rec}{'start'}  ne undef) ? sprintf("%d ns", ${$txn_rec}{'start'}) : "UNDEF",
                          (${$txn_rec}{'end'}    ne undef) ? sprintf("%d ns", ${$txn_rec}{'end'})   : "UNDEF",
                          (${$txn_rec}{'poison'})          ? "TRUE"                                 : "FALSE");

    # If this txn is done, print the results
    if ((${$txn_rec}{'start'} ne undef) and (${$txn_rec}{'end'} ne undef)) {
        $ret_str .= sprintf("\nResults: TxnType: %s, TxnTime: %d",
                            sprintf("%s_to_%s_%s", &port_decode(${$txn_rec}{'src'}),
                                                   &port_decode(${$txn_rec}{'dest'}),
                                                   ${$txn_rec}{'opcode'}),
                            (${$txn_rec}{'end'} - ${$txn_rec}{'start'}))
    }
    return $ret_str;
}

sub find_first_unknown_src {
#    print OUTPUT_FILE "txns has $#txns elements\n";
    foreach $txn_rec (@txns) {
        if (${$txn_rec}{'src'} eq undef) {
#            print OUTPUT_FILE "found match: $txn_rec\n";
#            print OUTPUT_FILE "$_\t=> $txn_rec->{$_}\n" for keys %{$txn_rec};
            return $txn_rec;
        }
    }

    # If we make it this far, flag an error
    print OUTPUT_FILE "ERROR: did not find a txn record without a source\n";
}
