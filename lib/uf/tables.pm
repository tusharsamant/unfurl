package tables;

use strict;
use integer;
use warnings;

use DBI;
use Fatal qw(open close mkdir chdir);
use Text::CSV_XS;

our $VERSION = '0.1';
our $DB = 'thedb.sqlite';
our $VERBOSE = 0;
our $DIR;

my $dbh; # shared!
my %name; # short aliases for tables, if needed

use constant JOINS  => 0;
use constant SELECT => 0;
use constant ORDER  => 0;
use constant GROUP  => 0;

sub new { bless [], shift }

# SQL mangling

# DB mangling

sub _connect () {
  die "DIR not set" if !$DIR;
  mkdir $DIR unless -d $DIR;
  $dbh ||= DBI->connect(
    "dbi:SQLite:dbname=$DIR/$DB","","",
    { RaiseError => 1, PrintError => 0 }
  ) or die "SQLite connect\n";
}

END {
  $dbh->disconnect if $dbh; 
}

sub _tab { split /\t/, $_[0] }

my $_CSV = new Text::CSV_XS {binary => 1};
sub _csv { $_CSV->parse($_[0]); $_CSV->fields }

sub prepare {
  my $name = shift;
  my($cols, @cols, $insert);

  open(my $f, $name);
  local $_ = <$f>;
  local($/) = /(\r?\n)$/;

  my $split = /\t/ ? \&_tab : \&_csv;

  _connect;

  chomp;
  $name =~ s{.*/}{};
  ($cols, $insert) = deploy_table($name, $split->($_)) or return;

  $cols--;

  $dbh->begin_work;

  my $progress = 0;
  while (<$f>) {
    chomp;
    $insert->execute(($split->($_), ('')x$cols)[0..$cols]);
  }
  continue {
    unless ($progress++ & 1023) {
      verb('.'); $dbh->commit; $dbh->begin_work;
    }
  }
  $dbh->commit;
}

sub deploy_table {
  my($name, @cols) = @_;

  for ($name, @cols) { s/\W+/_/g; $_ = lc($_) };

  eval {
    $dbh->do(
      "create table $name ("
      . join (", ", map "$_ text", @cols)
      . ")"
    )
  }; if ($@) {
    if ($@ =~ /already exists/) {
      verb("Reusing table $name\n");
      return;
    }
    die $@;
  }
  else {
    verb("Table $name created\n");
    (
      scalar(@cols),
      $dbh->prepare(
        "insert into $name values (" . join(",", map "?", @cols) .")"
      )
    )
  }
}

sub set_dir { $DIR = $_[0] }

# "logging"
sub verb { if ($VERBOSE) { print STDERR @_ } }

# interface
sub unfurl {{
  prepare => sub { my($t) = ::take(1); for (ref($t) ? @$t : $t) { prepare($_) } },
  dir     => sub { ($DIR) = ::take(1) },
  verbose => sub { $VERBOSE = 1 },
  quiet   => sub { $VERBOSE = 0 },
  alias   => sub { my($name, $alias) = ::take(2); $name{$alias} = $name },
}}

1;

__END__

=head1 NAME

tables -- row-column mangling via SQLite

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 SEE ALSO

=head1 AUTHOR

Tushar Samant <tushar@tmetic.com>

=cut

