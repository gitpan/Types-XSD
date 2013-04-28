#line 1
package Test::TypeTiny;

use Test::More ();
use base qw< Exporter::TypeTiny >;

our $AUTHORITY = 'cpan:TOBYINK';
our $VERSION   = '0.003_08';

our @EXPORT = qw( should_pass should_fail ok_subtype );

sub _mk_message
{
	require B;
	my ($template, $value) = @_;
	sprintf(
		$template,
		!defined $value      ? 'undef' :
		!ref $value          ? sprintf('value %s', B::perlstring($value)) :
		do {
			require Data::Dumper;
			local $Data::Dumper::Indent   = 0;
			local $Data::Dumper::Useqq    = 1;
			local $Data::Dumper::Terse    = 1;
			local $Data::Dumper::Maxdepth = 2;
			Data::Dumper::Dumper($value)
		}
	);
}

sub should_pass
{
	my ($value, $type, $message) = @_;
	@_ = (
		!!$type->check($value),
		$message || _mk_message("%s passes type constraint $type", $value),
	);
	goto \&Test::More::ok;
}

sub should_fail
{
	my ($value, $type, $message) = @_;
	@_ = (
		!$type->check($value),
		$message || _mk_message("%s fails type constraint $type", $value),
	);
	goto \&Test::More::ok;
}

sub ok_subtype
{
	my ($type, @s) = @_;
	@_ = (
		not(scalar grep !$_->is_subtype_of($type), @s),
		sprintf("%s subtype: %s", $type, join q[, ], @s),
	);
	goto \&Test::More::ok;
}

1;

__END__

