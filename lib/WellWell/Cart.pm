# WellWell::Cart - WellWell cart routines
#
# Copyright (C) 2009,2010 Stefan Hornburg (Racke) <racke@linuxia.de>.
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

package WellWell::Cart;

use strict;
use warnings;

use Vend::Config;
use Vend::Tags;
use Vend::Data;

Vend::Config::parse_tag('UserTag', 'cart_add Order sku quantity');
Vend::Config::parse_tag('UserTag', 'cart_add AddAttr');
Vend::Config::parse_tag('UserTag', 'cart_add MapRoutine WellWell::Cart::cart_add');

Vend::Config::parse_tag('UserTag', 'cart_item Order sku quantity');
Vend::Config::parse_tag('UserTag', 'cart_item AddAttr');
Vend::Config::parse_tag('UserTag', 'cart_item MapRoutine WellWell::Cart::cart_item');

Vend::Config::parse_tag('UserTag', 'cart_refresh MapRoutine WellWell::Cart::cart_refresh');
Vend::Config::parse_subroutine('GlobalSub', 'cart_refresh WellWell::Cart::cart_refresh_form_action');

# [cart-item] - returns item hash ready to put it into cart

sub cart_item {
	my ($sku, $quantity, $opt) = @_;
	my ($db_products, $product_ref, %item);

	unless ($db_products = database_exists_ref('products')) {
		die errmsg("Database missing: %s", 'products');
	}
	
	$quantity ||= 1;
	
    %item = (code => $sku,
			 quantity => $quantity,
			 mv_mi => Vend::Tags->time({format => '%s'}) . sprintf('%06d', ++$Vend::Session->{pageCount}),
			 mv_si => 0);

	$product_ref = $db_products->row_hash($sku);
	
	for (@{$Vend::Cfg->{AutoModifier}}) {
		$item{$_} = $opt->{$_} || $product_ref->{$_};
	}

	for (@{$Vend::Cfg->{UseModifier}}) {
		if (exists $opt->{$_}) {
			$item{$_} = $opt->{$_};
		}
	}

	return \%item;
}

# [cart-add] - add item to cart

sub cart_add {
	my ($sku, $quantity, $opt) = @_;
	my ($itemref);
	
	$itemref = cart_item($sku, $quantity, $opt);
	
    WellWell::Core::hooks('run', 'cart', 'add', 'main', $itemref);

	if ($itemref->{error}) {
		# one of the hooks denied the item
		if ($itemref->{log_error}) {
			::logError('Adding item %s was denied: %s', $sku, $itemref->{error});
		}
		Vend::Tags->error({name => $sku, set => $itemref->{error}, overwrite => 1});
		return;
	}
	
	# verify that number of items doesn't go out of bounds
	if ($Vend::Cfg->{OrderLineLimit} && @$Vend::Items >= $Vend::Cfg->{OrderLineLimit}) {
		::logError('Limit %s for number of items in the cart exceeded.',
				   $Vend::Cfg->{OrderLineLimit});
		return;
	}
	
    push(@$Vend::Items, $itemref);

    return $itemref;
}

sub cart_refresh {
	my ($cart, $new_cart, $itemref, $quantity);

	$cart = $Vend::Items;
	$new_cart = [];
	
	return 1 unless defined $CGI::values{"quantity0"};

	foreach my $i (0 .. $#$cart) {
		my $modref = {};
		
		$itemref = $cart->[$i];
		$quantity = $CGI::values{"quantity$i"};

		# trim quantity
		$quantity =~ s/^\s+//;
		$quantity =~ s/\s+$//;
		
		if (defined $quantity) {
			if ($quantity =~ /^(\d+)$/ && $quantity != $itemref->{quantity}) {
				if ($quantity == 0) {
					WellWell::Core::hooks('run', 'cart', 'delete', 'main', $itemref);

					if ($itemref->{error}) {
						if ($itemref->{log_error}) {
							::logError('Removal of item %s was denied: %s', $itemref->{code}, $itemref->{error});
						}
						Vend::Tags->error({name => $itemref->{code}, set => $itemref->{error}, overwrite => 1});
						$quantity = $itemref->{quantity};
					}
					else {
						# deleting the item by omission
						next;
					}
				}
				$modref->{quantity} = $quantity;
			}
		}

		# checking whether any modifier changed
		for (@{$Vend::Cfg->{UseModifier}}) {
			if (exists $CGI::values{"$_$i"}
			   && $CGI::values{"$_$i"} ne $itemref->{$_}) {
				$modref->{$_} = $CGI::values{"$_$i"};
			}
		}

		if (keys %$modref) {
		    WellWell::Core::hooks('run', 'cart', 'modify', 'main', $itemref, $modref);

			if ($itemref->{error}) {
				if ($itemref->{log_error}) {
					::logError('Modification of item %s was denied: %s', $itemref->{code}, $itemref->{error});
				}
				Vend::Tags->error({name => $itemref->{code}, set => $itemref->{error}, overwrite => 1});
				%$modref = ();
			}
			
			for (keys %$modref) {
				$itemref->{$_} = $modref->{$_};
			}
		}
		
		push (@$new_cart, $itemref);
	}

	@$cart = @$new_cart;
}

sub cart_refresh_form_action {
	# check for additional items
	if ($CGI::values{mv_order_item}) {
		my $opt = {};

		for (@{$Vend::Cfg->{UseModifier}}) {
			if (exists $CGI::values{"mv_order_$_"}) {
				$opt->{$_} = $CGI::values{"mv_order_$_"};
			}
		}
		
		cart_add($CGI::values{mv_order_item}, $CGI::values{mv_order_quantity}, $opt);
	}
	else {
		cart_refresh();
	}
	
	if ($CGI::values{mv_nextpage} eq $Vend::Cfg->{ProcessPage}) {
		# skip virtual pages for determing shopping cart page
		delete $CGI::values{mv_nextpage};
	}
	
	unless ($CGI::values{mv_nextpage}) {
		$CGI::values{mv_nextpage} = $CGI::values{mv_orderpage}
			|| find_special_page('order');
	}

	return 1;
}

1;