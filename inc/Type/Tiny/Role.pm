#line 1
package Type::Tiny::Role;

use 5.008001;
use strict;
use warnings;

BEGIN {
	$Type::Tiny::Role::AUTHORITY = 'cpan:TOBYINK';
	$Type::Tiny::Role::VERSION   = '0.003_08';
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
	_croak "need to supply role name" unless exists $opts{role};
	return $proto->SUPER::new(%opts);
}

sub role        { $_[0]{role} }
sub inlined     { $_[0]{inlined} ||= $_[0]->_build_inlined }

sub has_inlined { !!1 }

sub _build_constraint
{
	my $self = shift;
	my $role = $self->role;
	return sub { blessed($_) and do { my $method = $_->can('DOES')||$_->can('isa'); $_->$method($role) } };
}

sub _build_inlined
{
	my $self = shift;
	my $role = $self->role;
	sub {
		my $var = $_[1];
		qq{Scalar::Util::blessed($var) and do { my \$method = $var->can('DOES')||$var->can('isa'); $var->\$method(q[$role]) }};
	};
}

sub _build_default_message
{
	my $self = shift;
	my $c = $self->role;
	return sub { sprintf 'value "%s" did not pass type constraint (not DOES %s)', $_[0], $c } if $self->is_anon;
	my $name = "$self";
	return sub { sprintf 'value "%s" did not pass type constraint "%s" (not DOES %s)', $_[0], $name, $c };
}

1;

__END__

