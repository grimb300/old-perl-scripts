#!/usr/bin/perl

# Debug flag
$DBG = 0;
$HELP = 0;

# Default input/output files
$INPUT_FILE = "injections.list";
$OUTPUT_FILE = "analyzed_injections.log";

# Parse the command line opts
while ($#ARGV != -1) {
    my $arg = shift @ARGV;
    if ($arg eq "-d") {
        $DBG = 1;
    } elsif ($arg eq "-input") {
        $INPUT_FILE = shift @ARGV;
    } elsif ($arg eq "-output") {
        $OUTPUT_FILE = shift @ARGV;
    } elsif (($arg eq "-h")    ||
             ($arg eq "-help") ||
             ($arg eq "--help")) {
        $HELP = 1;
    } else {
        sprintf("ERROR: Illegal command line argument: %s\n", $arg);
        $HELP = 1;
    }
}

# Print out the help if necessary
if ($HELP) {
    &help;
    exit(1);
}

# Check the existance of the input file
if (-e $INPUT_FILE) {
    # Cool, the file exists, do nothing special
} elsif (-e $INPUT_FILE.".gz") {
    # The gzipped version exists, change $INPUT_FILE
    $INPUT_FILE = $INPUT_FILE.".gz";
} else {
    die sprintf("ERROR: No input file, neither %s or %s exist\n", $INPUT_FILE, $EMU_INPUT_FILE);
}

# Now open it (special handling for gzipped files)
if ($INPUT_FILE =~ /\.gz$/) {
    open(INPUT_FILE, "gunzip -c $INPUT_FILE |") || die "Unable to read the input file: $INPUT_FILE";
} else {
    open(INPUT_FILE, "<$INPUT_FILE") || die "Unable to read the input file: $INPUT_FILE";
}

# Open the output file
open(OUTPUT_FILE, ">$OUTPUT_FILE") || die "Unable to open output file: $OUTPUT_FILE";

# Subroutine to print out the line
sub print_line {
    return "ERROR: I do not know how to print yet";
    my $fields = shift(@_);
    # If this is a non-emu test, the time is in ps instead of ns, fix that here
    # But don't do it if it is the header ;-)
    if (($EMU_MODE == 0) && ($$fields{"time"} ne "TIME")) {
        $$fields{"time"} = substr $$fields{"time"}, 0, -3;
    }
    return sprintf "| %8s | %-15s | %-${max_string_len}s | %-${max_string_len}s | %-${max_string_len}s | %-${max_string_len}s |\n",
           $$fields{"time"}, $$fields{"mickey"}, $$fields{"minnie"}, $$fields{"goofy"}, $$fields{"sr_grp2"}, $$fields{"sr_grp3"};
}

# Variables so we know where in the file we are
my $in_lng_forces = 0;
my $in_ext_forces = 0;
my $in_event_list      = 0;
# Hashes holding the signal info
my @lng_header;
my %lng_forces;
my @ext_header;
my %ext_forces;
my %forces;
# Counters
my $total_lng_forces  = 0;
my $unique_lng_forces = 0;
my $tb_lng_forces     = 0;
my $total_ext_forces  = 0;
my $unique_ext_forces = 0;
my $tb_ext_forces     = 0;
my $total_forces  = 0;
my $unique_forces = 0;
my $tb_forces     = 0;
# Hash counting lanuage forces per file
my %forces_per_file;
my %unique_forces_per_file;
my %used_forces_per_file;
# Hash counting unique forces per partition
my %partition_cnt;
# Counters for the rtl force types
my $rtlFrcCnt_type1 = 0;
my $rtlFrcCnt_type2 = 0;
my $rtlFrcCnt_type3 = 0;
my $rtlFrcCnt_type4 = 0;
my $rtlFrcCnt_type5 = 0;
my $rtlFrcCnt_type6 = 0;
my $rtlFrcCnt_type7 = 0;
my $rtlFrcCnt_type8 = 0;
my $rtlFrcCnt_type9 = 0;
my $rtlFrcCnt_type10 = 0;
my $rtlFrcCnt_type11 = 0;
my $rtlFrcCnt_type12 = 0;
my $rtlFrcCnt_type13 = 0;
my $rtlFrcCnt_type14 = 0;
my $rtlFrcCnt_type15 = 0;
my $rtlFrcCnt_type16 = 0;
# Parse the INPUT_FILE
while (<INPUT_FILE>) {
    $line = $_;

    # If we're not in any section, look for the section headers
    if (($in_lng_forces == 0) && ($in_ext_forces == 0) && ($in_event_list == 0)) {
        if    ($line =~ /Language Forces/)    { $in_lng_forces = 1; }
        elsif ($line =~ /External Forces/)    { $in_ext_forces = 1; }
        elsif ($line =~ /Event List Section/) { $in_event_list = 1; }
        else                                  { next; }
        if ($DBG) { print "Saw section:\n$line"; }
    }
    # In "Language Forces" section
    elsif ($in_lng_forces == 1) {
        # Blank lines are skipped and reset the section if forces have been parsed
        if ($line =~ /^\s*$/) {
            if (scalar(keys(%forces)) > 0) {
                if ($DBG) {
                    printf "There are %d language forces\n", $total_lng_forces;
                    printf "There are %d unique forces\n",   $unique_lng_forces;
                    printf "There are %d entries in the hash\n", scalar(keys(%forces));
                }
                $in_lng_forces = 0;
                if ($DBG) { print "Reset Language Forces section:\n$line"; }
            }
            else { if ($DBG) { print "Saw errant blank line:\n$line"; } }
            next;
        }
        # Parse the non-blank lines
        else {
            # The expectation of this split is:
            #    $fields[0] => the signal ID
            #    $fields[1] => the signal name
            #    $fields[2] => the testbench module
            #    $fields[3] => the file containing the force
            #    $fields[4] => the line number in the file
            #
            my @fields = split /\s+/, $line;
            # Error checking and special case
            # If number of fields is less than 5, then throw error
            if (scalar(@fields) < 5) { print "Error! Bad line format:\n$line"; exit; }
            # If greater than 5, assume the signal name contains spaces (special case), collapse them
            if (scalar(@fields) > 5) {
                my $old_target = $fields[1];
                my $new_target = $fields[1];
                for ($i=2; $i<(scalar(@fields)-3); $i++) {
                    $old_target .= " ".$fields[$i];
                    $new_target .=     $fields[$i];
                }
                if ($DBG) {
                    print "Found special case:\n\told: $old_target\n\tnew: $new_target\n";
                }

                # Fix the @fields array with the collapsed target
                $fields[1] = $new_target;
                $fields[2] = $fields[scalar(@fields)-3];
                $fields[3] = $fields[scalar(@fields)-2];
                $fields[4] = $fields[scalar(@fields)-1];
                if ($DBG) {
                    print "The collapsed line is\n$fields[0] $fields[1] $fields[2] $fields[3] $fields[4]\n";
                }
            }

            # Skip the headers
            if (($fields[0] eq "ID") && ($fields[1] eq "Target")) {
                for ($i=0; $i<scalar(@fields); $i++) {
                    $lng_header[$i] = $fields[$i];
                    if ($DBG) { print "Saw the header: $fields[$i]\n"; }
                }
                if ($DBG) { print "Saw the header:\n$line"; }
            } else {
                # Count the forces per file
                $forces_per_file{$fields[3]}++;

                # Count the total number of forces
                $total_lng_forces++;
                $total_forces++;
                # Populate %forces if unique
                if (not defined $forces{$fields[0]}) {
                    # Count the forces per file
                    $unique_forces_per_file{$fields[3]}++;

                    # Count the unique forces
                    $unique_lng_forces++;
                    $unique_forces++;

                    # Assume the force is an RTL signal
                    my $force_type = "LANGUAGE";
                    # If the signal isn't in a partition or at toplevel soc, it is a TB signal
                    if (($fields[1] !~ /^soc_tb\.soc\.par/) &&
                        ($fields[1] !~ /^soc_tb\.soc\.\w+$/)) {
                        $force_type = "LANGUAGE_TB";
                        $tb_lng_forces++;
                        $tb_forces++;
                        if ($DBG) { print "This target is not RTL $fields[1]\n"; }
                    }
                    $forces{$fields[0]} = { "TYPE"         => $force_type,
                                            "EVENT_CNT"    => 0,
                                            $lng_header[1] => $fields[1],
                                            $lng_header[2] => $fields[2],
                                            $lng_header[3] => $fields[3],
                                            $lng_header[4] => $fields[4]  };
                }
            }
        }
    }
    # In "External Forces" section
    elsif ($in_ext_forces == 1) {
        # Blank lines are skipped and reset the section if forces have been parsed
        if ($line =~ /^\s*$/) {
            if (scalar(keys(%forces)) > $unique_lng_forces) {
                if ($DBG) {
                    printf "There are %d external forces\n", $total_ext_forces;
                    printf "There are %d unique forces\n",   $unique_ext_forces;
                    printf "There are %d entries in the hash\n", scalar(keys(%forces));
                }
                $in_ext_forces = 0;
                if ($DBG) { print "Reset External Forces section:\n$line"; }
            }
            else { if ($DBG) { print "Saw errant blank line:\n$line"; } }
            next;
        }
        # Parse the non-blank lines
        else {
            my @fields = split /\s+/, $line;
            if (scalar(@fields) != 2) { print "Error! Bad line format:\n$line"; exit; }

            # Skip the headers
            if (($fields[0] eq "ID") && ($fields[1] eq "Target")) {
                for ($i=0; $i<scalar(@fields); $i++) {
                    $ext_header[$i] = $fields[$i];
                    if ($DBG) { print "Saw the header: $fields[$i]\n"; }
                }
                if ($DBG) { print "Saw the header:\n$line"; }
            } else {
                $total_ext_forces++;
                $total_forces++;
                # Populate %forces if unique
                if (not defined $forces{$fields[0]}) {
                    $unique_ext_forces++;
                    $unique_forces++;

                    # Assume the force is an RTL signal
                    my $force_type = "EXTERNAL";
                    # If the signal isn't in a partition or at toplevel soc, it is a TB signal
                    if (($fields[1] !~ /^soc_tb\.soc\.par/) &&
                        ($fields[1] !~ /^soc_tb\.soc\.\w+$/)) {
                        $force_type = "EXTERNAL_TB";
                        $tb_ext_forces++;
                        $tb_forces++;
                        if ($DBG) { print "This target is not RTL $fields[1]\n"; }
                    }
                    $forces{$fields[0]} = { "TYPE"         => $force_type,
                                            "EVENT_CNT"    => 0,
                                            $ext_header[1] => $fields[1]  };
                } else {
                    if ($DBG) { printf "This signal was already in the forces list (%s) %s\n", $fields[0], $fields[1]; }
                }

                # Lets analyze the RTL signals being forced
                if ($forces{$fields[0]}{"TYPE"} eq "EXTERNAL") {
                    # Filter out and count known types of forces
                    my $full_path = $forces{$fields[0]}{"Target"};
                    my @split_path = split /\./, $forces{$fields[0]}{"Target"};
                    if    ($full_path =~ /type1$/) { $rtlFrcCnt_type1++; }
                    elsif ($full_path =~ /type2$/) { $rtlFrcCnt_type2++; }
                    elsif ($full_path =~ /type3$/)        { $rtlFrcCnt_type3++; }
                    elsif ($split_path[$#split_path-1] eq "type4") { $rtlFrcCnt_type4++; }
                    elsif ($full_path =~ /type5$/) { $rtlFrcCnt_type5++; }
                    elsif ($full_path =~ /type6$/) { $rtlFrcCnt_type6++; }
                    elsif ($full_path =~ /type7$/) { $rtlFrcCnt_type7++; }
                    elsif ($full_path =~ /type8$/) { $rtlFrcCnt_type8++; }
                    elsif ($full_path =~ /type9$/) { $rtlFrcCnt_type9++; }
                    elsif ($full_path =~ /type10$/) { $rtlFrcCnt_type10++; }
                    elsif ($full_path =~ /type10$/) { $rtlFrcCnt_type10++; }
                    elsif ($full_path =~ /type10$/) { $rtlFrcCnt_type10++; }
                    elsif ($full_path =~ /type10$/) { $rtlFrcCnt_type10++; }
                    elsif (($full_path =~ /type11$/) &&
                           (($split_path[$#split_path-1] =~ /type11$/) ||
                            ($split_path[$#split_path-1] eq "type11") ||
                            ($split_path[$#split_path-1] eq "type11")))  { $rtlFrcCnt_type11++; }
                    elsif ($full_path =~ /type11$/) { $rtlFrcCnt_type11++; }
                    elsif ($full_path =~ /type12$/) { $rtlFrcCnt_type12++; }
                    elsif ($full_path =~ /type13$/) { $rtlFrcCnt_type13++; }
                    elsif ($full_path =~ /type14$/) { $rtlFrcCnt_type14++; }
                    elsif ($full_path =~ /type14$/) { $rtlFrcCnt_type14++; }
                    elsif ($full_path =~ /type15$/) { $rtlFrcCnt_type15++; }
                    elsif ($full_path =~ /type16$/) { $rtlFrcCnt_type16++; }
                    else {
                        printf "Uncategorized external force on %s\n", $forces{$fields[0]}{"Target"};
                        #exit;
                    }
                }
            }
        }
    }
    # In "Event List" section
    elsif ($in_event_list == 1) {
        # Blank lines are skipped
        # Right now this section goes to the end of the file, no need to reset $in_event_list
        if ($line =~ /^\s*$/) { next; }
        # Skip the timestamp headers (for now)
        elsif ($line =~ /^----  Time/) { next; }
        # Parse the remaining lines
        else {
            my @fields = split /\s+/, $line;
            # Check that this is a known line format
            # FIXME: Do I care about the different values in $fields[1]?
            if (((scalar(@fields) == 3) && (($fields[1] eq "LF") ||
                                            ($fields[1] eq "ED") ||
                                            ($fields[1] eq "EF")    )) ||
                ((scalar(@fields) == 2) && (($fields[1] eq "LR") ||
                                            ($fields[1] eq "ER")    ))) {

                # Now increment the event counter for that signal
                if (defined $forces{$fields[0]}) {
                    $forces{$fields[0]}{"EVENT_CNT"}++;
                } else {
                    print "Error! Unknown signal in the event list:\n$line";
                    exit;
                }
            }
            else { print "Error! Bad line format:\n$line"; exit; }
        }
    }

}

# Get some statistics
my $unused_lng_forces = 0;
my $unused_ext_forces = 0;
my $unused_forces = 0;
foreach $key (keys(%forces)) {
    if ($forces{$key}{"EVENT_CNT"} == 0) {
        $unused_forces++;
        if ($forces{$key}{"TYPE"} eq "LANGUAGE") {
            $unused_lng_forces++;
        } elsif ($forces{$key}{"TYPE"} eq "EXTERNAL") {
            $unused_ext_forces++;
        }

        if ($DBG) {
            printf "%s (%s) %s was never forced\n", $forces{$key}{"TYPE"}, $key, $forces{$key}{"Target"};
        }
    } else {
        if ($forces{$key}{"TYPE"} eq "LANGUAGE") {
            # Count the forces per file
            $used_forces_per_file{$forces{$key}{"File"}}++;

            if ($DBG) {
                printf "%s, %s\n   %s\n", $forces{$key}{"File"}, $forces{$key}{"Line"}, $forces{$key}{"Target"};
            }
        }

        if ($DBG) {
            printf "%s (%s) %s was forced %d times\n", $forces{$key}{"TYPE"}, $key,
                                                       $forces{$key}{"Target"},
                                                       $forces{$key}{"EVENT_CNT"};
        }

        # Count the used forces per partition
        # Only count LANGUAGE and EXTERNAL forces (no *_TB forces)
        if ($forces{$key}{"TYPE"} =~ /^(LANGUAGE|EXTERNAL)$/) {
            my @split_path = split /\./, $forces{$key}{"Target"};
            # If this is a top-level/external pin (soc_tb.soc.xx*) put it in its own category
            if ($split_path[2] =~ /^xx/) {
                $split_path[2] = "top_level_pin";
            }
            if ($DBG) { printf "Saw %s force to partition %s\n", $forces{$key}{"TYPE"}, $split_path[2]; }
            $partition_cnt{$split_path[2]}{$forces{$key}{"TYPE"}}++;
        }
    }
}


# Print out the stats per file
printf OUTPUT_FILE "Forces per file (%d total files):\n", scalar(keys(%forces_per_file));
foreach $file (keys(%forces_per_file)) {
    printf OUTPUT_FILE "\t%4d : %s\n", $forces_per_file{$file}, $file;
}
print OUTPUT_FILE "\n";

printf OUTPUT_FILE "Unique forces per file (%d total files):\n", scalar(keys(%unique_forces_per_file));
foreach $file (keys(%unique_forces_per_file)) {
    printf OUTPUT_FILE "\t%4d : %s\n", $unique_forces_per_file{$file}, $file;
}
print OUTPUT_FILE "\n";

printf OUTPUT_FILE "Used forces per file (%d total files):\n", scalar(keys(%used_forces_per_file));
foreach $file (keys(%used_forces_per_file)) {
    printf OUTPUT_FILE "\t%4d : %s\n", $used_forces_per_file{$file}, $file;
}
print OUTPUT_FILE "\n";

# Print out the stats per partition
printf OUTPUT_FILE "Used forces per partition:\n";
foreach $par (sort(keys(%partition_cnt))) {
    printf OUTPUT_FILE "\t%14s (Language Forces) : %6d\n", $par, $partition_cnt{$par}{"LANGUAGE"};
    printf OUTPUT_FILE "\t%14s (External Forces) : %6d\n", ""  , $partition_cnt{$par}{"EXTERNAL"};
}

# Print out the results
print OUTPUT_FILE <<END_OF_RESULTS;
End of analysis statistics:
    Total defined language forces: $total_lng_forces
    Unique language forces:        $unique_lng_forces
    Unused language forces:        $unused_lng_forces
    Language forces on TB signals: $tb_lng_forces

    Total defined external forces: $total_ext_forces
    Unique external forces:        $unique_ext_forces
    Unused external forces:        $unused_ext_forces
    External forces on TB signals: $tb_ext_forces

    Total defined forces:          $total_forces
    Unique forces:                 $unique_forces
    Unused forces:                 $unused_forces
    Total forces on TB signals:    $tb_forces

END_OF_RESULTS

# Print out the external signal analysis
print OUTPUT_FILE <<END_OF_EXT_ANALYSIS;
Analysis of external forces:
    type1 forces:           $rtlFrcCnt_type1
    type2 forces:  $rtlFrcCnt_type2
    type3 forces:        $rtlFrcCnt_type3
    type4 forces:                 $rtlFrcCnt_type4
    type5 forces:                 $rtlFrcCnt_type5
    type6 injection:                $rtlFrcCnt_type6
    type7 forces:   $rtlFrcCnt_type7
    type8 init:                      $rtlFrcCnt_type8
    type9:                       $rtlFrcCnt_type9
    type10:  $rtlFrcCnt_type10
    type11:                     $rtlFrcCnt_type11
    type12:                        $rtlFrcCnt_type12
    type13:                       $rtlFrcCnt_type13
    type14:                       $rtlFrcCnt_type14
    type15:              $rtlFrcCnt_type15
    type16:                  $rtlFrcCnt_type16

END_OF_EXT_ANALYSIS


# Print out a helpful message to the user and exit
sub help {
    print <<END_OF_HELP;

Pulls interesting S0ix related events out of the ptracker (ptracker.log for simulation runs and ptracker_pcode.out for emulation runs)
and creates an easy to read S0ix specific log file (s0ix_ptracker.log).

Usage:
s0ix_ptracker.pl <options>

Options:
    -input <input_file>      : Path to foo.log      (default: current directory)
    -output <output_file>    : Path to bar.log (default: current directory)
    -logbook <logbook_file>  : Path to baz.log       (default: current directory)
    -ver <model>             : Path to \$MODEL_ROOT       (default: model found in logbook.log)
    -watson <watson_list_file> : Path to watson.lst         (default: \$MODEL_ROOT/target/<dut>/aceroot/results/target/gen/watson/watson.lst)
    -emu                     : Enable emulation mode (deprecated)
    -d                       : Enable debug mode (more verbose output)
    -h                       : This help message

END_OF_HELP
}
