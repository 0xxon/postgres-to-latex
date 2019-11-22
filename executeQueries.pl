#!/usr/bin/env perl -Ilib

# Ok, this little script (which for the record - was never really intended to be public)
# runs queries against a database, and writes them out into a file. Run without arguments to
# get usage information.

use 5.10.1;
use strict;
use warnings;

use YAML;
use Perl6::Slurp;
use autodie;
use Data::Dumper;
use Getopt::Long;

use DBI;
use DBD::Pg qw/:pg_types/;

use Carp;
use Carp::Assert;

sub usage {
	say STDERR <<EOD;
Script usage:
executeQueries [--site sitename] [--try] [--nocache] [--queries queryfile] [--dbconn connection string]

If --queries is not provided, queries are read from queries.yaml.

--site is "" by default. Result file will be named results-[site]-new.yaml
Cached results from results-[site].yaml will be used (queries already executed will not be re-executed).

--nocache disables caching, all queries will be re-executed even if results are already in results-[site].yaml

If --try is specified, queries are not run. Instead, an EXPLAIN statement is run for each query, and the
result is output to the console. This can, e.g. be used to verify that the query statements work correctly.

If you are satisfied with the results afer running them, you should consider moving them
to results-[site].yaml.

generateTex --site sitename > ../../tex/results-[site].tex can be used to generate macros that can
be embedded into LaTeX.

Database connection:
====================

Typically, this script tries to connect to a database with the following string:

dbi:Pg:dbname=tls;port=7779;host=localhost;password=[password]

where [password] is read from the PG_PW environment variable.

If this does not work for yoy, you can provide a new connection string with the --dbconn option.


Structure of queries.yaml:
==========================

Generally, a name and a query have to be given for each query. It is also possible to specify a sites entry
for queries - in this case, the entry is only run at sites where the name matches the list.

EOD
	exit(-1);
}

my $queryfile;
my $site;
my $connectString;
my $try = 0;
my $nocache = 0;
GetOptions("site=s" => \$site,
	"queries=s" => \$queryfile,
  "dbconn=s" => \$connectString,
  "try" => \$try,
  "nocache" => \$nocache)
or usage();

$queryfile //= "queries.yaml";
$site //= "";
my $resultsfile = "results";
$resultsfile .= "-$site" if ( $site ne "" );

unless ( -f $queryfile ) {
	die("$queryfile does not exist!");
}

my $pass = $ENV{PG_PW};
$connectString //= "dbi:Pg:dbname=tls;port=7779;host=localhost;password=$pass";

my $dbh = DBI->connect($connectString, "", "", {
	RaiseError => 1,
});

my $queries_yaml = slurp($queryfile);
my $queries = Load($queries_yaml);

my $results = { };

if ( -e "$resultsfile.yaml" ) {
	my $results_yaml = slurp("$resultsfile.yaml");
	$results = %{Load($results_yaml)}{results};
	say Dumper($results);
}

my %replace;

for my $q ( @$queries ) {
	my $name = $q->{'name'};
	my $type = $q->{'type'};
	my $before = $q->{'before'};

	if ( defined($q->{sites}) ) {
		my %sites = map { $_ => 1 } @{$q->{sites}};
		if ( !defined($sites{$site}) ) {
			say STDERR "Skipping $name because $site not listed in site list";
			next;
		}
	}

	say $q->{'name'};

	if ( defined($results->{$name}) ) {
		#say "skipping ".$q->{'name'};
		if ( !defined($type) ) {
			generateReplace($name, $results->{$name});
		}
		next;
	}

	if ( defined($before) ) {
		for my $q ( @$before ) {
			say "Executing $q";
			$dbh->do($q);
		}
	}

	my $sql = $q->{'query'};
	while ( my ($re, $res) = each(%replace) ) {
		last if defined($q->{'noexpand'} ); #no expansion for this query.
		$sql =~ s/ $re($| |;|\))/ $res$1/g;
	}

	if ( !defined($q->{type}) ) {  # no type defined, hence this is a default counting query
		my $res = executeCount($sql);
		say "Result: $res";
		if ( defined($q->{'pscale'}) ) {
			my $scale = $q->{'pscale'};
			unless ( $scale =~ /^\d+$/ ) {
				$scale = $results->{$scale};
				assert(defined($scale));
			}

			if ( $res != 0 ) {
				$res = ($res/$scale) * 100;
				$res =~ s/(\.\d\d).*/$1/;
				$res .= "\\\%";
			}
			say "Scaled result: $res";
		}
		$results->{$name} = $res;
		generateReplace($q->{'name'}, $res);
	} elsif ( $q->{type} eq 'switch' ) {
	       $results->{$name} = executeSwitch($sql);
	} elsif ( $q->{type} eq 'table' ) {
	       $results->{$name} = executeTable($sql);
	} else {
		die("Unknown query type $type");
	}

	# burp every time so that we can stop at any query
	burp("$resultsfile-new.yaml",
		Dump({
			meta=>{
				site=>$site,
			},
			results=>$results
		})
	);
}

sub generateReplace {
	my ($name, $result) = @_;
	assert(defined($name));
	assert(defined($result));

	my $re = qr/$name/;
	$replace{$name} = $result;
}

burp("$resultsfile-new.yaml",
	Dump({
		meta=>{
			site=>$site,
		},
		results=>$results
	})
);

say "Please examine $resultsfile-new.yaml and move to $resultsfile.yaml if statisfied";

sub executeTable {
	my ($query) = @_;

	assert(defined($query));

	say "Executing: $query";

	my $sth = $dbh->prepare($query);
	$sth->execute;

	my %res;

	my @fieldnames =  @{ $sth->{NAME} };
	$res{'fields'} = \@fieldnames;
	$res{'rows'} = [];

	while ( my $row = $sth->fetchrow_arrayref() ) {
		push(@{$res{'rows'}}, [@{$row}]);
	}

	say "Result: ".Dumper(\%res);

	return \%res;
}

sub executeSwitch {
	my $query = shift;

	say "Executing: $query";

	my $sth = $dbh->prepare($query);
	$sth->execute;

	my %res;

	while ( my $row = $sth->fetchrow_hashref() ) {
		$res{$row->{name}} = $row->{count};
	}

	say "Result: ".Dumper(\%res);

	return \%res;
}

sub executeCount {
	my $query = shift;
	if ( $try ) {
		$query = "explain $query";
	}

	say "Executing: $query";

	my $sth = $dbh->prepare($query);
	$sth->execute;
	my $a = $sth->fetchrow_hashref;

	if ( defined($a) && defined($a->{'count'}) ) {
		return $a->{'count'};
	}

	if ( $try ) {
		say Dumper($a);
	} else {
		die("Query did not return count");
	}
}


sub burp {
	my( $file_name ) = shift ;
	open( my $fh, ">$file_name" ) || die "can't create $file_name $!" ;
	print $fh @_;
}
