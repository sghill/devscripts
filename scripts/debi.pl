#! /usr/bin/perl -w

# debi:  Install current version of deb package
# debc:  List contents of current version of deb package
#
# debi and debc originally by Christoph Lameter <clameter@debian.org>
# Copyright Christoph Lameter <clameter@debian.org>
# The now defunct debit originally by Jim Van Zandt <jrv@vanzandt.mv.com>
# Copyright 1999 Jim Van Zandt <jrv@vanzandt.mv.com>
# Modifications by Julian Gilbey <jdg@debian.org>, 1999-2003
# Copyright 1999-2003, Julian Gilbey <jdg@debian.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

use 5.008;
use strict;
use Getopt::Long;
use File::Basename;
use filetest 'access';
use Cwd;

my $progname = basename($0,'.pl');  # the '.pl' is for when we're debugging
my $modified_conf_msg;

sub usage_i {
    print <<"EOF";
Usage: $progname [options] [.changes file] [package ...]
  Install the .deb file(s) just created, as listed in the generated
  .changes file or the .changes file specified.  If packages are listed,
  only install those specified packages from the .changes file.
  Options:
    --no-conf or      Don\'t read devscripts config files;
      --noconf          must be the first option given
    -a<arch>          Search for .changes file made for Debian build <arch>
    -t<target>        Search for .changes file made for GNU <target> arch
    --debs-dir DIR    Look for the changes and debs files in DIR instead of
                      the parent of the current package directory
    --multi           Search for multiarch .changes file made by dpkg-cross
    --check-dirname-level N
                      How much to check directory names:
                      N=0   never
                      N=1   only if program changes directory (default)
                      N=2   always
    --check-dirname-regex REGEX
                      What constitutes a matching directory name; REGEX is
                      a Perl regular expression; the string \`PACKAGE\' will
                      be replaced by the package name; see manpage for details
                      (default: 'PACKAGE(-.*)?')
    --help            Show this message
    --version         Show version and copyright information

Default settings modified by devscripts configuration files:
$modified_conf_msg
EOF
}

sub usage_c {
    print <<"EOF";
Usage: $progname [options] [.changes file] [package ...]
  Display the contents of the .deb file(s) just created, as listed
  in the generated .changes file or the .changes file specified.
  If packages are listed, only display those specified packages
  from the .changes file.  Options:
    --no-conf or      Don\'t read devscripts config files;
      --noconf          must be the first option given
    -a<arch>          Search for changes file made for Debian build <arch>
    -t<target>        Search for changes file made for GNU <target> arch
    --debs-dir DIR    Look for the changes and debs files in DIR instead of
                      the parent of the current package directory
    --multi           Search for multiarch .changes file made by dpkg-cross
    --check-dirname-level N
                      How much to check directory names:
                      N=0   never
                      N=1   only if program changes directory (default)
                      N=2   always
    --check-dirname-regex REGEX
                      What constitutes a matching directory name; REGEX is
                      a Perl regular expression; the string \`PACKAGE\' will
                      be replaced by the package name; see manpage for details
                      (default: 'PACKAGE(-.*)?')
    --help            Show this message
    --version         Show version and copyright information

Default settings modified by devscripts configuration files:
$modified_conf_msg
EOF
}

if ($progname eq 'debi') { *usage = \&usage_i; }
elsif ($progname eq 'debc') { *usage = \&usage_c; }
else { die "Unrecognised invocation name: $progname\n"; }

my $version = <<"EOF";
This is $progname, from the Debian devscripts package, version ###VERSION###
This code is copyright 1999-2003, Julian Gilbey <jdg\@debian.org>,
all rights reserved.
Based on original code by Christoph Lameter and James R. Van Zandt.
This program comes with ABSOLUTELY NO WARRANTY.
You are free to redistribute this code under the terms of
the GNU General Public License, version 2 or later.
EOF

# Start by setting default values
my $debsdir = '..';
my $debsdir_warning;
my $check_dirname_level = 1;
my $check_dirname_regex = 'PACKAGE(-.*)?';

# Next, read configuration files and then command line
# The next stuff is boilerplate

if (@ARGV and $ARGV[0] =~ /^--no-?conf$/) {
    $modified_conf_msg = "  (no configuration files read)";
    shift;
} else {
    my @config_files = ('/etc/devscripts.conf', '~/.devscripts');
    my %config_vars = (
		       'DEBRELEASE_DEBS_DIR' => '..',
		       'DEVSCRIPTS_CHECK_DIRNAME_LEVEL' => 1,
		       'DEVSCRIPTS_CHECK_DIRNAME_REGEX' => 'PACKAGE(-.*)?',
		       );
    my %config_default = %config_vars;

    my $shell_cmd;
    # Set defaults
    foreach my $var (keys %config_vars) {
	$shell_cmd .= qq[$var="$config_vars{$var}";\n];
    }
    $shell_cmd .= 'for file in ' . join(" ",@config_files) . "; do\n";
    $shell_cmd .= '[ -f $file ] && . $file; done;' . "\n";
    # Read back values
    foreach my $var (keys %config_vars) { $shell_cmd .= "echo \$$var;\n" }
    my $shell_out = `/bin/bash -c '$shell_cmd'`;
    @config_vars{keys %config_vars} = split /\n/, $shell_out, -1;

    # Check validity
    $config_vars{'DEVSCRIPTS_CHECK_DIRNAME_LEVEL'} =~ /^[012]$/
	or $config_vars{'DEVSCRIPTS_CHECK_DIRNAME_LEVEL'}=1;
    # We do not replace this with a default directory to avoid accidentally
    # installing a broken package
    $config_vars{'DEBRELEASE_DEBS_DIR'} =~ s%/+%/%;
    $config_vars{'DEBRELEASE_DEBS_DIR'} =~ s%(.)/$%$1%;
    if (! -d $config_vars{'DEBRELEASE_DEBS_DIR'}) {
	$debsdir_warning = "config file specified DEBRELEASE_DEBS_DIR directory $config_vars{'DEBRELEASE_DEBS_DIR'} does not exist!";
    }

    foreach my $var (sort keys %config_vars) {
	if ($config_vars{$var} ne $config_default{$var}) {
	    $modified_conf_msg .= "  $var=$config_vars{$var}\n";
	}
    }
    $modified_conf_msg ||= "  (none)\n";
    chomp $modified_conf_msg;

    $debsdir = $config_vars{'DEBRELEASE_DEBS_DIR'};
    $check_dirname_level = $config_vars{'DEVSCRIPTS_CHECK_DIRNAME_LEVEL'};
    $check_dirname_regex = $config_vars{'DEVSCRIPTS_CHECK_DIRNAME_REGEX'};
}

# Command line options next
my ($opt_help, $opt_version, $opt_a, $opt_t, $opt_debsdir, $opt_multi);
my ($opt_ignore, $opt_level, $opt_regex, $opt_noconf);
GetOptions("help" => \$opt_help,
	   "version" => \$opt_version,
	   "a=s" => \$opt_a,
	   "t=s" => \$opt_t,
	   "debs-dir=s" => \$opt_debsdir,
	   "multi" => \$opt_multi,
	   "ignore-dirname" => \$opt_ignore,
	   "check-dirname-level=s" => \$opt_level,
	   "check-dirname-regex=s" => \$opt_regex,
	   "noconf" => \$opt_noconf,
	   "no-conf" => \$opt_noconf,
	   )
    or die "Usage: $progname [options] [.changes file] [package ...]\nRun $progname --help for more details\n";

if ($opt_help) { usage(); exit 0; }
if ($opt_version) { print $version; exit 0; }
if ($opt_noconf) {
    die "$progname: --no-conf is only acceptable as the first command-line option!\n";
}

my ($targetarch, $targetgnusystem);
$targetarch = $opt_a ? "-a$opt_a" : "";
$targetgnusystem = $opt_t ? "-t$opt_t" : "";

if ($opt_debsdir) {
    $opt_debsdir =~ s%/+%/%;
    $opt_debsdir =~ s%(.)/$%$1%;
    if (! -d $opt_debsdir) {
	$debsdir_warning = "--debs-dir directory $opt_debsdir does not exist!";
    }
    $debsdir = $opt_debsdir;
}

if ($debsdir_warning) {
    die "$progname: $debsdir_warning\n";
}

# dirname stuff
if ($opt_ignore) {
    die "$progname: --ignore-dirname has been replaced by --check-dirname-level and\n--check-dirname-regex; run $progname --help for more details\n";
}

if (defined $opt_level) {
    if ($opt_level =~ /^[012]$/) { $check_dirname_level = $opt_level; }
    else {
	die "$progname: unrecognised --check-dirname-level value (allowed are 0,1,2)\n";
    }
}

if (defined $opt_regex) { $check_dirname_regex = $opt_regex; }

# Is a .changes file listed on the command line?
my ($changes, $mchanges, $arch);
if (@ARGV and $ARGV[0] =~ /\.changes$/) {
    $changes = shift;
}

# Need to determine $arch in any event
$arch = `dpkg-architecture $targetarch $targetgnusystem -qDEB_HOST_ARCH`;
if ($? != 0 or ! $arch) {
    die "$progname: unable to determine target architecture.\n";
}
chomp $arch;


my $chdir = 0;

if (! defined $changes) {
    # Look for .changes file via debian/changelog
    until (-r 'debian/changelog') {
	$chdir = 1;
	chdir '..' or die "$progname: can't chdir ..: $!\n";
	if (cwd() eq '/') {
	    die "$progname: cannot find readable debian/changelog anywhere!\nAre you in the source code tree?\n";
	}
    }

    # Find the source package name and version number
    my %changelog;
    open PARSED, q[dpkg-parsechangelog | grep '^\(Source\|Version\):' |]
	or die "$progname; cannot execute dpkg-parsechangelog | grep: $!\n";
    while (<PARSED>) {
	chomp;
	if (/^(\S+):\s(.+?)\s*$/) { $changelog{$1}=$2; }
	else {
	    die "$progname: don't understand dpkg-parsechangelog output: $_\n";
	}
    }

    close PARSED
	or die "$progname: problem executing dpkg-parsechangelog | grep: $!\n";
    if ($?) { die "$progname: dpkg-parsechangelog | grep failed!\n" }

    die "$progname: no package name in changelog!\n"
	unless exists $changelog{'Source'};
    die "$progname: no package version in changelog!\n"
	unless exists $changelog{'Version'};

    # Is the directory name acceptable?
    if ($check_dirname_level ==  2 or
	    ($check_dirname_level == 1 and $chdir)) {
	my $re = $check_dirname_regex;
	$re =~ s/PACKAGE/\\Q$changelog{'Source'}\\E/g;
	my $gooddir;
	if ($re =~ m%/%) { $gooddir = eval "cwd() =~ /^$re\$/;"; }
	else { $gooddir = eval "basename(cwd()) =~ /^$re\$/;"; }

	if (! $gooddir) {
	    my $pwd = cwd();
	    die <<"EOF";
$progname: found debian/changelog for package $changelog{'Source'} in the directory
  $pwd
but this directory name does not match the package name according to the
regex  $check_dirname_regex.

To run $progname on this package, see the --check-dirname-level and
--check-dirname-regex options; run $progname --help for more info.
EOF
	}
    }

    my $sversion = $changelog{'Version'};
    $sversion =~ s/^\d+://;
    my $package = $changelog{'Source'};
    my $pva="${package}_${sversion}_${arch}";
    $changes="$debsdir/$pva.changes";
    if ($opt_multi) {
	my @mchanges = glob("$debsdir/${package}_${sversion}_*+*.changes");
	@mchanges = grep { /[_+]$arch[\.+]/ } @mchanges;
	$mchanges = $mchanges[0] || '';
	$mchanges ||= "$debsdir/${package}_${sversion}_multi.changes"
	    if -f "$debsdir/${package}_${sversion}_multi.changes";
    }
}

chdir dirname($changes)
    or die "$progname: can't chdir to $changes directory: $!\n";
$changes = basename($changes);
$mchanges = basename($mchanges) if $opt_multi;

if (! -r $changes or $opt_multi and $mchanges and ! -r $mchanges) {
    die "$progname: can't read $changes" .
	(($opt_multi and $mchanges) ? " or $mchanges" : "") . "!\n";
}

if (! -r $changes and $opt_multi) {
    $changes = $mchanges;
} else {
    $opt_multi = 0;
}
# $opt_multi now tells us whether we're actually using a multi-arch .changes
# file

my @debs = ();
my %pkgs = map { $_ => 0 } @ARGV;
open CHANGES, $changes or die "$progname: problem opening $changes: $!\n";
my $infiles;
while (<CHANGES>) {
    last if $infiles and /^[^ ]/;
    /^Files:/ and $infiles=1, next;
    next unless $infiles;
    if (/ (\S*\.deb)$/) {
        my $deb = $1;
        $deb =~ /^([a-z0-9+\.-]+)_/ or warn "unrecognised .deb name: $deb\n";
	# don't want other archs' .debs:
	next unless $deb =~ /[_+]($arch|all)[\.+]/;
        my $pkg = $1;
        if (@ARGV) {
            if (exists $pkgs{$pkg}) {
                push @debs, $deb;
                $pkgs{$pkg}++;
            }
        } else {
            push @debs, $deb;
        }
    }
}
close CHANGES;

if (! @debs) {
    die "$progname: no appropriate .debs found in the changes file $changes!\n";
}

if ($progname eq 'debi') {
    system('debpkg', '-i', @debs) == 0
	or die "$progname: debpkg -i failed\n";
} else {
    # $progname eq 'debc'
    foreach my $deb (@debs) {
	print "$deb\n";
	print '-' x length($deb), "\n";
	system('dpkg-deb', '-I', $deb) == 0
	    or die "$progname: dpkg-deb -I $deb failed\n";
	system('dpkg-deb', '-c', $deb) == 0
	    or die "$progname: dpkg-deb -c $deb failed\n";
	print "\n";
    }
}

# Now do a sanity check
if (@ARGV) {
    foreach my $pkg (keys %pkgs) {
        if ($pkgs{$pkg} == 0) {
            warn "$progname: package $pkg not found in $changes, ignoring\n";
        } elsif ($pkgs{$pkg} > 1) {
            warn "$progname: package $pkg found more than once in $changes, installing all\n";
        }
    }
}

exit 0;