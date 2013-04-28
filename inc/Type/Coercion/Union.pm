#line 1
package Type::Coercion::Union;

use 5.008001;
use strict;
use warnings;

BEGIN {
	$Type::Coercion::Union::AUTHORITY = 'cpan:TOBYINK';
	$Type::Coercion::Union::VERSION   = '0.003_08';
}

use Scalar::Util qw< blessed >;
use Types::TypeTiny ();

sub _croak ($;@)
{
	require Carp;
	@_ = sprintf($_[0], @_[1..$#_]) if @_ > 1;
	goto \&Carp::croak;
}

use base "Type::Coercion";

sub type_coercion_map
{
	my $self = shift;
	
	Types::TypeTiny::TypeTiny->assert_valid(my $type = $self->type_constraint);
	$type->isa('Type::Tiny::Union')
		or _croak "Type::Coercion::Union must be used in conjunction with Type::Tiny::Union";
	
	my @c;
	for my $tc (@$type)
	{
		next unless $tc->has_coercion;
		push @c, @{$tc->coercion->type_coercion_map};
	}
	return \@c;
}

sub add_type_coercions
{
	my $self = shift;
	_croak "adding coercions to Type::Coercion::Union not currently supported";
}

# sub _build_moose_coercion ???

1;

__END__

