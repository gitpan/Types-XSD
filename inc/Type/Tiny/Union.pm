#line 1
package Type::Tiny::Union;

use 5.008001;
use strict;
use warnings;

BEGIN {
	$Type::Tiny::Union::AUTHORITY = 'cpan:TOBYINK';
	$Type::Tiny::Union::VERSION   = '0.003_08';
}

use Scalar::Util qw< blessed >;
use Types::TypeTiny ();

sub _croak ($;@)
{
	require Carp;
	@_ = sprintf($_[0], @_[1..$#_]) if @_ > 1;
	goto \&Carp::croak;
}

use overload q[@{}] => 'type_constraints';

use base "Type::Tiny";

sub new {
	my $proto = shift;
	my %opts = @_;
	_croak "need to supply list of type constraints" unless exists $opts{type_constraints};
	$opts{type_constraints} = [
		map { $_->isa(__PACKAGE__) ? @$_ : $_ }
		map Types::TypeTiny::to_TypeTiny($_),
		@{ ref $opts{type_constraints} eq "ARRAY" ? $opts{type_constraints} : [$opts{type_constraints}] }
	];
	my $self = $proto->SUPER::new(%opts);
	$self->coercion if grep $_->has_coercion, @$self;
	return $self;
}

sub type_constraints { $_[0]{type_constraints} }
sub constraint       { $_[0]{constraint} ||= $_[0]->_build_constraint }

sub _build_display_name
{
	my $self = shift;
	join q[|], @$self;
}

sub _build_coercion
{
	require Type::Coercion::Union;
	my $self = shift;
	return "Type::Coercion::Union"->new(type_constraint => $self);
}

sub _build_constraint
{
	my @tcs = @{+shift};
	return sub
	{
		my $val = $_;
		$_->check($val) && return !!1 for @tcs;
		return;
	}
}

sub can_be_inlined
{
	my $self = shift;
	not grep !$_->can_be_inlined, @$self;
}

sub inline_check
{
	my $self = shift;
	sprintf '(%s)', join " or ", map $_->inline_check($_[0]), @$self;
}

sub _instantiate_moose_type
{
	my $self = shift;
	my %opts = @_;
	delete $opts{parent};
	delete $opts{constraint};
	delete $opts{inlined};
	
	my @tc = map $_->moose_type, @{$self->type_constraints};
	
	require Moose::Meta::TypeConstraint::Union;
	return "Moose::Meta::TypeConstraint::Union"->new(%opts, type_constraints => \@tc);
}

1;

__END__

