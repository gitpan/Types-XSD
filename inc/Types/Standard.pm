#line 1
package Types::Standard;

use strict;
use warnings;

BEGIN {
	$Types::Standard::AUTHORITY = 'cpan:TOBYINK';
	$Types::Standard::VERSION   = '0.003_08';
}

use base "Type::Library";

our @EXPORT_OK = qw( slurpy );

use Scalar::Util qw( blessed looks_like_number );
use Type::Utils;
use Types::TypeTiny ();

sub _is_class_loaded {
	return !!0 if ref $_[0];
	return !!0 if !defined $_[0];
	my $stash = do { no strict 'refs'; \%{"$_[0]\::"} };
	return !!1 if exists $stash->{'ISA'};
	return !!1 if exists $stash->{'VERSION'};
	foreach my $globref (values %$stash) {
		return !!1 if *{$globref}{CODE};
	}
	return !!0;
}

sub _croak ($;@)
{
	require Carp;
	@_ = sprintf($_[0], @_[1..$#_]) if @_ > 1;
	goto \&Carp::croak;
}

no warnings;

declare "Any",
	_is_core => 1,
	inline_as { "!!1" };

declare "Item",
	_is_core => 1,
	inline_as { "!!1" };

declare "Bool",
	_is_core => 1,
	as "Item",
	where { !defined $_ or $_ eq q() or $_ eq '0' or $_ eq '1' },
	inline_as { "!defined $_ or $_ eq q() or $_ eq '0' or $_ eq '1'" };

declare "Undef",
	_is_core => 1,
	as "Item",
	where { !defined $_ },
	inline_as { "!defined($_)" };

declare "Defined",
	_is_core => 1,
	as "Item",
	where { defined $_ },
	inline_as { "defined($_)" };

declare "Value",
	_is_core => 1,
	as "Defined",
	where { not ref $_ },
	inline_as { "defined($_) and not ref($_)" };

declare "Str",
	_is_core => 1,
	as "Value",
	where { ref(\$_) eq 'SCALAR' or ref(\(my $val = $_)) eq 'SCALAR' },
	inline_as {
		"defined($_) and do { ref(\\$_) eq 'SCALAR' or ref(\\(my \$val = $_)) eq 'SCALAR' }"
	};

declare "Num",
	_is_core => 1,
	as "Str",
	where { looks_like_number $_ },
	inline_as { "!ref($_) && Scalar::Util::looks_like_number($_)" };

declare "Int",
	_is_core => 1,
	as "Num",
	where { /\A-?[0-9]+\z/ },
	inline_as { "defined $_ and $_ =~ /\\A-?[0-9]+\\z/" };

declare "ClassName",
	_is_core => 1,
	as "Str",
	where { goto \&_is_class_loaded },
	inline_as { "Types::Standard::_is_class_loaded($_)" };

declare "RoleName",
	as "ClassName",
	where { not $_->can("new") },
	inline_as { "Types::Standard::_is_class_loaded($_) and not $_->can('new')" };

declare "Ref",
	_is_core => 1,
	as "Defined",
	where { ref $_ },
	inline_as { "!!ref($_)" },
	constraint_generator => sub
	{
		my $reftype = shift;
		Types::TypeTiny::StringLike->check($reftype)
			or _croak("Parameter to Ref[`a] expected to be string; got $reftype");
		
		$reftype = "$reftype";
		return sub {
			ref($_[0]) and Scalar::Util::reftype($_[0]) eq $reftype;
		}
	},
	inline_generator => sub
	{
		my $reftype = shift;
		return sub {
			my $v = $_[1];
			"ref($v) and Scalar::Util::reftype($v) eq q($reftype)";
		};
	};

declare "CodeRef",
	_is_core => 1,
	as "Ref",
	where { ref $_ eq "CODE" },
	inline_as { "ref($_) eq 'CODE'" };

declare "RegexpRef",
	_is_core => 1,
	as "Ref",
	where { ref $_ eq "Regexp" },
	inline_as { "ref($_) eq 'Regexp'" };

declare "GlobRef",
	_is_core => 1,
	as "Ref",
	where { ref $_ eq "GLOB" },
	inline_as { "ref($_) eq 'GLOB'" };

declare "FileHandle",
	_is_core => 1,
	as "Ref",
	where {
		(ref($_) eq "GLOB" && Scalar::Util::openhandle($_))
		or (blessed($_) && $_->isa("IO::Handle"))
	},
	inline_as {
		"(ref($_) eq \"GLOB\" && Scalar::Util::openhandle($_)) ".
		"or (Scalar::Util::blessed($_) && $_->isa(\"IO::Handle\"))"
	};

declare "ArrayRef",
	_is_core => 1,
	as "Ref",
	where { ref $_ eq "ARRAY" },
	inline_as { "ref($_) eq 'ARRAY'" },
	constraint_generator => sub
	{
		require Types::Standard::AutomaticCoercion;
		
		my $param = Types::TypeTiny::to_TypeTiny(shift);
		Types::TypeTiny::TypeTiny->check($param)
			or _croak("Parameter to ArrayRef[`a] expected to be a type constraint; got $param");
		
		return sub
		{
			my $array = shift;
			$param->check($_) || return for @$array;
			return !!1;
		};
	},
	inline_generator => sub {
		my $param = shift;
		return unless $param->can_be_inlined;
		my $param_check = $param->inline_check('$i');
		return sub {
			my $v = $_[1];
			"ref($v) eq 'ARRAY' and do { "
			.  "my \$ok = 1; "
			.  "for my \$i (\@{$v}) { "
			.    "\$ok = 0 && last unless $param_check "
			.  "}; "
			.  "\$ok "
			."}"
		};
	};

declare "HashRef",
	_is_core => 1,
	as "Ref",
	where { ref $_ eq "HASH" },
	inline_as { "ref($_) eq 'HASH'" },
	constraint_generator => sub
	{
		require Types::Standard::AutomaticCoercion;
		
		my $param = Types::TypeTiny::to_TypeTiny(shift);
		Types::TypeTiny::TypeTiny->check($param)
			or _croak("Parameter to HashRef[`a] expected to be a type constraint; got $param");
		
		return sub
		{
			my $hash = shift;
			$param->check($_) || return for values %$hash;
			return !!1;
		};
	},
	inline_generator => sub {
		my $param = shift;
		return unless $param->can_be_inlined;
		my $param_check = $param->inline_check('$i');
		return sub {
			my $v = $_[1];
			"ref($v) eq 'HASH' and do { "
			.  "my \$ok = 1; "
			.  "for my \$i (values \%{$v}) { "
			.    "\$ok = 0 && last unless $param_check "
			.  "}; "
			.  "\$ok "
			."}"
		};
	};

declare "ScalarRef",
	_is_core => 1,
	as "Ref",
	where { ref $_ eq "SCALAR" or ref $_ eq "REF" },
	inline_as { "ref($_) eq 'SCALAR' or ref($_) eq 'REF'" },
	constraint_generator => sub
	{
		require Types::Standard::AutomaticCoercion;
		
		my $param = Types::TypeTiny::to_TypeTiny(shift);
		Types::TypeTiny::TypeTiny->check($param)
			or _croak("Parameter to ScalarRef[`a] expected to be a type constraint; got $param");
		
		return sub
		{
			my $ref = shift;
			$param->check($$ref) || return;
			return !!1;
		};
	},
	inline_generator => sub {
		my $param = shift;
		return unless $param->can_be_inlined;
		return sub {
			my $v = $_[1];
			my $param_check = $param->inline_check("\${$v}");
			"(ref($v) eq 'SCALAR' or ref($v) eq 'REF') and $param_check";
		};
	};

declare "Object",
	_is_core => 1,
	as "Ref",
	where { blessed $_ },
	inline_as { "Scalar::Util::blessed($_)" };

declare "Maybe",
	_is_core => 1,
	as "Item",
	constraint_generator => sub
	{
		my $param = Types::TypeTiny::to_TypeTiny(shift);
		Types::TypeTiny::TypeTiny->check($param)
			or _croak("Parameter to Maybe[`a] expected to be a type constraint; got $param");
		
		return sub
		{
			my $value = shift;
			return !!1 unless defined $value;
			return $param->check($value);
		};
	},
	inline_generator => sub {
		my $param = shift;
		return unless $param->can_be_inlined;
		return sub {
			my $v = $_[1];
			my $param_check = $param->inline_check($v);
			"!defined($v) or $param_check";
		};
	};

declare "Map",
	as "HashRef",
	where { ref $_ eq "HASH" },
	inline_as { "ref($_) eq 'HASH'" },
	constraint_generator => sub
	{
		require Types::Standard::AutomaticCoercion;
		
		my ($keys, $values) = map Types::TypeTiny::to_TypeTiny($_), @_;
		Types::TypeTiny::TypeTiny->check($keys)
			or _croak("First parameter to Map[`k,`v] expected to be a type constraint; got $keys");
		Types::TypeTiny::TypeTiny->check($values)
			or _croak("Second parameter to Map[`k,`v] expected to be a type constraint; got $values");
		
		return sub
		{
			my $hash = shift;
			$keys->check($_)   || return for keys %$hash;
			$values->check($_) || return for values %$hash;
			return !!1;
		};
	},
	inline_generator => sub {
		my ($k, $v) = @_;
		return unless $k->can_be_inlined && $v->can_be_inlined;
		my $k_check = $k->inline_check('$k');
		my $v_check = $v->inline_check('$v');
		return sub {
			my $h = $_[1];
			"ref($h) eq 'HASH' and do { "
			.  "my \$ok = 1; "
			.  "for my \$v (values \%{$h}) { "
			.    "\$ok = 0 && last unless $v_check "
			.  "}; "
			.  "for my \$k (keys \%{$h}) { "
			.    "\$ok = 0 && last unless $k_check "
			.  "}; "
			.  "\$ok "
			."}"
		};
	};

declare "Optional",
	as "Item",
	constraint_generator => sub
	{
		require Types::Standard::AutomaticCoercion;
		
		my $param = Types::TypeTiny::to_TypeTiny(shift);
		Types::TypeTiny::TypeTiny->check($param)
			or _croak("Parameter to Optional[`a] expected to be a type constraint; got $param");
		
		sub { exists($_[0]) ? $param->check($_[0]) : !!1 }
	},
	inline_generator => sub {
		my $param = shift;
		return unless $param->can_be_inlined;
		return sub {
			my $v = $_[1];
			my $param_check = $param->inline_check($v);
			"!exists($v) or $param_check";
		};
	};

sub slurpy ($) { +{ slurpy => $_[0] } }

declare "Tuple",
	as "ArrayRef",
	where { ref $_ eq "ARRAY" },
	inline_as { "ref($_) eq 'ARRAY'" },
	name_generator => sub
	{
		my ($s, @a) = @_;
		sprintf('%s[%s]', $s, join q[,], map { ref($_) eq "HASH" ? sprintf("slurpy %s", $_->{slurpy}) : $_ } @a);
	},
	constraint_generator => sub
	{
		require Types::Standard::AutomaticCoercion;
		
		my @constraints = @_;
		my $slurpy;
		if (exists $constraints[-1] and ref $constraints[-1] eq "HASH")
		{
			$slurpy = Types::TypeTiny::to_TypeTiny(pop(@constraints)->{slurpy});
			Types::TypeTiny::TypeTiny->check($slurpy)
				or _croak("Slurpy parameter to Tuple[...] expected to be a type constraint; got $slurpy");
		}

		@constraints = map Types::TypeTiny::to_TypeTiny($_), @constraints;
		for (@constraints)
		{
			Types::TypeTiny::TypeTiny->check($_)
				or _croak("Parameters to Tuple[...] expected to be type constraints; got $_");
		}
			
		return sub
		{
			my $value = $_[0];
			if ($#constraints < $#$value)
			{
				$slurpy or return;
				$slurpy->check([@$value[$#constraints+1 .. $#$value]]) or return;
			}
			for my $i (0 .. $#constraints)
			{
				$constraints[$i]->check(exists $value->[$i] ? $value->[$i] : ()) or return;
			}
			return !!1;
		};
	},
	inline_generator => sub
	{
		my @constraints = @_;
		my $slurpy;
		if (exists $constraints[-1] and ref $constraints[-1] eq "HASH")
		{
			$slurpy = pop(@constraints)->{slurpy};
		}
		
		return if grep { not $_->can_be_inlined } @constraints;
		return if defined $slurpy && !$slurpy->can_be_inlined;
		
		return sub
		{
			my $v = $_[1];
			join " and ",
				"ref($v) eq 'ARRAY'",
				($slurpy
					? sprintf("do { my \$tmp = [\@{$v}[%d..\$#{$v}]]; %s }", $#constraints+1, $slurpy->inline_check('$tmp'))
					: sprintf("\@{$v} <= %d", scalar @constraints)
				),
				map { $constraints[$_]->inline_check("$v\->[$_]") } 0 .. $#constraints;
		};
	};

declare "Dict",
	as "HashRef",
	where { ref $_ eq "HASH" },
	inline_as { "ref($_) eq 'HASH'" },
	name_generator => sub
	{
		my ($s, %a) = @_;
		sprintf('%s[%s]', $s, join q[,], map sprintf("%s=>%s", $_, $a{$_}), sort keys %a);
	},
	constraint_generator => sub
	{
		require Types::Standard::AutomaticCoercion;
		
		my %constraints = @_;
		
		while (my ($k, $v) = each %constraints)
		{
			$constraints{$k} = Types::TypeTiny::to_TypeTiny($v);
			Types::TypeTiny::TypeTiny->check($v)
				or _croak("Parameter to Dict[`a] for key '$k' expected to be a type constraint; got $v");
		}
		
		return sub
		{
			my $value = $_[0];
			exists ($constraints{$_}) || return for sort keys %$value;
			$constraints{$_}->check(exists $value->{$_} ? $value->{$_} : ()) || return for sort keys %constraints;
			return !!1;
		};
	},
	inline_generator => sub
	{
		# We can only inline a parameterized Dict if all the
		# constraints inside can be inlined.
		my %constraints = @_;
		for my $c (values %constraints)
		{
			next if $c->can_be_inlined;
			return;
		}
		my $regexp = join "|", map quotemeta, sort keys %constraints;
		return sub
		{
			require B;
			my $h = $_[1];
			join " and ",
				"ref($h) eq 'HASH'",
				"not(grep !/^($regexp)\$/, keys \%{$h})",
				map {
					my $k = B::perlstring($_);
					$constraints{$_}->inline_check("$h\->{$k}");
				}
				sort keys %constraints;
		}
	};

use overload ();
declare "Overload",
	as "Object",
	where { overload::Overloaded($_) },
	inline_as { "Scalar::Util::blessed($_) and overload::Overloaded($_)" },
	constraint_generator => sub
	{
		my @operations = map {
			Types::TypeTiny::StringLike->check($_)
				? "$_"
				: _croak("Parameters to Overload[`a] expected to be a strings; got $_");
		} @_;
		
		return sub {
			my $value = shift;
			for my $op (@operations) {
				return unless overload::Method($value, $op);
			}
			return !!1;
		}
	},
	inline_generator => sub {
		my @operations = @_;
		return sub {
			my $v = $_[1];
			join " and ",
				"Scalar::Util::blessed($v)",
				map "overload::Method($v, q[$_])", @operations;
		};
	};

declare "StrMatch",
	as "Str",
	constraint_generator => sub
	{
		my ($regexp, $checker) = @_;
		
		ref($regexp) eq 'Regexp'
			or _croak("First parameter to StrMatch[`a] expected to be a Regexp; got $regexp");

		if (@_ > 1)
		{
			$checker = Types::TypeTiny::to_TypeTiny($checker);
			Types::TypeTiny::TypeTiny->check($checker)
				or _croak("Second parameter to StrMatch[`a] expected to be a type constraint; got $checker")
		}

		$checker
			? sub {
				my $value = shift;
				return if ref($value);
				my @m = ($value =~ $regexp);
				$checker->check(\@m);
			}
			: sub {
				my $value = shift;
				!ref($value) and $value =~ $regexp;
			}
		;
	},
	inline_generator => sub
	{
		require B;
		my ($regexp, $checker) = @_;
		my $regexp_string = "$regexp";
		$regexp_string =~ s/\\\//\\\\\//g; # toothpicks
		if ($checker)
		{
			return unless $checker->can_be_inlined;
			return sub
			{
				my $v = $_[1];
				sprintf
					"!ref($v) and do { my \$m = [$v =~ /%s/]; %s }",
					$regexp_string,
					$checker->inline_check('$m'),
				;
			};
		}
		else
		{
			return sub
			{
				my $v = $_[1];
				sprintf
					"!ref($v) and $v =~ /%s/",
					$regexp_string,
				;
			};
		}
	};

declare "Bytes",
	as "Str",
	where { !utf8::is_utf8($_) },
	inline_as { "!utf8::is_utf8($_)" };

our $SevenBitSafe = qr{^[\x00-\x7F]*$}sm;
declare "Chars",
	as "Str",
	where { utf8::is_utf8($_) or $_ =~ $Types::Standard::SevenBitSafe },
	inline_as { "utf8::is_utf8($_) or $_ =~ \$Types::Standard::SevenBitSafe" };

declare "OptList",
	as ArrayRef( [ArrayRef()] ),
	where {
		for my $inner (@$_) {
			return unless @$inner == 2;
			return unless is_Str($inner->[0]);
		}
	},
	inline_as {
		my ($self, $var) = @_;
		my $Str_check = __PACKAGE__->meta->get_type("Str")->inline_check('$inner->[0]');
		my @code = 'do { my $ok = 1; ';
		push @code,   sprintf('for my $inner (@{%s}) { no warnings; ', $var);
		push @code,     '($ok=0) && last unless @$inner == 2; ';
		push @code,     sprintf('($ok=0) && last unless (%s); ', $Str_check);
		push @code,   '} ';
		push @code, '$ok }';
		sprintf(
			'%s and %s',
			$self->parent->inline_check($var),
			join(" ", @code),
		);
	};

declare "Tied",
	as "Ref",
	where { 
		!!tied(Scalar::Util::reftype($_) eq 'HASH' ?  %{$_} : Scalar::Util::reftype($_) eq 'ARRAY' ?  @{$_} :  ${$_})
	}
	inline_as {
		my $self = shift;
		$self->parent->inline_check(@_)
		. " and !!tied(Scalar::Util::reftype($_) eq 'HASH' ? \%{$_} : Scalar::Util::reftype($_) eq 'ARRAY' ? \@{$_} : \${$_})"
	}
	name_generator => sub
	{
		my $self  = shift;
		my $param = Types::TypeTiny::to_TypeTiny(shift);
		unless (Types::TypeTiny::TypeTiny->check($param))
		{
			Types::TypeTiny::StringLike->check($param)
				or _croak("Parameter to Tied[`a] expected to be a class name; got $param");
			require B;
			return sprintf("%s[%s]", $self, B::perlstring($param));
		}
		return sprintf("%s[%s]", $self, $param);
	},
	constraint_generator => sub
	{
		my $param = Types::TypeTiny::to_TypeTiny(shift);
		unless (Types::TypeTiny::TypeTiny->check($param))
		{
			Types::TypeTiny::StringLike->check($param)
				or _croak("Parameter to Tied[`a] expected to be a class name; got $param");
			require Type::Tiny::Class;
			$param = "Type::Tiny::Class"->new(class => "$param");
		}
		
		my $check = $param->compiled_check;
		return sub {
			$check->(tied(Scalar::Util::reftype($_) eq 'HASH' ?  %{$_} : Scalar::Util::reftype($_) eq 'ARRAY' ?  @{$_} :  ${$_}));
		};
	},
	inline_generator => sub {
		my $param = Types::TypeTiny::to_TypeTiny(shift);
		unless (Types::TypeTiny::TypeTiny->check($param))
		{
			Types::TypeTiny::StringLike->check($param)
				or _croak("Parameter to Tied[`a] expected to be a class name; got $param");
			require Type::Tiny::Class;
			$param = "Type::Tiny::Class"->new(class => "$param");
		}
		return unless $param->can_be_inlined;
		
		return sub {
			require B;
			my $var = $_[1];
			sprintf(
				"%s and do { my \$TIED = tied(Scalar::Util::reftype($var) eq 'HASH' ? \%{$var} : Scalar::Util::reftype($var) eq 'ARRAY' ? \@{$var} : \${$var}); %s }",
				Ref()->inline_check($var),
				$param->inline_check('$TIED')
			);
		};
	};

declare_coercion "MkOpt",
	to_type "OptList",
	from    "ArrayRef", q{ Exporter::TypeTiny::mkopt($_) },
	from    "HashRef",  q{ Exporter::TypeTiny::mkopt($_) },
	from    "Undef",    q{ [] };

declare_coercion "Decode", to_type "Chars" => {
	coercion_generator => sub {
		my ($self, $target, $encoding) = @_;
		require Encode;
		Encode::find_encoding($encoding)
			or _croak("Parameter \"$encoding\" for Decode[`a] is not an encoding supported by this version of Perl");
		require B;
		$encoding = B::perlstring($encoding);
		return (Bytes(), qq{ Encode::decode($encoding, \$_) });
	},
};

declare_coercion "Encode", to_type "Bytes" => {
	coercion_generator => sub {
		my ($self, $target, $encoding) = @_;
		require Encode;
		Encode::find_encoding($encoding)
			or _croak("Parameter \"$encoding\" for Encode[`a] is not an encoding supported by this version of Perl");
		require B;
		$encoding = B::perlstring($encoding);
		return (Chars(), qq{ Encode::encode($encoding, \$_) });
	},
};

declare_coercion "Join", to_type "Str" => {
	coercion_generator => sub {
		my ($self, $target, $sep) = @_;
		Types::TypeTiny::StringLike->check($sep)
			or _croak("Parameter to Join[`a] expected to be a string; got $sep");
		require B;
		$sep = B::perlstring($sep);
		return (ArrayRef(), qq{ join($sep, \@\$_) });
	},
};

declare_coercion "Split", to_type ArrayRef()->parameterize(Str()) => {
	coercion_generator => sub {
		my ($self, $target, $re) = @_;
		ref($re) eq q(Regexp)
			or _croak("Parameter to Split[`a] expected to be a regular expresssion; got $re");
		my $regexp_string = "$re";
		$regexp_string =~ s/\\\//\\\\\//g; # toothpicks
		return (Str(), qq{ [split /$regexp_string/, \$_] });
	},
};

1;

__END__

