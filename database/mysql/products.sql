-- DROP TABLE products;

CREATE TABLE `products`
(
  `sku` varchar(32) NOT NULL,
  `name` varchar(255) NOT NULL,
  `manufacturer` varchar(255),
  `short_description` text,
  `long_description` text,
  `price` decimal(11,2) NOT NULL DEFAULT 0,
  PRIMARY KEY (`sku`)
 ); 