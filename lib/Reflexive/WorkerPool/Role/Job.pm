package Reflexive::WorkerPool::Role::Job;

use Moose::Role;
use Reflex::POE::Wheel::Run;
use Reflex::Callbacks qw(cb_role cb_method cb_coderef);
use POE::Filter::Reference;
use Try::Tiny;
use Scalar::Util qw(reftype);

requires 'work';

has wheel => (
	is         => 'ro',
	isa        => 'Reflex::POE::Wheel::Run',
	writer     => '_set_wheel',
	clearer    => '_clear_wheel',
	lazy_build => 1,
);

sub run {
	my $self = shift;

	$self->emit(event => 'job_started', args => $self);

	$self->_set_wheel(
		Reflex::POE::Wheel::Run->new(
			Program => sub {
				my $self = shift;

				$self->_bind_update_handlers();
				$self->work();
				$self->ignore($self);
			},
			ProgramArgs => [ $self ],
			StdoutFilter => POE::Filter::Reference->new(),
			cb_role($self, "child"),
		)
	);
}

sub on_child_signal {
	my ( $self, $args ) = @_;

	$self->emit(event => 'job_stopped', args => $self);

	$self->_clear_wheel();
	$self->stopped();
}

sub on_child_stdout {
	my ( $self, $args ) = @_;

	$self->emit(event => 'job_updated', args => $args->{output});
}

################################################################################
# Happens in different session
################################################################################

sub _bind_update_handlers {
	my $self = shift;

	my @to_watch = grep {
		$_->does('Reflex::Trait::EmitsOnChange');
	} $self->meta->get_all_attributes();

	foreach my $attr ( @to_watch ) {
		my $name = $attr->{name};

		$self->watch(
			$self,
			$name => cb_coderef(sub {
				my $update = POE::Filter::Reference->new->put([{
					$name => $self->$name,
				}]);
				print @$update;
			}),
		);
	}
}

1;