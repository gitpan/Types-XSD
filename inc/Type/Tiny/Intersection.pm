#line 1
package Type::Tiny::Intersection;

use 5.008001;
use strict;
use warnings;

BEGIN {
	$Type::Tiny::Intersection::AUTHORITY = 'cpan:TOBYINK';
	$Type::Tiny::Intersection::VERSION   = '0.003_08';
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
	return $proto->SUPER::new(%opts);
}

sub type_constraints { $_[0]{type_constraints} }
sub constraint       { $_[0]{constraint} ||= $_[0]->_build_constraint }

sub _build_display_name
{
	my $self = shift;
	join q[&], @$self;
}

sub _build_constraint
{
	my @tcs = @{+shift};
	return sub
	{
		my $val = $_;
		$_->check($val) || return for @tcs;
		return !!1;
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
	sprintf '(%s)', join " and ", map $_->inline_check($_[0]), @$self;
}

1;

__END__

