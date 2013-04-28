#line 1
package Types::TypeTiny;

use strict;
use warnings;

our $AUTHORITY = 'cpan:TOBYINK';
our $VERSION   = '0.003_08';

use Scalar::Util qw< blessed >;

our @EXPORT_OK = qw( CodeLike StringLike TypeTiny HashLike to_TypeTiny );

my %cache;

sub import
{
	# do the shuffle!
	no warnings "redefine";
	our @ISA = qw( Exporter::TypeTiny );
	require Exporter::TypeTiny;
	my $next = \&Exporter::TypeTiny::import;
	*import = $next;
	goto $next;
}

sub StringLike ()
{
	require Type::Tiny;
	$cache{StringLike} ||= "Type::Tiny"->new(
		name       => "StringLike",
		constraint => sub {    !ref($_   ) or Scalar::Util::blessed($_   ) && overload::Method($_   , q[""])  },
		inlined    => sub { qq/!ref($_[1]) or Scalar::Util::blessed($_[1]) && overload::Method($_[1], q[""])/ },
	);
}

sub HashLike ()
{
	require Type::Tiny;
	$cache{HashLike} ||= "Type::Tiny"->new(
		name       => "HashLike",
		constraint => sub {    ref($_   ) eq q[HASH] or Scalar::Util::blessed($_   ) && overload::Method($_   , q[%{}])  },
		inlined    => sub { qq/ref($_[1]) eq q[HASH] or Scalar::Util::blessed($_[1]) && overload::Method($_[1], q[\%{}])/ },
	);
}

sub CodeLike ()
{
	require Type::Tiny;
	$cache{CodeLike} ||= "Type::Tiny"->new(
		name       => "CodeLike",
		constraint => sub {    ref($_   ) eq q[CODE] or Scalar::Util::blessed($_   ) && overload::Method($_   , q[&{}])  },
		inlined    => sub { qq/ref($_[1]) eq q[CODE] or Scalar::Util::blessed($_[1]) && overload::Method($_[1], q[\&{}])/ },
	);
}

sub TypeTiny ()
{
	require Type::Tiny;
	$cache{TypeTiny} ||= "Type::Tiny"->new(
		name       => "TypeTiny",
		constraint => sub {  Scalar::Util::blessed($_   ) && $_   ->isa(q[Type::Tiny])  },
		inlined    => sub { my $var = $_[1]; "Scalar::Util::blessed($var) && $var\->isa(q[Type::Tiny])" },
	);
}

sub to_TypeTiny
{
	my $t = $_[0];
	
	if (blessed($t) and ref($t)->isa("Moose::Meta::TypeConstraint"))
	{
		if ($t->can("tt_type") and my $tt = $t->tt_type)
		{
			return $tt;
		}
		
		my %opts;
		$opts{name}       = $t->name;
		$opts{constraint} = $t->constraint;
		$opts{parent}     = to_TypeTiny($t->parent)              if $t->has_parent;
		$opts{inlined}    = sub { shift; $t->_inline_check(@_) } if $t->can_be_inlined;
		$opts{message}    = sub { $t->get_message($_) }          if $t->has_message;
		
		require Type::Tiny;
		return "Type::Tiny"->new(%opts);
	}
	
	if (blessed($t) and ref($t)->isa("Mouse::Meta::TypeConstraint"))
	{
		my %opts;
		$opts{name}       = $t->name;
		$opts{constraint} = $t->constraint;
		$opts{parent}     = to_TypeTiny($t->parent)              if $t->has_parent;
		$opts{message}    = sub { $t->get_message($_) }          if $t->has_message;
		
		require Type::Tiny;
		return "Type::Tiny"->new(%opts);
	}

	return $t;
}

1;

__END__

