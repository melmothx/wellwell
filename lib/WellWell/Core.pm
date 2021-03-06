# WellWell::Core - WellWell core routines
#
# Copyright (C) 2010 Stefan Hornburg (Racke) <racke@linuxia.de>.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Free
# Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
# MA 02110-1301, USA.

package WellWell::Core;

use strict;
use warnings;

use vars qw/@ISA @EXPORT_OK/;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw/plugin_search_component/;

use Vend::Config;

use WellWell::Cart;
use WellWell::Data;
use WellWell::Plugin qw/plugin_scan plugin_enable/;
use WellWell::Engine;

# setup configuration directives
Vend::Config::parse_directive('Hook', 'Hook hook');
Vend::Config::parse_directive('StartupHooks', 'StartupHooks startup_hooks');

# predefined startup hooks
Vend::Config::parse_subroutine('GlobalSub', 'prepare_database WellWell::Data::prepare_database');
Vend::Config::parse_subroutine('GlobalSub', 'plugin_scan WellWell::Core::plugin_scan_sub');

# all what we want is to transfer CGI values from CGI to the Values
# space, and nothing else
Vend::Config::parse_tag('UserTag', 'values_update MapRoutine Vend::Dispatch::update_values');

sub plugins_from_var {
	my @plugins;
	
	# simply return a list of plugins sitting in $Variable
	@plugins = split(/,/, $::Variable->{PLUGINS});

	return @plugins;
}

# called at startup to scan plugins
sub plugin_scan_sub {
	my ($dbif, $plref, $active);

	WellWell::Data::make_classes($Vend::Config::C->{CatalogName});

	$plref = WellWell::Plugin::plugin_scan('plugins', 'local/plugins');

	# first pass for enabling plugins in the database from PLUGINS variable
	for my $plugin (plugins_from_var()) {
		if (exists $plref->{$plugin}) {
			if ($plref->{$plugin}->active eq 0) {
				Vend::Config::config_error("Plugin $plugin used in PLUGINS variable is explicitly disabled in plugins table.");
				return;
			}
			elsif (! defined($plref->{$plugin}->active)) {
				Vend::Config::config_warn("Enabling plugin $plugin in plugins table.");
				plugin_enable($plref->{$plugin});
			}
		}
	}

	for my $plugin (keys %$plref) {
		if ($plref->{$plugin}->active) {
			# search path for components and pages
			push(@{$Vend::Cfg->{TemplateDir}}, $plref->{$plugin}->{directory},
				 "$plref->{$plugin}->{directory}/pages");
		}
	}

	# store in catalog configuration
	$Vend::Cfg->{PluginRepository} = $plref;
}

sub plugin_search_component {
	my ($name) = @_;
	my ($plugin, $ref);
	
	while (($plugin, $ref) = each %{$Vend::Cfg->{PluginRepository}}) {
		if (-f "$ref->{directory}/components/$name") {
			return $ref;
		}
	}
}

sub hooks {
	my ($function, $name, @args) = @_;

	if ($function eq 'run') {
		if (exists $Vend::Cfg->{Hook}->{$name}) {
			my @hooks = @{$Vend::Cfg->{Hook}->{$name}};

			for my $hook (@hooks) {
				$hook->(@args);
			}
		}
	}
}

package Vend::Config;

sub parse_hook {
	my ($item, $settings) = @_;

	# parse routine is called once per catalog, regardless of configuration
	# directives
	return {} unless $settings;

	my ($name, $param, $value) = split(/\s+/, $settings);

	if (exists $C->{Sub}->{$param}) {
		push(@{$C->{$item}->{$name}}, $C->{Sub}->{$param});
	}
	else {
		config_error('Subroutine %s missing.', $param);
	}
	
	return $C->{$item};
}

sub parse_startup_hooks {
	my ($name, $routines) = @_;

	$Vend::Config::Default{$name} = sub {
		my $routines = shift;
		my $save = $Vend::Cfg;
		$Vend::Cfg = $Vend::Config::C;
		$::Variable = $Vend::Cfg->{Variable};
		$::Pragma = $Vend::Cfg->{Pragma};
		open_database();
		Vend::Dispatch::run_macro($routines);
#		$Vend::Cfg = $save;
		return 1;
	};

	return $routines || '';
}

1;
