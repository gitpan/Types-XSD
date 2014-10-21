#line 1
package Type::Tiny::Enum;

use 5.008001;
use strict;
use warnings;

BEGIN {
	$Type::Tiny::Enum::AUTHORITY = 'cpan:TOBYINK';
	$Type::Tiny::Enum::VERSION   = '0.003_08';
}

sub _croak ($;@)
{
	require Carp;
	@_ = sprintf($_[0], @_[1..$#_]) if @_ > 1;
	goto \&Carp::croak;
}

use overload q[@{}] => 'values';

use base "Type::Tiny";

sub new
{
	my $proto = shift;
	my %opts = @_;
	_croak "need to supply list of values" unless exists $opts{values};
	my %tmp =
		map { $_ => 1 }
		@{ ref $opts{values} eq "ARRAY" ? $opts{values} : [$opts{values}] };
	$opts{values} = [sort keys %tmp];
	return $proto->SUPER::new(%opts);
}

sub values      { $_[0]{values} }
sub constraint  { $_[0]{constraint} ||= $_[0]->_build_constraint }

sub _build_display_name
{
	my $self = shift;
	sprintf("Enum[%s]", join q[,], @$self);
}

sub _build_constraint
{
	my $self = shift;
	my $regexp = join "|", map quotemeta, @$self;
	return sub { defined and m{^(?:$regexp)$} };
}

sub can_be_inlined
{
	!!1;
}

sub inline_check
{
	my $self = shift;
	my $regexp = join "|", map quotemeta, @$self;
	$_[0] eq '$_'
		? "(defined and m{^(?:$regexp)\$})"
		: "(defined($_[0]) and $_[0] =~ m{^(?:$regexp)\$})";
}

sub _instantiate_moose_type
{
	my $self = shift;
	my %opts = @_;
	delete $opts{parent};
	delete $opts{constraint};
	delete $opts{inlined};
	require Moose::Meta::TypeConstraint::Enum;
	return "Moose::Meta::TypeConstraint::Enum"->new(%opts, values => $self->values);
}

1;

__END__

