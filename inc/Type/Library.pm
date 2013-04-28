#line 1
package Type::Library;

use 5.008003;
use strict;
use warnings;

BEGIN {
	$Type::Tiny::AUTHORITY = 'cpan:TOBYINK';
	$Type::Tiny::VERSION   = '0.003_08';
}

use Scalar::Util qw< blessed >;
use Type::Tiny;
use Types::TypeTiny qw< TypeTiny to_TypeTiny >;

use base qw< Exporter::TypeTiny >;

sub _croak ($;@)
{
	require Carp;
	@_ = sprintf($_[0], @_[1..$#_]) if @_ > 1;
	goto \&Carp::croak;
}

{
	my $got_subname;
	sub _subname ($$)
	{
		$got_subname = 1 && goto \&Sub::Name::subname
			if $got_subname || eval "require Sub::Name";
		return $_[1];
	}
}

sub _exporter_validate_opts
{
	my $class = shift;
	
	no strict "refs";
	my $into  = $_[0]{into};
	push @{"$into\::ISA"}, $class if $_[0]{base};
	
	return $class->SUPER::_exporter_validate_opts(@_);
}

sub _exporter_expand_tag
{
	my $class = shift;
	my ($name, $value, $globals) = @_;
	
	$name eq 'types'     and return map [ "$_"        => $value ], $class->type_names;
	$name eq 'is'        and return map [ "is_$_"     => $value ], $class->type_names;
	$name eq 'assert'    and return map [ "assert_$_" => $value ], $class->type_names;
	$name eq 'to'        and return map [ "to_$_"     => $value ], $class->type_names;
	$name eq 'coercions' and return map [ "$_"        => $value ], $class->coercion_names;
	
	if ($name eq 'all')
	{
		no strict "refs";
		return (
			map(
				[ "+$_" => $value ],
				$class->type_names,
			),
			map(
				[ $_ => $value ],
				$class->coercion_names,
				@{"$class\::EXPORT"},
				@{"$class\::EXPORT_OK"},
			),
		);
	}
	
	return $class->SUPER::_exporter_expand_tag(@_);
}

sub _mksub
{
	my $class = shift;
	my ($type, $post_method) = @_;
	$post_method ||= "";
	
	my $coderef;
	if ($type->is_parameterizable)
	{
		$coderef = eval sprintf q{
			sub (;@) {
				my $params; $params = shift if ref($_[0]) eq q(ARRAY);
				my $t = $params ? $type->parameterize(@$params) : $type;
				@_ && wantarray ? return($t%s, @_) : return $t%s;
			}
		}, $post_method, $post_method;
	}
	else
	{
		$coderef = eval sprintf q{ sub () { $type%s } }, $post_method;
	}
	
	return _subname $type->qualified_name, $coderef;
}

sub _exporter_permitted_regexp
{
	my $class = shift;
	
	my $inherited = $class->SUPER::_exporter_permitted_regexp(@_);
	my $types = join "|", map quotemeta, sort {
		length($b) <=> length($a) or $a cmp $b
	} $class->type_names;
	my $coercions = join "|", map quotemeta, sort {
		length($b) <=> length($a) or $a cmp $b
	} $class->coercion_names;
	
	qr{^(?:
		$inherited
		| (?: (?:is_|to_|assert_)? (?:$types) )
		| (?:$coercions)
	)$}xms;
}

sub _exporter_expand_sub
{
	my $class = shift;
	my ($name, $value, $globals) = @_;
	
	if ($name =~ /^\+(.+)/ and $class->has_type($1))
	{
		my $type   = $1;
		my $value2 = +{%{$value||{}}};
		
		return map $class->_exporter_expand_sub($_, $value2, $globals),
			$type, "is_$type", "assert_$type", "to_$type";
	}
	
	if (my $type = $class->get_type($name))
	{
		my $post_method = '';
		$post_method = '->mouse_type' if $globals->{mouse};
		$post_method = '->moose_type' if $globals->{moose};
		return ($name => $class->_mksub($type, $post_method)) if $post_method;
	}
	
	return $class->SUPER::_exporter_expand_sub(@_);
}

#sub _exporter_install_sub
#{
#	my $class = shift;
#	my ($name, $value, $globals, $sym) = @_;
#	
#	warn sprintf(
#		'Exporter %s exporting %s with prototype %s',
#		$class,
#		$name,
#		prototype($sym),
#	);
#	
#	$class->SUPER::_exporter_install_sub(@_);
#}

sub _exporter_fail
{
	my $class = shift;
	my ($name, $value, $globals) = @_;
	
	my $into = $globals->{into}
		or _croak("Parameter 'into' not supplied");
	
	if ($globals->{declare})
	{
		return($name, _subname("$class\::$name", sub (;@)
		{
			my $params; $params = shift if ref($_[0]) eq "ARRAY";
			my $type = $into->get_type($name);
			unless ($type)
			{
				_croak "cannot parameterize a non-existant type" if $params;
				$type = $name;
			}
			
			my $t = $params ? $type->parameterize(@$params) : $type;
			@_ && wantarray ? return($t, @_) : return $t;
		}));
	}
	
	return $class->SUPER::_exporter_fail(@_);
}

sub meta
{
	no strict "refs";
	no warnings "once";
	return $_[0] if blessed $_[0];
	${"$_[0]\::META"} ||= bless {}, $_[0];
}

sub add_type
{
	my $meta = shift->meta;
	my $type = blessed($_[0]) ? to_TypeTiny($_[0]) : "Type::Tiny"->new(@_);
	my $name = $type->name;
	
	$meta->{types} ||= {};
	_croak 'Type %s already exists in this library', $name if $meta->has_type($name);
	_croak 'Type %s conflicts with coercion of same name', $name if $meta->has_coercion($name);
	_croak 'Cannot add anonymous type to a library' if $type->is_anon;
	$meta->{types}{$name} = $type;
	
	no strict "refs";
	no warnings "redefine", "prototype";
	
	my $class = blessed($meta);
	
	# There is an inlined coercion available, but don't use that because
	# additional coercions can be added *after* the type has been installed
	# into the library.
	#
	# XXX: maybe we can use it if the coercion is frozen???
	#
	*{"$class\::$name"}        = $class->_mksub($type);
	*{"$class\::is_$name"}     = _subname "is_"    .$type->qualified_name, $type->compiled_check;
	*{"$class\::to_$name"}     = _subname "to_"    .$type->qualified_name, sub ($) { $type->coerce($_[0]) };
	*{"$class\::assert_$name"} = _subname "assert_".$type->qualified_name, sub ($) { $type->assert_valid($_[0]) };
	
	return $type;
}

sub get_type
{
	my $meta = shift->meta;
	$meta->{types}{$_[0]};
}

sub has_type
{
	my $meta = shift->meta;
	exists $meta->{types}{$_[0]};
}

sub type_names
{
	my $meta = shift->meta;
	keys %{ $meta->{types} };
}

sub add_coercion
{
	my $meta = shift->meta;
	my $c    = blessed($_[0]) ? $_[0] : "Type::Coercion"->new(@_);
	my $name = $c->name;

	$meta->{coercions} ||= {};
	_croak 'Coercion %s already exists in this library', $name if $meta->has_coercion($name);
	_croak 'Coercion %s conflicts with type of same name', $name if $meta->has_type($name);
	_croak 'Cannot add anonymous type to a library' if $c->is_anon;
	$meta->{coercions}{$name} = $c;

	no strict "refs";
	no warnings "redefine", "prototype";
	
	my $class = blessed($meta);
	*{"$class\::$name"} = $class->_mksub($c);
	
	return $c;
}

sub get_coercion
{
	my $meta = shift->meta;
	$meta->{coercions}{$_[0]};
}

sub has_coercion
{
	my $meta = shift->meta;
	exists $meta->{coercions}{$_[0]};
}

sub coercion_names
{
	my $meta = shift->meta;
	keys %{ $meta->{coercions} };
}

1;

__END__

