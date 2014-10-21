#line 1
package Type::Tiny;

use 5.008001;
use strict;
use warnings;

BEGIN {
	$Type::Tiny::AUTHORITY = 'cpan:TOBYINK';
	$Type::Tiny::VERSION   = '0.003_08';
}

use Scalar::Util qw< blessed weaken refaddr isweak >;
use Types::TypeTiny ();

sub _croak ($;@)
{
	require Carp;
	@_ = sprintf($_[0], @_[1..$#_]) if @_ > 1;
	goto \&Carp::croak;
}

sub _swap { $_[2] ? @_[1,0] : @_[0,1] }

use overload
	q("")      => sub { caller =~ m{^(Moo::HandleMoose|Sub::Quote)} ? overload::StrVal($_[0]) : $_[0]->display_name },
	q(bool)    => sub { 1 },
	q(&{})     => "_overload_coderef",
	q(+)       => sub { $_[2] ? $_[1]->plus_coercions($_[0]) : $_[0]->plus_fallback_coercions($_[1]) },
	q(|)       => sub { my @tc = _swap @_; require Type::Tiny::Union; "Type::Tiny::Union"->new(type_constraints => \@tc) },
	q(&)       => sub { my @tc = _swap @_; require Type::Tiny::Intersection; "Type::Tiny::Intersection"->new(type_constraints => \@tc) },
	q(~)       => sub { shift->complementary_type },
	q(==)      => sub { $_[0]->equals($_[1]) },
	q(<)       => sub { my $m = $_[0]->can('is_subtype_of'); $m->(_swap @_) },
	q(>)       => sub { my $m = $_[0]->can('is_subtype_of'); $m->(reverse _swap @_) },
	q(<=)      => sub { my $m = $_[0]->can('is_a_type_of');  $m->(_swap @_) },
	q(>=)      => sub { my $m = $_[0]->can('is_a_type_of');  $m->(reverse _swap @_) },
	fallback   => 1,
;
BEGIN {
	overload->import(q(~~) => sub { $_[0]->check($_[1]) })
		if $] >= 5.010001;
}

sub _overload_coderef
{
	my $self = shift;
	$self->message unless exists $self->{message};
	$self->{_overload_coderef} ||=
		$self->has_parent && $self->_is_null_constraint
			? $self->parent->_overload_coderef :
		$self->{_default_message} && "Sub::Quote"->can("quote_sub") && $self->can_be_inlined
			? Sub::Quote::quote_sub($self->inline_assert('$_[0]')) :
		sub { $self->assert_valid(@_) }
}

my $uniq = 1;
sub new
{
	my $class  = shift;
	my %params = (@_==1) ? %{$_[0]} : @_;
	
	if (exists $params{parent})
	{
		$params{parent} = Types::TypeTiny::to_TypeTiny($params{parent});
		
		_croak "parent must be an instance of %s", __PACKAGE__
			unless blessed($params{parent}) && $params{parent}->isa(__PACKAGE__);
	}
	
	$params{name} = "__ANON__" unless exists $params{name};
	$params{uniq} = $uniq++;
	
	if (exists $params{coercion} and !ref $params{coercion} and $params{coercion})
	{
		$params{parent}->has_coercion
			or _croak "coercion => 1 requires type to have a direct parent with a coercion";
		
		$params{coercion} = $params{parent}->coercion;
	}
	
	my $self = bless \%params, $class;
	
	unless ($self->is_anon)
	{
		# First try a fast ASCII-only expression, but fall back to Unicode
		$self->name =~ /^[A-Z][A-Za-z0-9_]+$/sm
			or eval q( $self->name =~ /^\p{Lu}[\p{L}0-9_]+$/sm )
			or _croak '"%s" is not a valid type name', $self->name;
	}
	
	if ($self->has_library and !$self->is_anon and !$params{tmp})
	{
		$Moo::HandleMoose::TYPE_MAP{overload::StrVal($self)} = sub { $self };
	}
		
	return $self;
}

sub _clone
{
	my $self = shift;
	my %opts;
	$opts{$_} = $self->{$_} for qw< name display_name message >;
	$self->create_child_type(%opts);
}

sub name                     { $_[0]{name} }
sub display_name             { $_[0]{display_name}   ||= $_[0]->_build_display_name }
sub parent                   { $_[0]{parent} }
sub constraint               { $_[0]{constraint}     ||= $_[0]->_build_constraint }
sub compiled_check           { $_[0]{compiled_check} ||= $_[0]->_build_compiled_check }
sub coercion                 { $_[0]{coercion}       ||= $_[0]->_build_coercion }
sub message                  { $_[0]{message} }
sub library                  { $_[0]{library} }
sub inlined                  { $_[0]{inlined} }
sub constraint_generator     { $_[0]{constraint_generator} }
sub inline_generator         { $_[0]{inline_generator} }
sub name_generator           { $_[0]{name_generator} ||= $_[0]->_build_name_generator }
sub coercion_generator       { $_[0]{coercion_generator} }
sub parameters               { $_[0]{parameters} }
sub moose_type               { $_[0]{moose_type}     ||= $_[0]->_build_moose_type }
sub mouse_type               { $_[0]{mouse_type}     ||= $_[0]->_build_mouse_type }

sub has_parent               { exists $_[0]{parent} }
sub has_library              { exists $_[0]{library} }
sub has_coercion             { exists $_[0]{coercion} and !!@{ $_[0]{coercion}->type_coercion_map } }
sub has_inlined              { exists $_[0]{inlined} }
sub has_constraint_generator { exists $_[0]{constraint_generator} }
sub has_inline_generator     { exists $_[0]{inline_generator} }
sub has_coercion_generator   { exists $_[0]{coercion_generator} }
sub has_parameters           { exists $_[0]{parameters} }
sub has_message              { exists $_[0]{message} }

sub _default_message         { $_[0]{_default_message} ||= $_[0]->_build_default_message }

sub _assert_coercion
{
	my $self = shift;
	_croak "no coercion for this type constraint"
		unless $self->has_coercion && @{$self->coercion->type_coercion_map};
	return $self->coercion;
}

my $null_constraint = sub { !!1 };

sub _build_display_name
{
	shift->name;
}

sub _build_constraint
{
	return $null_constraint;
}

sub _is_null_constraint
{
	shift->constraint == $null_constraint;
}

sub _build_coercion
{
	require Type::Coercion;
	my $self = shift;
	return "Type::Coercion"->new(type_constraint => $self);
}

sub _build_default_message
{
	my $self = shift;
	return sub { sprintf 'value "%s" did not pass type constraint', $_[0] } if $self->is_anon;
	my $name = "$self";
	return sub { sprintf 'value "%s" did not pass type constraint "%s"', $_[0], $name };
}

sub _build_name_generator
{
	my $self = shift;
	return sub {
		my ($s, @a) = @_;
		sprintf('%s[%s]', $s, join q[,], @a);
	};
}

sub _build_compiled_check
{
	my $self = shift;
	
	if ($self->_is_null_constraint and $self->has_parent)
	{
		return $self->parent->compiled_check;
	}
	
	if ($self->{_is_core} and $INC{'Mouse/Util.pm'} and Mouse::Util::MOUSE_XS())
	{
		require Mouse::Util::TypeConstraints;
		my $xs = "Mouse::Util::TypeConstraints"->can($self->name);
		return $xs if $xs;
	}
	
	if ($self->can_be_inlined)
	{
		local $@;
		my $sub = eval sprintf('sub ($) { %s }', $self->inline_check('$_[0]'));
		die "Failed to compile check for $self: $@\n\nCODE: ".$self->inline_check('$_[0]') if $@;
		return $sub;
	}
	
	my @constraints =
		reverse
		map  { $_->constraint }
		grep { not $_->_is_null_constraint }
		($self, $self->parents);
	
	return $null_constraint unless @constraints;
	
	return sub ($)
	{
		local $_ = $_[0];
		for my $c (@constraints)
		{
			return unless $c->(@_);
		}
		return !!1;
	};
}

sub equals
{
	my ($self, $other) = map Types::TypeTiny::to_TypeTiny($_), @_;
	return unless blessed($self)  && $self->isa("Type::Tiny");
	return unless blessed($other) && $other->isa("Type::Tiny");
	
	return !!1 if refaddr($self) == refaddr($other);
	
	return !!1 if $self->has_parent  && $self->_is_null_constraint  && $self->parent==$other;
	return !!1 if $other->has_parent && $other->_is_null_constraint && $other->parent==$self;
	
	return !!1 if refaddr($self->compiled_check) == refaddr($other->compiled_check);
	
	return $self->qualified_name eq $other->qualified_name
		if $self->has_library && !$self->is_anon && $other->has_library && !$other->is_anon;
	
	return $self->inline_check('$x') eq $other->inline_check('$x')
		if $self->can_be_inlined && $other->can_be_inlined;
	
	return;
}

sub is_subtype_of
{
	my ($self, $other) = map Types::TypeTiny::to_TypeTiny($_), @_;
	return unless blessed($self)  && $self->isa("Type::Tiny");
	return unless blessed($other) && $other->isa("Type::Tiny");

	my $this = $self;
	while (my $parent = $this->parent)
	{
		return !!1 if $parent->equals($other);
		$this = $parent;
	}
	return;
}

sub is_supertype_of
{
	my ($self, $other) = map Types::TypeTiny::to_TypeTiny($_), @_;
	return unless blessed($self)  && $self->isa("Type::Tiny");
	return unless blessed($other) && $other->isa("Type::Tiny");
	
	$other->is_subtype_of($self);
}

sub is_a_type_of
{
	my ($self, $other) = map Types::TypeTiny::to_TypeTiny($_), @_;
	return unless blessed($self)  && $self->isa("Type::Tiny");
	return unless blessed($other) && $other->isa("Type::Tiny");
	
	$self->equals($other) or $self->is_subtype_of($other);
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

sub parents
{
	my $self = shift;
	return unless $self->has_parent;
	return ($self->parent, $self->parent->parents);
}

sub check
{
	my $self = shift;
	$self->compiled_check->(@_);
}

sub get_message
{
	my $self = shift;
	local $_ = $_[0];
	$self->has_message
		? $self->message->(@_)
		: $self->_default_message->(@_);
}

sub validate
{
	my $self = shift;
	
	return undef if $self->compiled_check->(@_);
	
	local $_ = $_[0];
	return $self->get_message(@_);
}

sub assert_valid
{
	my $self = shift;
	
	return !!1 if $self->compiled_check->(@_);
	
	local $_ = $_[0];
	_croak $self->get_message(@_);
}

sub can_be_inlined
{
	my $self = shift;
	return $self->parent->can_be_inlined
		if $self->has_parent && $self->_is_null_constraint;
	return !!1
		if !$self->has_parent && $self->_is_null_constraint;
	return $self->has_inlined;
}

sub inline_check
{
	my $self = shift;
	_croak "cannot inline type constraint check for %s", $self
		unless $self->can_be_inlined;
	return $self->parent->inline_check(@_)
		if $self->has_parent && $self->_is_null_constraint;
	return '(!!1)'
		if !$self->has_parent && $self->_is_null_constraint;
	my $r = $self->inlined->($self, @_);
	$r =~ /[;{}]/ ? "(do { $r })" : "($r)";
}

sub inline_assert
{
	my $self = shift;
	my $varname = $_[0];
	my $code = sprintf(
		q[die qq(value "%s" did not pass type constraint "%s") unless %s;],
		$varname,
		"$self",
		$self->inline_check(@_),
	);
	return $code;
}

sub _inline_check
{
	shift->inline_check(@_);
}

sub coerce
{
	my $self = shift;
	$self->_assert_coercion->coerce(@_);
}

sub assert_coerce
{
	my $self = shift;
	$self->_assert_coercion->assert_coerce(@_);
}

sub is_parameterizable
{
	shift->has_constraint_generator;
}

sub is_parameterized
{
	shift->has_parameters;
}

my %param_cache;
sub parameterize
{
	my $self = shift;
	return $self unless @_;
	$self->is_parameterizable
		or _croak "type '%s' does not accept parameters", "$self";
	
	@_ = map Types::TypeTiny::to_TypeTiny($_), @_;
	
	# Generate a key for caching parameterized type constraints,
	# but only if all the parameters are strings or type constraints.
	my $key;
	unless (grep(ref($_) && !Types::TypeTiny::TypeTiny->check($_), @_))
	{
		require B;
		$key = join ":", map(Types::TypeTiny::TypeTiny->check($_) ? $_->{uniq} : B::perlstring($_), $self, @_);
	}
	
	return $param_cache{$key} if defined $key && defined $param_cache{$key};
	
	local $_ = $_[0];
	my %options = (
		constraint   => $self->constraint_generator->(@_),
		display_name => $self->name_generator->($self, @_),
		parameters   => [@_],
	);
	$options{inlined} = $self->inline_generator->(@_)
		if $self->has_inline_generator;
	exists $options{$_} && !defined $options{$_} && delete $options{$_}
		for keys %options;
	
	my $P = $self->create_child_type(%options);

	my $coercion = $self->coercion_generator->($self, $P, @_)
		if $self->has_coercion_generator;
	$P->coercion->add_type_coercions( @{$coercion->type_coercion_map} )
		if $coercion;
	
	if (defined $key)
	{
		$param_cache{$key} = $P;
		weaken($param_cache{$key});
	}
	
	return $P;
}

sub child_type_class
{
	__PACKAGE__;
}

sub create_child_type
{
	my $self = shift;
	return $self->child_type_class->new(parent => $self, @_);
}

sub complementary_type
{
	my $self = shift;
	my $r    = ($self->{complementary_type} ||= $self->_build_complementary_type);
	weaken($self->{complementary_type}) unless isweak($self->{complementary_type});
	return $r;
}

sub _build_complementary_type
{
	my $self = shift;
	my %opts = (
		constraint   => sub { not $self->check($_) },
		display_name => sprintf("~%s", $self),
	);
	$opts{display_name} =~ s/^\~{2}//;
	$opts{inlined} = sub { shift; "not(".$self->inline_check(@_).")" }
		if $self->can_be_inlined;
	return "Type::Tiny"->new(%opts);
}

sub _instantiate_moose_type
{
	my $self = shift;
	my %opts = @_;
	require Moose::Meta::TypeConstraint;
	return "Moose::Meta::TypeConstraint"->new(%opts);
}

my $trick_done = 0;
sub _build_moose_type
{
	my $self = shift;
	
	_MONKEY_MAGIC() unless $trick_done;
	
	my $r;
	if ($self->{_is_core})
	{
		require Moose::Util::TypeConstraints;
		$r = Moose::Util::TypeConstraints::find_type_constraint($self->name);
		$r->_set_tt_type($self);
	}
	else
	{
		my %opts;
		$opts{name}       = $self->qualified_name     if $self->has_library && !$self->is_anon;
		$opts{parent}     = $self->parent->moose_type if $self->has_parent;
		$opts{constraint} = $self->constraint         unless $self->_is_null_constraint;
		$opts{message}    = $self->message            if $self->has_message;
		$opts{inlined}    = $self->inlined            if $self->has_inlined;
		
		$r = $self->_instantiate_moose_type(%opts);
		$r->_set_tt_type($self);
		$self->{moose_type} = $r;  # prevent recursion
		$r->coercion($self->coercion->moose_coercion) if $self->has_coercion;
	}
		
	return $r;
}

sub _build_mouse_type
{
	my $self = shift;
	
	my %options;
	$options{name}       = $self->qualified_name     if $self->has_library && !$self->is_anon;
	$options{parent}     = $self->parent->mouse_type if $self->has_parent;
	$options{constraint} = $self->constraint         unless $self->_is_null_constraint;
	$options{message}    = $self->message            if $self->has_message;
		
	require Mouse::Meta::TypeConstraint;
	my $r = "Mouse::Meta::TypeConstraint"->new(%options);
	
	$self->{mouse_type} = $r;  # prevent recursion
	$r->_add_type_coercions(
		$self->coercion->freeze->_codelike_type_coercion_map('mouse_type')
	) if $self->has_coercion;
	
	return $r;
}

sub plus_coercions
{
	my $self = shift;
	
	my @more = (@_==1 && blessed($_[0]) && $_[0]->can('type_coercion_map'))
		? @{ $_[0]->type_coercion_map }
		: (@_==1 && ref $_[0]) ? @{$_[0]} : @_;
	
	my $new = $self->_clone;
	$new->coercion->add_type_coercions(
		@more,
		@{$self->coercion->type_coercion_map},
	);
	return $new;
}

sub plus_fallback_coercions
{
	my $self = shift;
	
	my @more = (@_==1 && blessed($_[0]) && $_[0]->can('type_coercion_map'))
		? @{ $_[0]->type_coercion_map }
		: (@_==1 && ref $_[0]) ? @{$_[0]} : @_;
	
	my $new = $self->_clone;
	$new->coercion->add_type_coercions(
		@{$self->coercion->type_coercion_map},
		@more,
	);
	return $new;
}

sub minus_coercions
{
	my $self = shift;
	
	my @not = (@_==1 && blessed($_[0]) && $_[0]->can('type_coercion_map'))
		? grep(blessed($_)&&$_->isa("Type::Tiny"), @{ $_[0]->type_coercion_map })
		: (@_==1 && ref $_[0]) ? @{$_[0]} : @_;
	
	my @keep;
	my $c = $self->coercion->type_coercion_map;
	for (my $i = 0; $i <= $#$c; $i += 2)
	{
		my $keep_this = 1;
		NOT: for my $n (@not)
		{
			if ($c->[$i] == $n)
			{
				$keep_this = 0;
				last NOT;
			}
		}
		
		push @keep, $c->[$i], $c->[$i+1] if $keep_this;
	}

	my $new = $self->_clone;
	$new->coercion->add_type_coercions(@keep);
	return $new;
}

sub no_coercions
{
	shift->_clone;
}

# Monkey patch Moose::Meta::TypeConstraint to refer to Type::Tiny
sub _MONKEY_MAGIC
{
	return if $trick_done;
	$trick_done++;
	
	eval q{
		package #
		Moose::Meta::TypeConstraint;
		my $meta = __PACKAGE__->meta;
		$meta->make_mutable;
		$meta->add_attribute(
			"Moose::Meta::Attribute"->new(
				tt_type => (
					reader    => "tt_type",
					writer    => "_set_tt_type",
					predicate => "has_tt_type",
					weak_ref  => 1,
					Class::MOP::_definition_context(),
				),
			),
		);
		$meta->make_immutable(inline_constructor => 0);
		1;
	} or _croak("could not perform magic Moose trick: $@");
}

sub isa
{
	my $self = shift;
	
	if ($INC{"Moose.pm"} and blessed($self) and $_[0] eq 'Moose::Meta::TypeConstraint')
	{
		return !!1;
	}
	
	if ($INC{"Moose.pm"} and blessed($self) and $_[0] =~ /^Moose/ and my $r = $self->moose_type->isa(@_))
	{
		return $r;
	}

	if ($INC{"Mouse.pm"} and blessed($self) and $_[0] eq 'Mouse::Meta::TypeConstraint')
	{
		return !!1;
	}

	$self->SUPER::isa(@_);
}

sub can
{
	my $self = shift;
	
	my $can = $self->SUPER::can(@_);
	return $can if $can;
	
	if ($INC{"Moose.pm"} and blessed($self) and my $method = $self->moose_type->can(@_))
	{
		return sub { $method->(shift->moose_type, @_) };
	}
	
	return;
}

sub AUTOLOAD
{
	my $self = shift;
	my ($m) = (our $AUTOLOAD =~ /::(\w+)$/);
	return if $m eq 'DESTROY';
	
	if ($INC{"Moose.pm"} and blessed($self) and my $method = $self->moose_type->can($m))
	{
		return $method->($self->moose_type, @_);
	}
	
	_croak q[Can't locate object method "%s" via package "%s"], $m, ref($self)||$self;
}

# fill out Moose-compatible API
sub inline_environment { +{} }
*_compiled_type_constraint = \&compiled_check;

# some stuff for Mouse-compatible API
*__is_parameterized = \&is_parameterized;
sub _add_type_coercions { shift->coercion->add_type_coercions(@_) };
*_as_string = \&qualified_name;
sub _compiled_type_coercion { shift->coercion->compiled_coercion(@_) };
sub _identify { refaddr(shift) };
sub _unite { require Type::Tiny::Union; "Type::Tiny::Union"->new(type_constraints => \@_) };

1;

__END__

