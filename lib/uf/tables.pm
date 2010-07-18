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
# the args are mostly documentation

sub t_join {
  my($self, $keep, $cols, $other, $other_keep) = @_;
  push @{$self->[JOINS]}, [$keep, $cols, $other, $other_keep];
}

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
  @cols = $split->($_);
  for ($name, @cols) { s/\W+/_/g; $_ = lc($_) };

  ($cols, $insert) = deploy_table($name, @cols);
  
  if ($insert) {
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
  ($name, @cols);
}

sub deploy_table {
  my($name, @cols) = @_;

  # assume scrubbed

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
  prepare => sub {
    my($a, $t) = ::take(2);
    my ($name, @cols) = prepare($t);
    # make ALIAS.colname a var containing 'name.colname'
    ::add_var({ map {$_, "$name.$_"} @cols }, "$a.");
    return
  },
  dir     => sub { ($DIR) = ::take(1) },
  verbose => sub { $VERBOSE = 1 },
  quiet   => sub { $VERBOSE = 0 },
  alias   => sub { my($name, $alias) = ::take(2); $name{$alias} = $name },
}}

1;

__END__

=head1 NAME

tables -- row-column munging through SQLite

=head1 FUNCTIONS/FLAGS

=over 4

=item B<set_dir>

Designate a work directory, creating it if necessary. The file
I<thedb.sqlite> in the directory is used as the sqlite3 database
to do all munging.

=item B<prepare(file)>

Imports a tab-delimited or CSV file as a single table. The table's name is a
scrubbed version of the file's basename. This is a no-op if the table
exists.

The first line is expected to have column names--these are also scrubbed
before being used for table creation.

All columns are type text and indexed.

=item B<$VERBOSE>

When (and only when) true, prints messages and progress to STDERR.

=back

=head1 AUTHOR

Tushar Samant <tushar@tmetic.com>

=cut

