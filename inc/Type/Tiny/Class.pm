#line 1
package Type::Tiny::Class;

use 5.008001;
use strict;
use warnings;

BEGIN {
	$Type::Tiny::Class::AUTHORITY = 'cpan:TOBYINK';
	$Type::Tiny::Class::VERSION   = '0.003_08';
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
	return $proto->class->new(@_) if blessed $proto; # DWIM
	
	my %opts = @_;
	_croak "need to supply class name" unless exists $opts{class};
	return $proto->SUPER::new(%opts);
}

sub class       { $_[0]{class} }
sub inlined     { $_[0]{inlined} ||= $_[0]->_build_inlined }

sub has_inlined { !!1 }

sub _build_constraint
{
	my $self  = shift;
	my $class = $self->class;
	return sub { blessed($_) and $_->isa($class) };
}

sub _build_inlined
{
	my $self  = shift;
	my $class = $self->class;
	sub {
		my $var = $_[1];
		qq{Scalar::Util::blessed($var) and $var->isa(q[$class])};
	};
}

sub _build_default_message
{
	my $self = shift;
	my $c = $self->class;
	return sub { sprintf 'value "%s" did not pass type constraint (not isa %s)', $_[0], $c } if $self->is_anon;
	my $name = "$self";
	return sub { sprintf 'value "%s" did not pass type constraint "%s" (not isa %s)', $_[0], $name, $c };
}

sub _instantiate_moose_type
{
	my $self = shift;
	my %opts = @_;
	delete $opts{parent};
	delete $opts{constraint};
	delete $opts{inlined};
	require Moose::Meta::TypeConstraint::Class;
	return "Moose::Meta::TypeConstraint::Class"->new(%opts, class => $self->class);
}

sub plus_constructors
{
	my $self = shift;
	
	unless (@_)
	{
		require Types::Standard;
		push @_, Types::Standard::HashRef(), "new";
	}
	
	require B;
	require Types::TypeTiny;
	
	my $class = B::perlstring($self->class);
	
	my @r;
	while (@_)
	{
		my $source = shift;
		Types::TypeTiny::TypeTiny->check($source)
			or _croak "Expected type constraint; got $source";
		
		my $constructor = shift;
		Types::TypeTiny::StringLike->check($constructor)
			or _croak "Expected string; got $constructor";
		
		push @r, $source, sprintf('%s->%s($_)', $class, $constructor);
	}
	
	return $self->plus_coercions(\@r);
}

1;

__END__

