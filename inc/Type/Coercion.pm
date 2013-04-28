#line 1
package Type::Coercion;

use 5.008001;
use strict;
use warnings;

BEGIN {
	$Type::Coercion::AUTHORITY = 'cpan:TOBYINK';
	$Type::Coercion::VERSION   = '0.003_08';
}

use Scalar::Util qw< blessed >;
use Types::TypeTiny ();

sub _croak ($;@)
{
	require Carp;
	@_ = sprintf($_[0], @_[1..$#_]) if @_ > 1;
	goto \&Carp::croak;
}

use overload
	q("")      => sub { caller =~ m{^(Moo::HandleMoose|Sub::Quote)} ? overload::StrVal($_[0]) : $_[0]->display_name },
	q(bool)    => sub { 1 },
	q(&{})     => "_overload_coderef",
	q(+)       => sub { __PACKAGE__->add(@_) },
	fallback   => 1,
;
BEGIN {
	overload->import(q(~~) => sub { $_[0]->has_coercion_for_value($_[1]) })
		if $] >= 5.010001;
}

sub _overload_coderef
{
	my $self = shift;
	$self->{_overload_coderef} ||= "Sub::Quote"->can("quote_sub") && $self->can_be_inlined
		? Sub::Quote::quote_sub($self->inline_coercion('$_[0]'))
		: sub { $self->coerce(@_) }
}

sub new
{
	my $class  = shift;
	my %params = (@_==1) ? %{$_[0]} : @_;
	
	$params{name} = '__ANON__' unless exists $params{name};
	
	my $self   = bless \%params, $class;
	Scalar::Util::weaken($self->{type_constraint}); # break ref cycle
	return $self;
}

sub name                   { $_[0]{name} }
sub display_name           { $_[0]{display_name}      ||= $_[0]->_build_display_name }
sub library                { $_[0]{library} }
sub type_constraint        { $_[0]{type_constraint} }
sub type_coercion_map      { $_[0]{type_coercion_map} ||= [] }
sub moose_coercion         { $_[0]{moose_coercion}    ||= $_[0]->_build_moose_coercion }
sub compiled_coercion      { $_[0]{compiled_coercion} ||= $_[0]->_build_compiled_coercion }
sub frozen                 { $_[0]{frozen}            ||= 0 }
sub coercion_generator     { $_[0]{coercion_generator} }
sub parameters             { $_[0]{parameters} }

sub has_library            { exists $_[0]{library} }
sub has_type_constraint    { defined $_[0]{type_constraint} } # sic
sub has_coercion_generator { exists $_[0]{coercion_generator} }
sub has_parameters         { exists $_[0]{parameters} }

sub add
{
	my $class = shift;
	my ($x, $y, $swap) = @_;
	
	Types::TypeTiny::TypeTiny->check($x) and return $x->plus_fallback_coercions($y);
	Types::TypeTiny::TypeTiny->check($y) and return $y->plus_coercions($x);
	
	_croak "Attempt to add $class to something that is not a $class"
		unless blessed($x) && blessed($y) && $x->isa($class) && $y->isa($class);

	($y, $x) = ($x, $y) if $swap;

	my %opts;
	if ($x->has_type_constraint and $y->has_type_constraint and $x->type_constraint == $y->type_constraint)
	{
		$opts{type_constraint} = $x->type_constraint;
	}
	$opts{name} ||= "$x+$y";
	$opts{name} = '__ANON__' if $opts{name} eq '__ANON__+__ANON__';
	
	my $new = $class->new(%opts);
	$new->add_type_coercions( @{$x->type_coercion_map} );
	$new->add_type_coercions( @{$y->type_coercion_map} );
	return $new;
}

sub _build_display_name
{
	shift->name;
}

sub qualified_name
{
	my $self = shift;
	
	if ($self->has_library and not $self->is_anon)
	{
		return sprintf("%s::%s", $self->library, $self->name);
	}
	
	return $self->name;
}

sub is_anon
{
	my $self = shift;
	$self->name eq "__ANON__";
}

sub _clear_compiled_coercion {
	delete $_[0]{_overload_coderef};
	delete $_[0]{compiled_coercion};
}

sub freeze { $_[0]{frozen} = 1; $_[0] }

sub coerce
{
	my $self = shift;
	return $self->compiled_coercion->(@_);
}

sub assert_coerce
{
	my $self = shift;
	my $r = $self->coerce(@_);
	$self->type_constraint->assert_valid($r)
		if $self->has_type_constraint;
	return $r;
}

sub has_coercion_for_type
{
	my $self = shift;
	my $type = Types::TypeTiny::to_TypeTiny($_[0]);
	
	return "0 but true"
		if $self->has_type_constraint && $type->is_a_type_of($self->type_constraint);
	
	for my $has (@{$self->type_coercion_map})
	{
		return !!1 if Types::TypeTiny::TypeTiny->check($has) && $type->is_a_type_of($has);
	}
	
	return;
}

sub has_coercion_for_value
{
	my $self = shift;
	local $_ = $_[0];
	
	return "0 but true"
		if $self->has_type_constraint && $self->type_constraint->check(@_);
	
	my $c = $self->type_coercion_map;
	for (my $i = 0; $i <= $#$c; $i += 2)
	{
		return !!1 if $c->[$i]->check(@_);
	}
	return;
}

sub add_type_coercions
{
	my $self = shift;
	my @args = @_;
	
	_croak "Attempt to add coercion code to a Type::Coercion which has been frozen"
		if $self->frozen;
	
	while (@args)
	{
		my $type     = Types::TypeTiny::to_TypeTiny(shift @args);
		my $coercion = shift @args;
		
		_croak "Types must be blessed Type::Tiny objects"
			unless Types::TypeTiny::TypeTiny->check($type);
		_croak "Coercions must be code references or strings"
			unless Types::TypeTiny::StringLike->check($coercion) || Types::TypeTiny::CodeLike->check($coercion);
		
		push @{$self->type_coercion_map}, $type, $coercion;
	}
	
	$self->_clear_compiled_coercion;
	return $self;
}

sub _build_compiled_coercion
{
	my $self = shift;
	
	my @mishmash = @{$self->type_coercion_map};
	return sub { $_[0] } unless @mishmash;

	if ($self->can_be_inlined)
	{
		local $@;
		my $sub = eval sprintf('sub ($) { %s }', $self->inline_coercion('$_[0]'));
		die "Failed to compile coercion: $@\n\nCODE: ".$self->inline_coercion('$_[0]') if $@;
		return $sub;
	}

	# These arrays will be closed over.
	my (@types, @codes);
	while (@mishmash)
	{
		push @types, shift @mishmash;
		push @codes, shift @mishmash;
	}
	if ($self->has_type_constraint)
	{
		unshift @types, $self->type_constraint;
		unshift @codes, undef;
	}
	
	my @sub;
	
	for my $i (0..$#types)
	{
		push @sub,
			$types[$i]->can_be_inlined ? sprintf('if (%s)', $types[$i]->inline_check('$_[0]')) :
			sprintf('if ($types[%d]->check(@_))', $i);
		push @sub,
			!defined($codes[$i])
				? sprintf('  { return $_[0] }') :
			Types::TypeTiny::StringLike->check($codes[$i])
				? sprintf('  { local $_ = $_[0]; return( %s ) }', $codes[$i]) :
			sprintf('  { local $_ = $_[0]; return $codes[%d]->(@_) }', $i);
	}
	
	push @sub, 'return $_[0];';
	
	local $@;
	my $sub = eval sprintf('sub ($) { %s }', join qq[\n], @sub);
	die "Failed to compile coercion: $@\n\nCODE: @sub" if $@;
	return $sub;
}

sub can_be_inlined
{
	my $self = shift;
	my @mishmash = @{$self->type_coercion_map};
	return
		if $self->has_type_constraint
		&& !$self->type_constraint->can_be_inlined;
	while (@mishmash)
	{
		my ($type, $converter) = splice(@mishmash, 0, 2);
		return unless $type->can_be_inlined;
		return unless Types::TypeTiny::StringLike->check($converter);
	}
	return !!1;
}

sub _source_type_union
{
	my $self = shift;
	
	my @r;
	push @r, $self->type_constraint if $self->has_type_constraint;
	
	my @mishmash = @{$self->type_coercion_map};
	while (@mishmash)
	{
		my ($type) = splice(@mishmash, 0, 2);
		push @r, $type;
	}
	
	require Type::Tiny::Union;
	return "Type::Tiny::Union"->new(type_constraints => \@r, tmp => 1);
}

sub inline_coercion
{
	my $self = shift;
	my $varname = $_[0];
	
	_croak "This coercion cannot be inlined" unless $self->can_be_inlined;
	
	my @mishmash = @{$self->type_coercion_map};
	return "($varname)" unless @mishmash;
	
	my (@types, @codes);
	while (@mishmash)
	{
		push @types, shift @mishmash;
		push @codes, shift @mishmash;
	}
	if ($self->has_type_constraint)
	{
		unshift @types, $self->type_constraint;
		unshift @codes, undef;
	}
	
	my @sub;
	
	for my $i (0..$#types)
	{
		push @sub, sprintf('(%s) ?', $types[$i]->inline_check($varname));
		push @sub,
			(defined($codes[$i]) && ($varname eq '$_'))
				? sprintf('scalar(%s) :', $codes[$i]) :
			defined($codes[$i])
				? sprintf('do { local $_ = %s; scalar(%s) } :', $varname, $codes[$i]) :
			sprintf('%s :', $varname);
	}
	
	push @sub, "$varname";
	
	"@sub";
}

sub _build_moose_coercion
{
	my $self = shift;
	
	my %options = ();
	$options{type_coercion_map} = [ $self->freeze->_codelike_type_coercion_map('moose_type') ];
	$options{type_constraint}   = $self->type_constraint if $self->has_type_constraint;
	
	require Moose::Meta::TypeCoercion;
	my $r = "Moose::Meta::TypeCoercion"->new(%options);
	
	return $r;
}

sub _codelike_type_coercion_map
{
	my $self = shift;
	my $modifier = $_[0];
	
	my @orig = @{ $self->type_coercion_map };
	my @new;
	
	while (@orig)
	{
		my ($type, $converter) = splice(@orig, 0, 2);
		
		push @new, $modifier ? $type->$modifier : $type;
		
		if (Types::TypeTiny::CodeLike->check($converter))
		{
			push @new, $converter;
		}
		else
		{
			local $@;
			my $r = eval sprintf('sub { local $_ = $_[0]; %s }', $converter);
			die $@ if $@;
			push @new, $r;
		}
	}
	
	return @new;
}

sub is_parameterizable
{
	shift->has_coercion_generator;
}

sub is_parameterized
{
	shift->has_parameters;
}

sub parameterize
{
	my $self = shift;
	return $self unless @_;
	$self->is_parameterizable
		or _croak "constraint '%s' does not accept parameters", "$self";
	
	@_ = map Types::TypeTiny::to_TypeTiny($_), @_;
	
	return ref($self)->new(
		type_constraint    => $self->type_constraint,
		type_coercion_map  => [ $self->coercion_generator->($self, $self->type_constraint, @_) ],
		parameters         => \@_,
		frozen             => 1,
	);
}

sub isa
{
	my $self = shift;
	
	if ($INC{"Moose.pm"} and blessed($self) and $_[0] eq 'Moose::Meta::TypeCoercion')
	{
		return !!1;
	}
	
	if ($INC{"Moose.pm"} and blessed($self) and $_[0] =~ /^Moose/ and my $r = $self->moose_coercion->isa(@_))
	{
		return $r;
	}
	
	$self->SUPER::isa(@_);
}

sub can
{
	my $self = shift;
	
	my $can = $self->SUPER::can(@_);
	return $can if $can;
	
	if ($INC{"Moose.pm"} and blessed($self) and my $method = $self->moose_coercion->can(@_))
	{
		return sub { $method->(shift->moose_coercion, @_) };
	}
	
	return;
}

sub AUTOLOAD
{
	my $self = shift;
	my ($m) = (our $AUTOLOAD =~ /::(\w+)$/);
	return if $m eq 'DESTROY';
	
	if ($INC{"Moose.pm"} and blessed($self) and my $method = $self->moose_coercion->can($m))
	{
		return $method->($self->moose_coercion, @_);
	}
	
	_croak q[Can't locate object method "%s" via package "%s"], $m, ref($self)||$self;
}

*_compiled_type_coercion = \&compiled_coercion;

1;

__END__

