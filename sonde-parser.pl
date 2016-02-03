#!/usr/bin/perl
use strict;                         # Include all types
use warnings;
use Getopt::Long qw(GetOptions);


#******************************************************************************#
#
# 'Cup-Sonde' Data parser
#
# Usage:
#   perl sonde-parser.pl
#       --file=<filename>
#       --alt=<inital altitude in meters>
#
# The Fine Print (License)
# ------------------------
# Copyright 2016 Adam C. Abernathy, (adamabernathy@gmail.com)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
#******************************************************************************#


##
# TODO: Add pressure corrections from elevation
# TODO: Add direction/bearing support?
# TODO: Add dew point calculation?
#

#******************************************************************************#
#
#                       DECLARATIONS AND DEFINITIONS
#                       ============================
#
#  Name                 Description and Scope
#  ----                 ---------------------------------------------
my $i           = 0;    # Counter
my $line        = '';   # Line-by-line read-in from source file
my $junk        = '';   # Resuable working variable
my $AFU         = 0;    # Escape flag, Integer, 0=NO, 1=YES
my $FIRST_TIME  = 1;    # Fist itteration flag, Integer, 0=NO, 1=YES
my $print_ver   = 0;    # Print version flag

#  -- I/O --
my $working_dir = '';   # Working directory
my $output_dir  = '';   # Output directory
my $source_file = '';   # Original source file
my $output_file = '';   # Processed output file

#  -- DATA FIELDS (TOKENS & RETRIEVED VALUES) --
my $token       = '';   # Parsed token, reusable
my $slice       = '';   # Token slice,  resuable
my $value       = 0;    # Token value,  reusable
my @arr         = 0;    # Token container, ARRAY: 1xn
my $nline       = 1;    # Line number of valid date from raw file, recorded
my $init_elev   = 0;    # Initial elevation for take-off. Used in corrections
my $unix_start  = 0;    # Standard UNIX (UTC) time of the start of the flight
my $time_shift  = 0;    # Profile offset
my $min         = 0;    # Profile timestamp minute
my $sec         = 0;    # Profile timestamp second
my $decs        = 0;    # Profile timestamp fractional second
#  Profile values
my $sys_volt    = 0;    # Profile battery voltage,    units: Volts
my $sys_nsat    = 0;    # Profile No. of Sattelites,  units: none
my $geo_lat     = 0;    # Profile geodetic lattiude,  units: Degrees North
my $geo_lon     = 0;    # Profile geodetic longitude, units: Degrees East
my $geo_elev    = 0;    # Profile geodetic elevation, units: Meters
my $dat_tmpc    = 0;    # Profile temperature,        units: Celcius
my $dat_relh    = 0;    # Profile relative humidity,  units: Percent
my $dat_pres    = 0;    # Profile pressure,           units: Pascals
#
#******************************************************************************#


##
# Define initialization parameters
#

# Set directories. These are only here if you plan on automating this script.
# For general use you do not need to define these.
#$working_dir = "path/goes/here";
#$output_dir  = $working_dir;

print "Cup-Sonde Parser\n";
GetOptions(
    'file=s'    => \$source_file,
    'alt=s'     => \$init_elev,
) or die print<<EOF;
Usage:
    --file=<filename>
    --alt=<inital altitude in meters>
EOF

##
# Untangle user inputs
#

# If no input file argument is passed then bail out!
if ($source_file eq '' ) {
    print "No input file!\n";
    exit;
}

# Set starting elevation and other constants for altimeter correction work
if ($init_elev == 0) {
    $init_elev = 1560; # Approximate for SLC
}

# Let the user know what is going on
print "Processing file: ", $source_file, " ...\n";


##
# If we can open the file, we will process (chomp) it line-by-line.  It
# is key to remember to close the file handler 'F' when we are done!
#
if( open(F1, "$source_file") ) {
    while( $line = <F1> ) {
        chomp($line);

        #print "$line\n";       # For diagostic purposes

        # The first two lines of the raw data file contain the initialization
        # time of the flight. The first line contains the local time, whereas
        # the second line is the UNIX UTC offset.  Personally I think using
        # the UNIX time is easier, as you can derive any other time parameter
        # from it.
        if ($line =~ /^\# offset/) {
            # should be 1430258910.990000 for the test case
            ($token, $unix_start) = split(/=/, $line);
            #print $unix_start, "\n";    # Diagnostic
        }


        ##
        # We can now assume that we have the starting time of the flight.  We
        # can move onward and process the timestamp and the data from the
        # sonde.
        #
        # The plan here is to first get the timestamp then clean up the string
        # and process the data values as a query. This allows for irregularity
        # in their location. If we have all the values that we need then we
        # will store the values in a CSV file.
        #
        if (($line =~ /^\d\dm\d\ds\d/ ||
             $line =~ /\dh\d\dm\d\ds\d/) &&
             $line =~ /\#DAT\:/) {

             # Each timestamp needs to be converted to an integer of
             # seconds so we can add it to the UNIX time.
             #
             # Example:
             # 01m16s970: [#DAT:q=BE, ... ]
             # We want all three values, then round the decimal seconds to
             # the nearest 1000th and add/subtract 1 to the seconds.
             # We also know the timestamp is fixed at 9 chars.

            $junk = substr($line, 0, 9);
            ($min, $sec, $decs, $junk) = split(/[ms:]/,$line);

            # In order to not pull in the math library, we'll do this the
            # old-school assembly way :)
            if ($decs >= 500){
                $time_shift = $unix_start + ($min * 60) + $sec + 1;
            } else {
                $time_shift = $unix_start + ($min * 60) + $sec;
            }
            #print $time_shift, "\n";        # Diagnostic

            # Now parse out the values from the "DAT" section of the string
            if ($line =~ /\[#DAT:([^\[#DAT:]+)\]/) {

                @arr = split(/,/, $1); # grab the return from the IF eval
                #print $junk, "\n";         # Diagnostic
                foreach $slice (@arr) {
                    ($token, $value) = split(/=/, $slice);

                    # Define null just to be safe
                    if($value =~ /NaN/ || $value eq "" || $value eq "No") {
                        $value = -9999;
                    };

                    # Parse tokens
                    if ( $token eq 'sats' ) { $sys_nsat = $value; }
                    if ( $token eq 'su' )   { $sys_volt = $value; }

                    if ( $token eq 'lat' )  { $geo_lat  = $value; }
                    if ( $token eq 'lon' )  { $geo_lon  = $value; }
                    if ( $token eq 'alt' )  { $geo_elev = $value; }

                    if ( $token eq 'te' )   { $dat_tmpc = $value; }
                    if ( $token eq 'hu')    { $dat_relh = $value; }
                    if ( $token eq 'pa')    { $dat_pres = $value; }
                }

            } else {
                $AFU = 1;
            }

            ##
            # At this point all the data has been parsed and ready for first
            # pass validation.  For the first pass we will just make sure that
            # all the tokens we need are avaiable.  We will deal with
            # QA/QC later.
            #
            # Since the tokens and their values are not in a vector,
            # (for simplicity), our only real option here is brute force
            # thru each variable and test. Not ideal, but it's the way it is.
            #
            $AFU = 0;   # Reset escape flag

            if ($sys_nsat == -9999) { $AFU = 1;}
            if ($sys_volt == -9999) { $AFU = 1;}

            if ($geo_lat  == -9999) { $AFU = 1;}
            if ($geo_lon  == -9999) { $AFU = 1;}
            if ($geo_elev == -9999) { $AFU = 1;}

            if ($dat_tmpc == -9999) { $AFU = 1;}
            if ($dat_relh == -9999) { $AFU = 1;}
            if ($dat_pres == -9999) { $AFU = 1;}


            ##
            # From now on we have an escape plan.  If at any point AFU=1 then we
            # can just skip the line and move on.  Now is also the time to
            # add any corrections or secondary token processing.
            #


            ##
            # Save to output file.  Initially we need to see if this is the
            # first itteration of the program.  If so, we have enough
            # information now to generate the filename.  Once we do this, we
            # can store our Profile data to the CSV output file.
            #
            if ($FIRST_TIME == 1 ) {
                ($output_file, $junk) = split(/.sounding/, $source_file);
                $output_file = sprintf("%s%010d-%s.csv",
                                       $output_dir, $unix_start, $output_file);

                system("rm -f $output_file");
                $FIRST_TIME = 0;
            }

            if ( $AFU == 0 ) {
                if (! -e "$output_file") {
                    # Print CSV header to file
                    open (F2, ">$output_file");
                    print F2 ("#IDX, UNIX-TIME, SYS-NSAT, SYS-VOLT, ".
                              "GEO-LAT, GEO-LON, GEO-ELEV, ".
                              "DAT-TMPC, DAT-RH, DAT-PRES\n");
                    close(F2);
                } else {
                    # Print data to file. This assumes we have a header
                    # WARNING: This could be a sorce of file I/O failures.
                    open (F2,">>$output_file");
                    printf F2 (
                        "%04d,%010d,%02d,%05.2f,%010d,%010d,%05d,".
                        "%06.2f,%06.2f,%06d\n",
                        $nline, $time_shift, $sys_nsat, $sys_volt,
                        $geo_lat, $geo_lon, $geo_elev,
                        $dat_tmpc, $dat_relh, $dat_pres);
                    close(F2);
                }
            }
        }

        $nline++;   # line number +1
    }
}

close(F1);
exit;
