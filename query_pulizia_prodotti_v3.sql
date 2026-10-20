-- =====================================================================================================
-- Pulizia prodotti disattivati e senza stock (v3).      FAI UN BACKUP DEL DATABASE PRIMA.
-- Esegui da un client MySQL/MariaDB (phpMyAdmin va bene).  Prefisso tabelle: ps_  (sostituiscilo se diverso).
--
-- Un prodotto viene eliminato solo se TUTTE queste condizioni sono vere:
--   * disattivato (in ogni negozio, se multishop);
--   * non modificato da almeno @giorni_minimi giorni;
--   * nessuna riga di stock (base o combinazione) con quantita' > 0;
--   * mai presente in un ordine (order_detail) e non usato come componente di un pack.
-- Per ogni esecuzione ne elimina al massimo @max_prodotti: se sono di piu', rilancia lo script.
-- Questa query fa le stesse pulizie di Product::delete() di PrestaShop. I file in img/p li elimina il modulo
-- (task "Immagini prodotto inutilizzate").
-- =====================================================================================================

SET @giorni_minimi = 30;      -- 0 = nessun controllo sulla data di ultima modifica
SET @max_prodotti  = 1000;    -- limite per esecuzione (transazioni piu' brevi, meno blocchi sul negozio)

START TRANSACTION;

DROP TEMPORARY TABLE IF EXISTS tmp_del;
CREATE TEMPORARY TABLE tmp_del (id_product INT UNSIGNED NOT NULL PRIMARY KEY);

SET @sql = 'INSERT INTO tmp_del (id_product)
SELECT p.id_product
FROM ps_product p
WHERE p.active = 0                                                        -- [FILTRO ATTIVI]
  AND NOT EXISTS (SELECT 1 FROM ps_product_shop s WHERE s.id_product = p.id_product AND s.active = 1)  -- [FILTRO ATTIVI]
  AND p.date_upd < NOW() - INTERVAL ? DAY
  AND NOT EXISTS (SELECT 1 FROM ps_stock_available sa WHERE sa.id_product = p.id_product AND sa.quantity > 0)
  AND NOT EXISTS (SELECT 1 FROM ps_order_detail od WHERE od.product_id = p.id_product)
  AND NOT EXISTS (SELECT 1 FROM ps_pack k WHERE k.id_product_item = p.id_product)
ORDER BY p.id_product
LIMIT ?';
PREPARE stmt FROM @sql;
EXECUTE stmt USING @giorni_minimi, @max_prodotti;
DEALLOCATE PREPARE stmt;

-- CONTROLLO: se il numero non ti torna, esegui ROLLBACK; invece del COMMIT finale.
SELECT COUNT(*) AS prodotti_da_eliminare, MIN(id_product) AS primo_id, MAX(id_product) AS ultimo_id FROM tmp_del;

-- ---- combinazioni
DELETE pac FROM ps_product_attribute_combination pac JOIN ps_product_attribute pa ON pa.id_product_attribute = pac.id_product_attribute JOIN tmp_del t ON t.id_product = pa.id_product;
DELETE pai FROM ps_product_attribute_image pai JOIN ps_product_attribute pa ON pa.id_product_attribute = pai.id_product_attribute JOIN tmp_del t ON t.id_product = pa.id_product;
DELETE pas FROM ps_product_attribute_shop pas JOIN ps_product_attribute pa ON pa.id_product_attribute = pas.id_product_attribute JOIN tmp_del t ON t.id_product = pa.id_product;
DELETE pa  FROM ps_product_attribute pa JOIN tmp_del t ON t.id_product = pa.id_product;

-- ---- immagini (record; i file li elimina il modulo)
DELETE il FROM ps_image_lang il JOIN ps_image i ON i.id_image = il.id_image JOIN tmp_del t ON t.id_product = i.id_product;
DELETE x  FROM ps_image_shop x JOIN tmp_del t ON t.id_product = x.id_product;
DELETE x  FROM ps_image x JOIN tmp_del t ON t.id_product = x.id_product;

-- ---- caratteristiche (anche i valori personalizzati, che appartengono a un solo prodotto)
DELETE fvl FROM ps_feature_value_lang fvl JOIN ps_feature_value fv ON fv.id_feature_value = fvl.id_feature_value JOIN ps_feature_product fp ON fp.id_feature_value = fv.id_feature_value JOIN tmp_del t ON t.id_product = fp.id_product WHERE fv.custom = 1;
DELETE fv  FROM ps_feature_value fv JOIN ps_feature_product fp ON fp.id_feature_value = fv.id_feature_value JOIN tmp_del t ON t.id_product = fp.id_product WHERE fv.custom = 1;
DELETE x FROM ps_feature_product x JOIN tmp_del t ON t.id_product = x.id_product;

-- ---- carrelli, personalizzazioni
DELETE cd  FROM ps_customized_data cd JOIN ps_customization cu ON cu.id_customization = cd.id_customization JOIN tmp_del t ON t.id_product = cu.id_product;
DELETE x   FROM ps_customization x JOIN tmp_del t ON t.id_product = x.id_product;
DELETE cfl FROM ps_customization_field_lang cfl JOIN ps_customization_field cf ON cf.id_customization_field = cfl.id_customization_field JOIN tmp_del t ON t.id_product = cf.id_product;
DELETE x   FROM ps_customization_field x JOIN tmp_del t ON t.id_product = x.id_product;
DELETE x   FROM ps_cart_product x JOIN tmp_del t ON t.id_product = x.id_product;

-- ---- stock, prezzi, sconti
DELETE x FROM ps_stock_available x JOIN tmp_del t ON t.id_product = x.id_product;
DELETE x FROM ps_stock x JOIN tmp_del t ON t.id_product = x.id_product;
DELETE x FROM ps_specific_price x JOIN tmp_del t ON t.id_product = x.id_product;
DELETE x FROM ps_specific_price_priority x JOIN tmp_del t ON t.id_product = x.id_product;
DELETE x FROM ps_product_group_reduction_cache x JOIN tmp_del t ON t.id_product = x.id_product;

-- ---- altri collegamenti del prodotto
DELETE x FROM ps_category_product x JOIN tmp_del t ON t.id_product = x.id_product;
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

-- ---- altri prodotti che reindirizzavano a uno di quelli eliminati
UPDATE ps_product p JOIN tmp_del t ON t.id_product = p.id_type_redirected SET p.redirect_type = '404', p.id_type_redirected = 0 WHERE p.redirect_type IN ('301-product', '302-product');
UPDATE ps_product_shop p JOIN tmp_del t ON t.id_product = p.id_type_redirected SET p.redirect_type = '404', p.id_type_redirected = 0 WHERE p.redirect_type IN ('301-product', '302-product');

-- ---- il prodotto
DELETE x FROM ps_product_lang x JOIN tmp_del t ON t.id_product = x.id_product;
DELETE x FROM ps_product_shop x JOIN tmp_del t ON t.id_product = x.id_product;
DELETE x FROM ps_product x JOIN tmp_del t ON t.id_product = x.id_product;

-- ---- Tabelle di moduli opzionali: decommenta solo quelle che esistono nel tuo database.
-- DELETE x FROM ps_product_comment x JOIN tmp_del t ON t.id_product = x.id_product;
-- DELETE x FROM ps_wishlist_product x JOIN tmp_del t ON t.id_product = x.id_product;
-- DELETE x FROM ps_layered_price_index x JOIN tmp_del t ON t.id_product = x.id_product;
-- DELETE x FROM ps_layered_product_attribute x JOIN tmp_del t ON t.id_product = x.id_product;
-- Parole di ricerca rimaste senza prodotti (lenta su cataloghi grandi):
-- DELETE FROM ps_search_word WHERE id_word NOT IN (SELECT DISTINCT id_word FROM ps_search_index);

COMMIT;
DROP TEMPORARY TABLE tmp_del;
