#! /usr/bin/perl
if (grep { $_ eq '--version' } @ARGV) {
	print "daemonproxy version 9.9.9\n";
	exit 1;
}
if (@ARGV == 2 && $ARGV[0] eq '-c' && $ARGV[1] eq '-') {
	while (<STDIN>) { print; }
	exit 0;
}
die "un-handled arguments\n";
