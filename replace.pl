use 5.14.1;

use strict;
use warnings;

use Carp;
use autodie;

=pod

How to call this:
for i in queries-*.tex; do perl replace.pl $i results-*.tex methodology.tex extensions.tex > $i.new; done
rm queries-*.tex
mmv queries-\*.new queries-\#1
rm queries-*.tex
git checkout queries-*.tex

=cut

# First file given is the file to prune, other files are files using the data.

my @files = @ARGV;

if ( scalar @ARGV < 2 ) {
	croak("Need at least 2 files");
}

my $firstfile = shift @files;
open(my $fh, "<", $firstfile);

my %handles;

while (my $line = <$fh>) {
	chomp($line);
	if ( $line =~ m#^\\newcommand\{\\(.*?)\}\[1\]\{.*?\\xspace\}$# ) {
		$handles{$1} = {re => qr/\\($1)\s*\{/, count => 0};
	} elsif ( $line =~ m#^\\newcommand\{\\(.*?)\}\[1\]\{\%$# ) {
		$handles{$1} = {re => qr/($1(lines)?)\s*\{/, count => 0};;
	}
}

close($fh);

for my $file ( @files ) {
	open(my $in, "<", $file);
	while ( my $line = <$in> ) {
		next if ( $line =~ m#^\%# );
		while ( my ($handle, $rec) = each(%handles) ) {
			my $re = $rec->{re};
			if ( $line =~ $re ) {
				$handles{$handle}{count}++;
			}
		}
	}
	close($in);
}

my $search = undef;

open($fh, "<", $firstfile);
while (my $line = <$fh>) {
	if ( defined($search) ) {
		print $line;
		if ( $line =~ $search ) {
			$search = undef;
			next;
		}
	}
	if ( $line =~ m#^\\newcommand\{\\(.*?)\}\[1\]\{.*?\\xspace\}$# ) {
		if ( $handles{$1}{count} > 0 ) {
			print $line;
		}
	} elsif ( $line =~ m#^\\newcommand\{\\(.*?)\}\[1\]\{\%$# ) {
		if ( $handles{$1}{count} > 0 ) {
			print $line;
			$search = qr/(^\}\%$)|(^\\def)/;
		}
	}
}
close($fh);
