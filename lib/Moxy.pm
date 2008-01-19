package Moxy;
use strict;
use warnings;
require Class::Accessor::Fast;
use base qw/Class::Accessor::Fast/;

our $VERSION = '0.07';

__PACKAGE__->mk_accessors(qw/config/);

use Path::Class;
use YAML;
use Encode;
use FindBin;
use UNIVERSAL::require;
use Carp;
use Log::Dispatch;
my $TERM_ANSICOLOR_ENABLED = eval { use Term::ANSIColor; 1; };

sub new {
    my ($class, $config) = @_;

    my $self = bless { config => $config, }, $class;

    $self->{logger} = Log::Dispatch->new;

    $self->_init_server;

    $self->_load_plugins;

    $self->_init_ua_info;

    $self->_init_storage;

    $self->_init_logger;

    return $self;
}

sub run {
    my $self = shift;

    $self->{server}->run($self);
}

sub _load_plugins {
    my $self = shift;

    for my $plugin (@{$self->config->{plugins}}) {
        $self->log(debug => "load plugin: $plugin->{module}");

        my $module = "Moxy::Plugin::" . $plugin->{module};
        $module->require or die $@;
        $module->register($self);
    }
}

sub assets_path {
    my $self = shift;

    return $self->{__assets_path} ||= do {
        $self->config->{global}->{assets_path}
            || dir( $FindBin::RealBin, 'assets' )->stringify;
    };
}

# -------------------------------------------------------------------------

sub ua_list {
    my $self = shift;
    return $self->{__ua_list} ||= YAML::LoadFile( file( $self->assets_path, qw/common useragent.yaml/)->stringify );
}

sub _init_ua_info {
    my $self = shift;

    my $ua_hash;
    for my $agents (values %{$self->ua_list}) {
        for my $ua (@{$agents}) {
            $ua_hash->{$ua->{agent}} = $ua;
        }
    }
    $self->{__ua_hash} = $ua_hash;
}

sub get_ua_info {
    my ($self, $ua) = @_;

    return $self->{__ua_hash}->{$ua||''};
}

# -------------------------------------------------------------------------

sub _init_server {
    my $self = shift;

    my $conf = $self->{config}->{global}->{server};

    my $proto = $conf->{module} ? "Moxy::Server::$conf->{module}" : "Moxy::Server::HTTPProxy";

    $self->log(debug => "SETUP $proto");

    $proto->use or die $@;
    my $server = $proto->new($self, $conf);
    $self->{server} = $server;
}

# -------------------------------------------------------------------------

sub _init_storage {
    my ($self, ) = @_;

    my $mod = $self->{config}->{global}->{storage}->{module};
       $mod = $mod ? "Moxy::Storage::$mod" : 'Moxy::Storage::DBM_File';
    $mod->use or die $@;
    $self->{storage} = $mod->new($self, $self->{config}->{global}->{storage} || {});
}

sub storage { shift->{storage} }

# -------------------------------------------------------------------------

sub _init_logger {
    my ($self, ) = @_;

    for my $target (@{$self->config->{global}->{log}->{targets}}) {
        $target->{module}->use or die $@;
        $self->{logger}->add( $target->{module}->new( %{ $target->{conf} } ) );
    }
}

sub log {
    my ($self, $level, $msg, %opt) = @_;

    # hack to get the original caller as Plugin or Server
    my $caller = $opt{caller};
    unless ($caller) {
        my $i = 0;
        while (my $c = caller($i++)) {
            last if $c !~ /Plugin|Server/;
            $caller = $c;
        }
        $caller ||= caller(0);
    }

    chomp($msg);
    if ( $self->config->{global}->{log}->{encoding} ) {
        $msg = Encode::decode_utf8($msg) unless utf8::is_utf8($msg);
        $msg = Encode::encode( $self->config->{global}->{log}->{encoding}, $msg );
    }

    $self->{logger}->log(level => $level, message => "$caller [$level] $msg\n");
}

# -------------------------------------------------------------------------

sub register_hook {
    my ($self, @hooks) = @_;

    while ( my ( $hook, $callback ) = splice( @hooks, 0, 2 ) ) {
        croak "invalid args for register_hook" unless ref $callback eq 'CODE';

        push @{ $self->{hooks}->{$hook} }, $callback;
    }
}

sub run_hook {
    my ($self, $hook, @args) = @_;

    $self->log(debug => "Run hook: $hook");
    for my $action (@{$self->{hooks}->{$hook}}) {
        $action->($self, @args);
    }
}

sub get_hooks {
    my ($self, $hook) = @_;

    my $hooks = $self->{hooks}->{$hook};
    return unless $hooks;
    return wantarray ? @$hooks : $hooks;
}

1;
__END__

=head1 NAME

Moxy - Mobile web development proxy

=head1 DESCRIPTION

Moxy is a mobile web development proxy.

=head1 AUTHOR

    Kan Fushihara
    Tokuhiro Matsuno

=head1 SEE ALSO

L<http://coderepos.org/share/wiki/ssb>
