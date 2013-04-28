#line 1
package Type::Utils;

use 5.008001;
use strict;
use warnings;

BEGIN {
	$Type::Utils::AUTHORITY = 'cpan:TOBYINK';
	$Type::Utils::VERSION   = '0.003_08';
}

sub _croak ($;@) {
	require Carp;
	@_ = sprintf($_[0], @_[1..$#_]) if @_ > 1;
	goto \&Carp::croak;
}

use Scalar::Util qw< blessed >;
use Type::Library;
use Type::Tiny;
use Types::TypeTiny qw< TypeTiny to_TypeTiny HashLike >;

our @EXPORT = qw<
	extends declare as where message inline_as
	class_type role_type duck_type union intersection enum
	coerce from via
	declare_coercion to_type
>;
our @EXPORT_OK = (@EXPORT, qw< type subtype >);

use base qw< Exporter::TypeTiny >;

sub extends
{
	_croak "Not a type library" unless caller->isa("Type::Library");
	my $caller = caller->meta;
	
	foreach my $lib (@_)
	{
		eval "require $lib" or _croak "Could not load library '$lib': $@";
		$caller->add_type($lib->get_type($_)) for $lib->meta->type_names;
	}
}

sub declare
{
	my %opts;
	if (@_ % 2 == 0)
	{
		%opts = @_;
	}
	else
	{
		(my($name), %opts) = @_;
		_croak "Cannot provide two names for type" if exists $opts{name};
		$opts{name} = $name;
	}

	my $caller = caller($opts{_caller_level} || 0);
	$opts{library} = $caller;

	if (defined $opts{parent})
	{
		$opts{parent} = to_TypeTiny($opts{parent});
		
		unless (TypeTiny->check($opts{parent}))
		{
			$caller->isa("Type::Library")
				or _croak "Parent type cannot be a string";
			$opts{parent} = $caller->meta->get_type($opts{parent})
				or _croak "Could not find parent type";
		}
	}
		
	my $type;
	if (defined $opts{parent})
	{
		$type = delete($opts{parent})->create_child_type(%opts);
	}
	else
	{
		my $bless = delete($opts{bless}) || "Type::Tiny";
		eval "require $bless";
		$type = $bless->new(%opts);
	}
	
	if ($caller->isa("Type::Library"))
	{
		$caller->meta->add_type($type) unless $type->is_anon;
	}
	
	return $type;
}

*subtype = \&declare;
*type = \&declare;

sub as (@)
{
	parent => @_;
}

sub where (&;@)
{
	constraint => @_;
}

sub message (&;@)
{
	message => @_;
}

sub inline_as (&;@)
{
	my $coderef = shift;
	inlined => sub { local $_ = $_[1]; $coderef->(@_) }, @_;
}

sub class_type
{
	my $name = ref($_[0]) ? undef : shift;
	my %opts = %{ +shift };
	
	if (defined $name)
	{
		$opts{name}  = $name unless exists $opts{name};
		$opts{class} = $name unless exists $opts{class};
	}
	
	$opts{bless} = "Type::Tiny::Class";
	
	{ no warnings "numeric"; $opts{_caller_level}++ }
	declare(%opts);
}

sub role_type
{
	my $name = ref($_[0]) ? undef : shift;
	my %opts = %{ +shift };
	
	if (defined $name)
	{
		$opts{name}  = $name unless exists $opts{name};
		$opts{role}  = $name unless exists $opts{role};
	}
	
	$opts{bless} = "Type::Tiny::Role";
	
	{ no warnings "numeric"; $opts{_caller_level}++ }
	declare(%opts);
}

sub duck_type
{
	my $name    = ref($_[0]) ? undef : shift;
	my @methods = @{ +shift };
	
	my %opts;
	$opts{name} = $name if defined $name;
	$opts{methods} = \@methods;
	
	$opts{bless} = "Type::Tiny::Duck";
	
	{ no warnings "numeric"; $opts{_caller_level}++ }
	declare(%opts);
}

sub enum
{
	my $name   = ref($_[0]) ? undef : shift;
	my @values = @{ +shift };
	
	my %opts;
	$opts{name} = $name if defined $name;
	$opts{values} = \@values;
	
	$opts{bless} = "Type::Tiny::Enum";
	
	{ no warnings "numeric"; $opts{_caller_level}++ }
	declare(%opts);
}

sub union
{
	my $name = ref($_[0]) ? undef : shift;
	my @tcs  = @{ +shift };
	
	my %opts;
	$opts{name} = $name if defined $name;
	$opts{type_constraints} = \@tcs;
	
	$opts{bless} = "Type::Tiny::Union";
	
	{ no warnings "numeric"; $opts{_caller_level}++ }
	declare(%opts);
}

sub intersection
{
	my $name = ref($_[0]) ? undef : shift;
	my @tcs  = @{ +shift };
	
	my %opts;
	$opts{name} = $name if defined $name;
	$opts{type_constraints} = \@tcs;
	
	$opts{bless} = "Type::Tiny::Intersection";
	
	{ no warnings "numeric"; $opts{_caller_level}++ }
	declare(%opts);
}

sub declare_coercion
{
	my %opts;
	$opts{name} = shift if !ref($_[0]);
	
	while (HashLike->check($_[0]) and not TypeTiny->check($_[0]))
	{
		%opts = (%opts, %{+shift});
	}
	
	my $caller = caller($opts{_caller_level} || 0);
	$opts{library} = $caller;
	
	my $bless = delete($opts{bless}) || "Type::Coercion";
	eval "require $bless";
	my $c = $bless->new(%opts);
	
	my @C = @_;
	
	if ($caller->isa("Type::Library"))
	{
		my $meta = $caller->meta;
		$meta->add_coercion($c) unless $c->is_anon;
		@C = map { ref($_) ? to_TypeTiny($_) : $meta->get_type($_)||$_ } @C;
	}
	
	$c->add_type_coercions(@C);
	
	return $c->freeze;
}

sub coerce
{
	if ((scalar caller)->isa("Type::Library"))
	{
		my $meta = (scalar caller)->meta;
		my ($type, @opts) = map { ref($_) ? to_TypeTiny($_) : $meta->get_type($_)||$_ } @_;
		return $type->coercion->add_type_coercions(@opts);
	}
	
	my ($type, @opts) = @_;
	$type = to_TypeTiny($type);
	return $type->coercion->add_type_coercions(@opts);
}

sub from (@)
{
	return @_;
}

sub to_type (@)
{
	my $type = shift;
	unless (TypeTiny->check($type))
	{
		caller->isa("Type::Library")
			or _croak "Target type cannot be a string";
		$type = caller->meta->get_type($type)
			or _croak "Could not find target type";
	}
	return +{ type_constraint => $type }, @_;
}

sub via (&;@)
{
	return @_;
}

1;

__END__

