#line 1
package Exporter::TypeTiny;

use 5.008001;
use strict;   no strict qw(refs);
use warnings; no warnings qw(void once uninitialized numeric redefine);

our $AUTHORITY = 'cpan:TOBYINK';
our $VERSION   = '0.003_08';
our @EXPORT_OK = qw< mkopt mkopt_hash _croak >;

sub _croak ($;@) {
	require Carp;
	@_ = sprintf($_[0], @_[1..$#_]) if @_ > 1;
	goto \&Carp::croak;
}

sub import
{
	my $class       = shift;
	my $global_opts = +{ @_ && ref($_[0]) eq q(HASH) ? %{+shift} : () };
	my @args        = @_ ? @_ : @{"$class\::EXPORT"};
	my $opts        = mkopt(\@args);
	
	$global_opts->{into} = caller unless exists $global_opts->{into};
	my @want;
	
	while (@$opts)
	{
		my $opt = shift @{$opts};
		my ($name, $value) = @$opt;
		
		$name =~ /^[:-](.+)$/
			? push(@$opts, $class->_exporter_expand_tag($1, $value, $global_opts))
			: push(@want, $opt);
	}
	
	$class->_exporter_validate_opts($global_opts);
	my $permitted = $class->_exporter_permitted_regexp($global_opts);
	
	for my $wanted (@want)
	{
		my %symbols = $class->_exporter_expand_sub(@$wanted, $global_opts, $permitted);
		$class->_exporter_install_sub($_, $wanted->[1], $global_opts, $symbols{$_})
			for keys %symbols;
	}
}

# Called once per import, passed the "global" import options. Expected to
# validate the import options and carp or croak if there are problems. Can
# also take the opportunity to do other stuff if needed.
#
sub _exporter_validate_opts
{
	1;
}

# Given a tag name, looks it up in %EXPORT_TAGS and returns the list of
# associated functions. The default implementation magically handles tags
# "all" and "default". The default implementation interprets any undefined
# tags as being global options.
# 
sub _exporter_expand_tag
{
	my $class = shift;
	my ($name, $value, $globals) = @_;
	my $tags  = \%{"$class\::EXPORT_TAGS"};
	
	return map [$_ => $value], @{$tags->{$name}}
		if exists $tags->{$name};
	
	return map [$_ => $value], @{"$class\::EXPORT"}, @{"$class\::EXPORT_OK"}
		if $name eq 'all';
	
	return map [$_ => $value], @{"$class\::EXPORT"}
		if $name eq 'default';
	
	$globals->{$name} = $value || 1;
	return;
}

# Helper for _exporter_expand_sub. Returns a regexp matching all subs in
# the exporter package which are available for export.
#
sub _exporter_permitted_regexp
{
	my $class = shift;
	my $re = join "|", map quotemeta, sort {
		length($b) <=> length($a) or $a cmp $b
	} @{"$class\::EXPORT"}, @{"$class\::EXPORT_OK"};
	qr{^(?:$re)$}ms;
}

# Given a sub name, returns a hash of subs to install (usually just one sub).
# Keys are sub names, values are coderefs.
#
sub _exporter_expand_sub
{
	my $class = shift;
	my ($name, $value, $globals, $permitted) = @_;
	$permitted ||= $class->_exporter_permitted_regexp($globals);
	
	exists &{"$class\::$name"} && $name =~ $permitted
		? ($name => \&{"$class\::$name"})
		: $class->_exporter_fail(@_);
}

# Called by _exporter_expand_sub if it is unable to generate a key-value
# pair for a sub.
#
sub _exporter_fail
{
	my $class = shift;
	my ($name, $value, $globals) = @_;
	_croak("Could not find sub '$name' to export in package '$class'");
}

# Actually performs the installation of the sub into the target package. This
# also handles renaming the sub.
#
sub _exporter_install_sub
{
	my $class = shift;
	my ($name, $value, $globals, $sym) = @_;
	
	my $into      = $globals->{into};
	my $installer = $globals->{installer} || $globals->{exporter};
	
	$name = $value->{-as} || $name;
	unless (ref($name) eq q(SCALAR))
	{
		my ($prefix) = grep defined, $value->{-prefix}, $globals->{prefix}, '';
		my ($suffix) = grep defined, $value->{-suffix}, $globals->{suffix}, '';
		$name = "$prefix$name$suffix";
	}
	
	return $installer->($globals, [$name, $sym]) if $installer;
	return ($$name = $sym)                       if ref($name) eq q(SCALAR);
	return ($into->{$name} = $sym)               if ref($into) eq q(HASH);
	
	require B;
	for (grep ref, $into->can($name))
	{
		my $cv = B::svref_2object($_);
		$cv->STASH->NAME eq $into
			and _croak("Refusing to overwrite local sub '$name' with export from $class");
	}
	
	*{"$into\::$name"} = $sym;
}

sub mkopt
{
	my $in = shift or return [];
	my @out;
	
	$in = [map(($_ => ref($in->{$_}) ? $in->{$_} : ()), sort keys %$in)]
		if ref($in) eq q(HASH);
	
	for (my $i = 0; $i < @$in; $i++)
	{
		my $k = $in->[$i];
		my $v;
		
		($i == $#$in)         ? ($v = undef) :
		!defined($in->[$i+1]) ? (++$i, ($v = undef)) :
		!ref($in->[$i+1])     ? ($v = undef) :
		($v = $in->[++$i]);
		
		push @out, [ $k => $v ];
	}
	
	\@out;
}

sub mkopt_hash
{
	my $in  = shift or return;
	my %out = map @$_, mkopt($in);
	\%out;
}

1;

__END__

