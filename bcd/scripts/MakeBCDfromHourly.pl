#!/usr/bin/perl

# --------------------------------------------------------------------
# Declare modules which are used
# --------------------------------------------------------------------

use warnings;
use strict;

use Data::Dumper;

use lib qw(../../scripts/modules);
use General;

# Inputs
my @iTstep = qw(5 10 15 30 60);
my $SProfile = 'NBC_Profiles.csv';

# Intermediates
my @fElec;
my @AoA_DHW;


# Process the hourly profiles
open(my $fh, "<", $SProfile) or die "Can't open < $SProfile: $!";
my @sAllData = <$fh>;
close $fh;
my $sHeader = shift @sAllData; # Remove the header
foreach my $sLine (@sAllData) {
    my @sLineData = split /,/,$sLine;
    push(@fElec,$sLineData[1]/1.0);
    push(@{$AoA_DHW[0]},$sLineData[2]/1.0);
    push(@{$AoA_DHW[1]},$sLineData[3]/1.0);
};


foreach my $time_step (@iTstep) { # For each timestep
    foreach my $iDHWday (0,1) { # For each DHW consumption
        my $DhwYrL;
        if($iDHWday == 0) {
            $DhwYrL=225;
        } elsif($iDHWday == 1) {
            $DhwYrL=140;
        };
    
        my $bcd_copy = "../../templates/template.bcd";
        open (my $GETBCD, '<', $bcd_copy) or die ("can't open template: $bcd_copy");	# open the template
        my $hse_file->{'bcd'} = [<$GETBCD>];	# Slurp the entire file with one line per array element
        close $GETBCD;
        
        WRITE_BCD: {
            # Generate the profiles
            my @DHW_Draw;
            my @TotalOther;
            my $iStepsHr = 60/$time_step;
            for(my $i=1;$i<=365;$i++) { # For each day
                for(my $j=0;$j<=23;$j++) { # For each hourly
                    for(my $k=0;$k<$iStepsHr;$k++) { # For each timestep
                        push(@TotalOther,$fElec[$j]);
                        push(@DHW_Draw,$AoA_DHW[$iDHWday][$j]);
                    };
                };
            };
            
            # Determine and update sampling frequency
            my $SamplingFreq = $time_step*60;
            $SamplingFreq = sprintf("%d", $SamplingFreq);
            &replace ($hse_file->{'bcd'}, "# period frequency", 1, 1, "%s\n", "*frequency $SamplingFreq");
        
            &insert($hse_file->{'bcd'},"#END_NOTES",1,0,0,"%s\n","# DHW conumption: $DhwYrL [L/day] (unmultiplied)");
        
            # Write the BCD Data
            for(my $k=0;$k<=$#DHW_Draw;$k++) {
                # Populate new line
                $TotalOther[$k]=sprintf("%d",$TotalOther[$k]);
                $DHW_Draw[$k]=sprintf("%d",$DHW_Draw[$k]);
                
                # my $newline = sprintf "%26s %15s %15s %10s %15s\n", $DHW_Draw[$k], 0,0,0,$TotalOther[$k];
                my $newline = sprintf "%26s\n", $DHW_Draw[$k];
                push(@{$hse_file->{'bcd'}},$newline);
            };
            push(@{$hse_file->{'bcd'}},"*data_end\n"); # Add the end statement to the data
        }; # END WRITE_BCD
        
        FILE_PRINTOUT: {
            my $file = "../2015_NBC_$DhwYrL"."_L_Day_DHW_$time_step"."_min.bcd";
			my $FILE;
			open ($FILE, '>', $file ) or die ("Can't open datafile: $file");	# open writeable file
			foreach my $line (@{$hse_file->{'bcd'}}) {print $FILE "$line";};	# loop through each element of the array (i.e. line of the final file) and print each line out
            close $FILE;
		};
    };
};