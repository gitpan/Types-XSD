#line 1
package Type::Tiny::Duck;

use 5.008001;
use strict;
use warnings;

BEGIN {
	$Type::Tiny::Duck::AUTHORITY = 'cpan:TOBYINK';
	$Type::Tiny::Duck::VERSION   = '0.003_08';
}

use Scalar::Util qw< blessed >;

sub _croak ($;@)
{
	require Carp;
	@_ = sprintf($_[0], @_[1..$#_]) if @_ > 1;
	goto \&Carp::croak;
}

use base "Type::Tiny";

sub new {
	my $proto = shift;
	my %opts = @_;
	_croak "need to supply list of methods" unless exists $opts{methods};
	$opts{methods} = [$opts{methods}] unless ref $opts{methods};
	return $proto->SUPER::new(%opts);
}

sub methods     { $_[0]{methods} }
sub inlined     { $_[0]{inlined} ||= $_[0]->_build_inlined }

sub has_inlined { !!1 }

sub _build_constraint
{
	my $self    = shift;
	my @methods = @{$self->methods};
	return sub { blessed($_[0]) and not grep(!$_[0]->can($_), @methods) };
}

sub _build_inlined
{
	my $self = shift;
	my @methods = @{$self->methods};
	sub {
		my $var = $_[1];
		local $" = q{ };
		qq{ Scalar::Util::blessed($var) and not grep(!$var->can(\$_), qw/@methods/) };
	};
}

sub _build_default_message
{
	my $self = shift;
	return sub { sprintf 'value "%s" did not pass type constraint', $_[0] } if $self->is_anon;
	my $name = "$self";
	return sub { sprintf 'value "%s" did not pass type constraint "%s"', $_[0], $name };
}

sub _instantiate_moose_type
{
	my $self = shift;
	my %opts = @_;
	delete $opts{parent};
	delete $opts{constraint};
	delete $opts{inlined};
	
	require Moose::Meta::TypeConstraint::DuckType;
	return "Moose::Meta::TypeConstraint::DuckType"->new(%opts, methods => $self->methods);
}

1;

__END__

