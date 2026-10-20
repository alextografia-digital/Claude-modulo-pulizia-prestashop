-- Pulizia prodotti senza stock (v2). FAI UN BACKUP DEL DATABASE PRIMA.
-- Cambiamenti rispetto alla v1:
--  * solo prodotti DISATTIVATI (p.active = 0): per includere anche gli attivi rimuovi la riga marcata [FILTRO ATTIVI];
--  * stock: un prodotto e' candidato solo se NESSUNA riga di stock_available (base o combinazione) e' > 0;
--  * puliti anche cart_product, customization/customized_data e ps_stock (magazzino avanzato);
--  * protetti anche i prodotti usati come componente di un pack (come prima) e quelli presenti in ordini.
-- Se il prefisso non e' ps_, sostituiscilo ovunque. Tabelle di moduli (wishlist, recensioni...) sono in fondo, commentate.

START TRANSACTION;

DROP TEMPORARY TABLE IF EXISTS tmp_del;
CREATE TEMPORARY TABLE tmp_del (id_product INT UNSIGNED NOT NULL PRIMARY KEY)
AS
SELECT sa.id_product
FROM ps_stock_available sa
JOIN ps_product p ON p.id_product = sa.id_product
WHERE p.active = 0                                              -- [FILTRO ATTIVI]
  AND NOT EXISTS (SELECT 1 FROM ps_product_shop ps WHERE ps.id_product = p.id_product AND ps.active = 1)  -- [FILTRO ATTIVI] multishop
GROUP BY sa.id_product
HAVING MAX(sa.quantity) <= 0;

DELETE FROM tmp_del WHERE id_product IN (SELECT product_id FROM ps_order_detail);
DELETE FROM tmp_del WHERE id_product IN (SELECT id_product_item FROM ps_pack);

-- controllo: quanti prodotti verranno eliminati (annulla con ROLLBACK se il numero non ti torna)
SELECT COUNT(*) AS prodotti_da_eliminare FROM tmp_del;

-- combinazioni
DELETE pac FROM ps_product_attribute_combination pac JOIN ps_product_attribute pa ON pa.id_product_attribute = pac.id_product_attribute JOIN tmp_del t ON t.id_product = pa.id_product;
DELETE pai FROM ps_product_attribute_image pai JOIN ps_product_attribute pa ON pa.id_product_attribute = pai.id_product_attribute JOIN tmp_del t ON t.id_product = pa.id_product;
DELETE pas FROM ps_product_attribute_shop pas JOIN ps_product_attribute pa ON pa.id_product_attribute = pas.id_product_attribute JOIN tmp_del t ON t.id_product = pa.id_product;
DELETE pa  FROM ps_product_attribute pa JOIN tmp_del t ON t.id_product = pa.id_product;

-- immagini (i file in img/p li elimina poi il modulo "Immagini prodotto inutilizzate")
DELETE il FROM ps_image_lang il JOIN ps_image i ON i.id_image = il.id_image JOIN tmp_del t ON t.id_product = i.id_product;
DELETE x FROM ps_image_shop x JOIN tmp_del t ON t.id_product = x.id_product;
DELETE x FROM ps_image x JOIN tmp_del t ON t.id_product = x.id_product;

-- carrelli e personalizzazioni
DELETE cd FROM ps_customized_data cd JOIN ps_customization cu ON cu.id_customization = cd.id_customization JOIN tmp_del t ON t.id_product = cu.id_product;
DELETE x FROM ps_customization x JOIN tmp_del t ON t.id_product = x.id_product;
DELETE x FROM ps_cart_product x JOIN tmp_del t ON t.id_product = x.id_product;

-- dati del prodotto
DELETE x FROM ps_category_product x JOIN tmp_del t ON t.id_product = x.id_product;
DELETE x FROM ps_stock_available x JOIN tmp_del t ON t.id_product = x.id_product;
DELETE x FROM ps_stock x JOIN tmp_del t ON t.id_product = x.id_product;
DELETE x FROM ps_specific_price x JOIN tmp_del t ON t.id_product = x.id_product;
DELETE x FROM ps_feature_product x JOIN tmp_del t ON t.id_product = x.id_product;
DELETE x FROM ps_product_tag x JOIN tmp_del t ON t.id_product = x.id_product;
DELETE x FROM ps_product_supplier x JOIN tmp_del t ON t.id_product = x.id_product;
DELETE x FROM ps_product_carrier x JOIN tmp_del t ON t.id_product = x.id_product;
DELETE x FROM ps_product_attachment x JOIN tmp_del t ON t.id_product = x.id_product;
DELETE x FROM ps_product_country_tax x JOIN tmp_del t ON t.id_product = x.id_product;
DELETE x FROM ps_product_sale x JOIN tmp_del t ON t.id_product = x.id_product;
DELETE x FROM ps_product_download x JOIN tmp_del t ON t.id_product = x.id_product;
DELETE x FROM ps_accessory x JOIN tmp_del t ON t.id_product = x.id_product_1;
DELETE x FROM ps_accessory x JOIN tmp_del t ON t.id_product = x.id_product_2;
DELETE x FROM ps_pack x JOIN tmp_del t ON t.id_product = x.id_product_pack;
DELETE x FROM ps_search_index x JOIN tmp_del t ON t.id_product = x.id_product;
DELETE x FROM ps_product_lang x JOIN tmp_del t ON t.id_product = x.id_product;
DELETE x FROM ps_product_shop x JOIN tmp_del t ON t.id_product = x.id_product;
DELETE x FROM ps_product x JOIN tmp_del t ON t.id_product = x.id_product;

-- Tabelle di moduli opzionali: decommenta solo quelle che esistono nel tuo database.
-- DELETE x FROM ps_product_comment x JOIN tmp_del t ON t.id_product = x.id_product;
-- DELETE x FROM ps_wishlist_product x JOIN tmp_del t ON t.id_product = x.id_product;
-- DELETE x FROM ps_layered_price_index x JOIN tmp_del t ON t.id_product = x.id_product;
-- DELETE x FROM ps_layered_product_attribute x JOIN tmp_del t ON t.id_product = x.id_product;

COMMIT;
DROP TEMPORARY TABLE tmp_del;
