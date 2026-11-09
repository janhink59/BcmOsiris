/* =============================================================================
 * Verze: 2026-11-09 14:15
 * Soubor: fillup_meta_link_def.sql
 * Účel:   1. Zajistí v tabulce meta_class existenci bázové třídy 'asset' a všech
 *            17 odvozených STI logických tříd aktiv (asset_district, asset_city,
 *            asset_site, asset_building, asset_room, asset_physical, asset_host,
 *            asset_cabling, asset_document, asset_media, asset_data,
 *            asset_software, asset_application, asset_service, asset_interface,
 *            asset_personnel, asset_supplier).
 *         2. Idempotentně naplní tabulku meta_link_def (object_owner = 0x00,
 *            jazyk 'cs', záznamy 'A' a symetrické 'L') všemi předdefinovanými
 *            vztahy prostorové hierarchie, uložení dat, podpory služeb
 *            a aplikací, přenosu chyb a výpadků, personálu, dodavatelů,
 *            hrozeb, dopadů a protiopatření (seřazeno podle link_code).
 * Vazby:  - Vyžaduje tabulky meta_object, meta_class, meta_link_def a funkci
 *           dbo.f_generate_original.
 * ============================================================================= */

SET NOCOUNT ON;
GO

DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);
DECLARE @stg_asset uuid = dbo.f_generate_original('meta_object', @sys_owner, 'T', 'asset');
DECLARE @cls_asset uuid = dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), 'asset', '');
DECLARE @cls_physical uuid = dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), 'asset_physical', '');

-- 1. Zajištění existence fyzického objektu 'asset' v meta_object a bázové třídy 'asset' v meta_class
IF NOT EXISTS (SELECT 1 FROM meta_object WHERE original = @stg_asset AND object_owner = @sys_owner AND record_type = 'A')
BEGIN
	INSERT INTO meta_object (
		uuid, object_owner, original, record_type, approval_status, [language],
		object_type, builtin_code, caption, caption_plural, system_role
	) VALUES (
		@stg_asset, @sys_owner, @stg_asset, 'A', 'A', 'cs',
		'T', 'asset', 'Aktivum', 'Evidence aktiv', 'U'
	);
END

IF NOT EXISTS (SELECT 1 FROM meta_class WHERE original = @cls_asset AND object_owner = @sys_owner AND record_type = 'A')
BEGIN
	INSERT INTO meta_class (
		uuid, object_owner, original, record_type, approval_status, [language],
		class_name, storage_object, ancestor_class, sort_code, caption, caption_plural, is_final, is_protected
	) VALUES (
		@cls_asset, @sys_owner, @cls_asset, 'A', 'A', 'cs',
		'asset', @stg_asset, NULL, '010', 'Aktivum', 'Evidence aktiv', 0, 1
	);
END

-- 2. Registrace specializovaných STI tříd aktiv v meta_class (dědí z třídy 'asset', resp. 'asset_host' z 'asset_physical')
DECLARE @sti_classes TABLE (
	class_name varchar(80) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
	ancestor_code varchar(80) COLLATE DATABASE_DEFAULT NOT NULL,
	sort_code varchar(20) NOT NULL,
	caption varchar(200) NOT NULL,
	caption_plural varchar(200) NOT NULL
);

INSERT INTO @sti_classes (class_name, ancestor_code, sort_code, caption, caption_plural) VALUES
('asset_application','asset','130','Aplikace (instalovaná)','Aplikace (instalované)'),
('asset_building','asset','040','Budova','Budovy'),
('asset_cabling','asset','080','Kabeláž a rozvody','Kabeláž a rozvody'),
('asset_city','asset','020','Město / obec','Města a obce'),
('asset_data','asset','110','Datové aktivum','Datová aktiva'),
('asset_district','asset','010','Okres / region','Okresy a regiony'),
('asset_document','asset','090','Dokument','Dokumenty'),
('asset_host','asset_physical','070','Hostitelský počítač / server','Hostitelské počítače a servery'),
('asset_interface','asset','150','Služba typu Interface','Služby typu Interface (Internet, hlas, video)'),
('asset_media','asset','100','Médium / nosič dat','Média a nosiče dat'),
('asset_personnel','asset','160','Personál / klíčová role','Personál a klíčové role'),
('asset_physical','asset','060','Fyzické aktivum (HW / zařízení)','Fyzická aktiva a hardware'),
('asset_room','asset','050','Místnost','Místnosti a sály'),
('asset_service','asset','140','Služba','Služby (interní a zákaznické)'),
('asset_site','asset','030','Lokalita / areál','Lokality a areály'),
('asset_software','asset','120','Software (vyvíjený / pořizovaný)','Software (vyvíjený a pořizovaný)'),
('asset_supplier','asset','170','Dodavatel / partner','Dodavatelé a externí partneři');

INSERT INTO meta_class (
	uuid, object_owner, original, record_type, approval_status, [language],
	class_name, storage_object, ancestor_class, sort_code, caption, caption_plural, is_final, is_protected
)
SELECT
	x.orig, @sys_owner, x.orig, 'A', 'A', 'cs',
	s.class_name, @stg_asset, p.anc_orig, s.sort_code, s.caption, s.caption_plural, 0, 1
FROM @sti_classes s
CROSS APPLY (
	SELECT dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), s.class_name, '') AS orig
) x
CROSS APPLY (
	SELECT dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), s.ancestor_code, '') AS anc_orig
) p
WHERE NOT EXISTS (
	SELECT 1 FROM meta_class mc
	WHERE mc.original = x.orig AND mc.object_owner = @sys_owner AND mc.record_type = 'A'
);

-- 3. Definice předdefinovaných typů vazeb v meta_link_def (seřazeno abecedně podle link_code)
DECLARE @links_cs TABLE (
	link_code varchar(80) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
	from_class_code varchar(80) COLLATE DATABASE_DEFAULT NOT NULL,
	to_class_code varchar(80) COLLATE DATABASE_DEFAULT NOT NULL,
	is_multiple bit NOT NULL,
	is_mandatory bit NOT NULL,
	leaf_only bit NOT NULL,
	link_weight_enabled bit NOT NULL,
	caption_forward varchar(200) NOT NULL,
	caption_backward varchar(200) NOT NULL,
	description varchar(max) NOT NULL,
	helptext varchar(max) NOT NULL
);

INSERT INTO @links_cs (
	link_code, from_class_code, to_class_code,
	is_multiple, is_mandatory, leaf_only, link_weight_enabled,
	caption_forward, caption_backward, description, helptext
) VALUES
('app_instance_of_sw','asset_application','asset_software',1,0,1,1,'Je instalací softwaru (přebírá SW chyby)','Je nasazen jako instalovaná aplikace','Vazba instalované aplikace na vyvíjený nebo nakupovaný softwarový produkt. Přenos softwarových chyb a zranitelností do aplikace.','Vyberte softwarové produkty, ze kterých se instalovaná aplikace skládá.'),
('app_requires_data','asset_application','asset_data',1,0,1,1,'Vyžaduje a zpracovává datové aktivum','Je využíváno aplikací (přenáší výpadky, chyby i prozrazení)','Vazba M:N mezi instalovanou aplikací a datovými aktivy. Nedostupnost, nekonzistence/chyby i prozrazení dat se přenášejí na aplikaci a navazující služby.','Určete datová aktiva, která aplikace ke svému běhu čte nebo zapisuje.'),
('app_requires_interface','asset_application','asset_interface',1,0,1,1,'Vyžaduje komunikační rozhraní (interface)','Zajišťuje komunikaci pro aplikaci','Závislost aplikace na externím či interním rozhraní (internet, API, komunikační linka).','Vyberte rozhraní, bez nichž aplikace nemůže plnohodnotně komunikovat.'),
('app_requires_personnel','asset_application','asset_personnel',1,0,1,1,'Vyžaduje personál (správa a obsluha)','Spravuje / obsluhuje aplikaci (zdroj lidských chyb)','Závislost aplikace na klíčovém personálu (administrátoři, garanti). Přenáší riziko nedostupnosti personálu a lidských chyb.','Přiřaďte klíčové role nebo pracovníky zajišťující provoz aplikace.'),
('app_runs_on_host','asset_application','asset_host',1,1,1,1,'Běží na hostitelském počítači / serveru','Hostuje instalovanou aplikaci (přenáší HW výpadky a chyby)','Provozní umístění instalované aplikace na hostitelském počítači nebo serveru. Výpadek nebo HW chyba serveru přímo postihuje aplikaci.','Vyberte jeden nebo více hostitelských počítačů (serverů), na kterých aplikace běží.'),
('asset_Additional_class','asset','asset_class',1,0,1,0,'Patří do vedlejší třídy aktiv','Obsahuje aktivum (sekundární zařazení)','Možnost zařadit aktivum kromě primární třídy (primary_asset_class) i do dalších koncových tříd aktiv v katalogu.','Volitelné přiřazení aktiva do dalších kategorií katalogu tříd aktiv.'),
('asset_maintained_by_supplier','asset','asset_supplier',1,0,1,0,'Je dodáváno / servisováno dodavatelem','Dodává / servisuje aktivum','Vazba obecného aktiva (HW, SW, technologie) na externího dodavatele nebo servisního partnera.','Vyberte dodavatele zajišťujícího dodávku, záruku nebo servis aktiva.'),
('building_in_site','asset_building','asset_site',0,0,1,0,'Nachází se v lokalitě / areálu','Obsahuje budovu','Prostorové zařazení budovy do lokality (jsou-li lokality v organizaci definovány).','Pokud evidujete areály či lokality, vyberte lokalitu, v níž budova leží.'),
('cabling_connects_room','asset_cabling','asset_room',1,0,1,0,'Propojuje místnost','Je propojena kabeláží','Seznam místností v budově, které daná kabeláž nebo rozvod napájí či datově propojuje.','Vyberte místnosti obsluhované touto kabeláží.'),
('cabling_in_building','asset_cabling','asset_building',0,1,1,0,'Je instalována v budově','Obsahuje kabeláž a rozvody','Povinné prostorové umístění kabeláže do konkrétní budovy. Poškození budovy se přenáší na kabeláž.','Každá kabeláž musí být přiřazena právě do jedné budovy.'),
('city_in_district','asset_city','asset_district',0,0,1,0,'Leží v okrese / regionu','Obsahuje město / obec','Prostorové zařazení města do okresu (jsou-li okresy v organizaci definovány).','Pokud evidujete okresy, vyberte nadřízený okres.'),
('countermeasure_applies_to_asset_class','asset_class','countermeasure',1,0,1,0,'Doporučené protiopatření pro třídu aktiv','Je aplikovatelné na třídu aktiv (dědí se po stromu)','Katalogová vazba určující, která protiopatření jsou relevantní pro danou třídu aktiv a její podřízené třídy.','Přiřaďte protiopatření, která se mají nabízet pro aktiva této třídy.'),
('countermeasure_mitigates_scenario','scenario','countermeasure',1,0,1,1,'Je ošetřen protiopatřením','Snižuje riziko scénáře (reduction_factor / risk_factor)','Metodická vazba mezi rizikovým scénářem a protiopatřeními, která snižují jeho zbytkové riziko nebo stanovují práh rizika při neimplementaci.','Vyberte protiopatření působící proti tomuto rizikovému scénáři.'),
('countermeasure_mitigates_threat','threat','countermeasure',1,0,1,1,'Je potlačována protiopatřením','Působí proti hrozbě','Metodická vazba mezi katalogovou hrozbou a preventivními či detekčními protiopatřeními.','Vyberte protiopatření, která snižují působení této hrozby.'),
('countermeasure_requires_personnel','countermeasure','asset_personnel',1,0,1,0,'Vyžaduje personál k realizaci / provozu','Zajišťuje provoz protiopatření','Lidské zdroje a role nezbytné k tomu, aby bezpečnostní opatření (např. ostraha, dohled SOC, revize) reálně fungovalo.','Určete personál potřebný pro chod tohoto opatření.'),
('data_evaluated_by_impact','asset_data','impact',1,0,1,1,'Má hodnocen dopad v oblasti (prozrazení / chyby / ztráta)','Je oblastí dopadu pro datové aktivum','Hodnocení dopadů prozrazení dat, nekonzistence nebo chyb dat (od drobných chyb po ztrátu od poslední zálohy či úplnou likvidaci) do jednotlivých oblastí.','Ohodnoťte dopady kompromitace nebo ztráty tohoto datového aktiva.'),
('data_in_document','asset_data','asset_document',1,0,1,0,'Je zaznamenáno v dokumentu','Obsahuje datové aktivum','Uložení datového aktiva v listinném nebo řízeném elektronickém dokumentu.','Vyberte dokumenty, ve kterých se tato data nacházejí.'),
('data_on_host','asset_data','asset_host',1,0,1,1,'Je uloženo na hostitelském počítači / serveru','Ukládá datové aktivum (přenáší HW chyby a výpadky)','Fyzické nebo virtuální uložení databáze či souborů na hostitelském počítači. Selhání nebo kompromitace hosta přímo ohrožuje data.','Vyberte hostitelské počítače (servery), na kterých jsou data uložena.'),
('data_on_media','asset_data','asset_media',1,0,1,0,'Je uloženo / zálohováno na médiu','Nese datové aktivum (zálohu / archiv)','Uložení nebo zálohování datového aktiva na přenosném či trezorovém médiu.','Vyberte paměťová média, na nichž jsou uloženy kopie nebo zálohy těchto dat.'),
('data_on_physical','asset_data','asset_physical',1,0,1,0,'Je uloženo na fyzickém zařízení','Obsahuje datové aktivum','Uložení dat na specializovaném HW zařízení (diskové pole SAN/NAS, koncová stanice, technologický prvek).','Vyberte fyzická zařízení, na kterých se data nacházejí.'),
('document_in_room','asset_document','asset_room',0,1,1,0,'Je uložen v místnosti','Obsahuje dokument','Povinné prostorové umístění dokumentu do konkrétní místnosti (archivu, kanceláře).','Vyberte místnost, ve které je dokument trvale uložen.'),
('host_in_room','asset_host','asset_room',0,1,1,0,'Je umístěn v místnosti','Obsahuje hostitelský počítač / server','Povinné prostorové umístění hostitelského počítače / serveru právě v jedné místnosti (serverovně).','Každý hostitelský počítač musí být umístěn právě v jedné místnosti.'),
('host_uses_cabling','asset_host','asset_cabling',1,0,1,0,'Využívá kabeláž a rozvody','Propojuje / napájí hostitelský počítač','Závislost serveru na datové a napájecí kabeláži budovy.','Vyberte kabeláž zajišťující konektivitu a napájení tohoto hostitelského počítače.'),
('interface_provided_by_supplier','asset_interface','asset_supplier',1,0,1,1,'Zajišťuje dodavatel (poskytovatel služeb)','Poskytuje službu typu Interface (internet / hlas / video)','Vazba externího rozhraní (internetové přípojky, hlasové/video služby, datového okruhu) na dodavatele.','Vyberte dodavatele (operátora / poskytovatele), který toto rozhraní zajišťuje.'),
('media_in_room','asset_media','asset_room',0,1,1,0,'Je uloženo v místnosti','Obsahuje paměťové médium','Povinné prostorové umístění média (nosiče dat) do konkrétní místnosti nebo trezoru.','Vyberte místnost, ve které je paměťové médium uloženo.'),
('physical_in_room','asset_physical','asset_room',0,1,1,0,'Je umístěno v místnosti','Obsahuje fyzické aktivum','Povinné prostorové umístění každého fyzického aktiva právě v jedné místnosti.','Každé fyzické aktivum musí být umístěno právě v jedné místnosti.'),
('room_in_building','asset_room','asset_building',0,1,1,0,'Nachází se v budově','Obsahuje místnost','Povinné prostorové zařazení místnosti do budovy. Každá místnost musí patřit právě do jedné budovy.','Vyberte budovu, ve které se tato místnost nachází.'),
('scenario_causes_impact','scenario','impact',1,0,1,1,'Způsobuje dopad v oblasti','Je způsoben rizikovým scénářem','Určuje, které oblasti dopadů (finanční, pověst, obecné ohrožení, trestní odpovědnost, řízení firmy, zákony) daný scénář vyvolává.','Přiřaďte oblasti dopadů, které tento rizikový scénář ohrožuje.'),
('service_evaluated_by_impact','asset_service','impact',1,0,1,1,'Má hodnocen výpadek / degradaci v oblasti dopadu','Slouží k hodnocení dopadu výpadku služby','Hodnocení dopadů výpadku nebo degradace služby do jednotlivých oblastí (finanční, pověst, obecné ohrožení, trestní odpovědnost, řízení firmy, zákony).','Určete oblasti dopadů a míru závažnosti při výpadku nebo degradaci této služby.'),
('service_requires_app','asset_service','asset_application',1,0,1,1,'Vyžaduje aplikaci (je jí podporována)','Podporuje službu (přenáší na ni výpadky a chyby)','Klíčová vazba M:N mezi službou a podpůrnými aplikacemi. Výpadky aplikací i chyby/prozrazení jejich dat se přenášejí na službu.','Vyberte instalované aplikace, které jsou nezbytné pro poskytování této služby.'),
('service_requires_interface','asset_service','asset_interface',1,0,1,1,'Vyžaduje rozhraní (internet / hlas / video / ext. službu)','Zajišťuje přenos / rozhraní pro službu','Závislost služby na komunikačním rozhraní nebo jiné dříve definované službě (internet, hlasové či video spojení).','Vyberte služby typu Interface, které tato služba ke svému provozu potřebuje.'),
('service_requires_personnel','asset_service','asset_personnel',1,0,1,1,'Vyžaduje personál pro zajištění služby','Zajišťuje provoz a obsluhu služby','Závislost služby na klíčových pracovnících a rolích.','Přiřaďte personál nezbytný pro poskytování této služby.'),
('service_requires_service','asset_service','asset_service',1,0,1,1,'Vyžaduje podřízenou (interní) službu','Podporuje nadřazenou službu (přenáší výpadky)','Řetězení závislostí mezi interními podpůrnými službami a koncovými byznys službami.','Vyberte jiné interní služby, na kterých je tato služba závislá.'),
('site_in_city','asset_site','asset_city',0,0,1,0,'Nachází se ve městě / obci','Obsahuje lokalitu / areál','Prostorové zařazení lokality do města (jsou-li města v organizaci definována).','Pokud evidujete města, vyberte město, v němž se lokalita nachází.'),
('threat_applies_to_asset_class','asset_class','threat',1,0,1,0,'Je vystavena působení hrozby','Působí na třídu aktiv (dědí se po stromu)','Katalogová vazba určující, které hrozby působí na danou třídu aktiv a automaticky se dědí na podřízené třídy.','Přiřaďte hrozby relevantní pro tuto třídu aktiv.');

-- 4. Idempotentní UPDATE existujících hlavních záznamů v meta_link_def (record_type = 'A', language = 'cs')
UPDATE t
SET t.from_class = fc.orig,
	t.to_class = tc.orig,
	t.is_multiple = s.is_multiple,
	t.is_mandatory = s.is_mandatory,
	t.leaf_only = s.leaf_only,
	t.link_weight_enabled = s.link_weight_enabled,
	t.caption_forward = s.caption_forward,
	t.caption_backward = s.caption_backward,
	t.description = s.description,
	t.helptext = s.helptext,
	t.[language] = 'cs',
	t.date_modified = GETDATE()
FROM meta_link_def t
JOIN @links_cs s ON s.link_code = t.link_code
CROSS APPLY (SELECT dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), s.from_class_code, '') AS orig) fc
CROSS APPLY (SELECT dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), s.to_class_code, '') AS orig) tc
WHERE t.object_owner = @sys_owner
  AND t.record_type = 'A'
  AND t.who_modified = @sys_owner
  AND EXISTS (
	SELECT t.from_class, t.to_class, t.is_multiple, t.is_mandatory, t.leaf_only, t.link_weight_enabled, t.caption_forward, t.caption_backward, t.description, t.helptext
	EXCEPT
	SELECT fc.orig, tc.orig, s.is_multiple, s.is_mandatory, s.leaf_only, s.link_weight_enabled, s.caption_forward, s.caption_backward, s.description, s.helptext
  );

-- 5. Idempotentní INSERT chybějících hlavních záznamů v meta_link_def (record_type = 'A', language = 'cs')
INSERT INTO meta_link_def (
	uuid, object_owner, original, record_type, approval_status, [language],
	link_code, from_class, to_class,
	caption_forward, caption_backward, description, helptext,
	is_multiple, is_mandatory, leaf_only, link_weight_enabled,
	is_final, is_protected
)
SELECT
	x.orig, @sys_owner, x.orig, 'A', 'A', 'cs',
	s.link_code, fc.orig, tc.orig,
	s.caption_forward, s.caption_backward, s.description, s.helptext,
	s.is_multiple, s.is_mandatory, s.leaf_only, s.link_weight_enabled,
	1, 1
FROM @links_cs s
CROSS APPLY (SELECT dbo.f_generate_original('meta_link_def', @sys_owner, s.link_code, '') AS orig) x
CROSS APPLY (SELECT dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), s.from_class_code, '') AS orig) fc
CROSS APPLY (SELECT dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), s.to_class_code, '') AS orig) tc
WHERE NOT EXISTS (
	SELECT 1 FROM meta_link_def t
	WHERE t.original = x.orig AND t.object_owner = @sys_owner AND t.record_type = 'A'
);

-- 6. Idempotentní UPDATE a INSERT symetrických 'L' záznamů pro češtinu (language = 'cs')
UPDATE l
SET l.caption_forward = s.caption_forward,
	l.caption_backward = s.caption_backward,
	l.description = s.description,
	l.helptext = s.helptext,
	l.date_modified = GETDATE()
FROM meta_link_def l
JOIN meta_link_def a ON a.original = l.original AND a.object_owner = @sys_owner AND a.record_type = 'A'
JOIN @links_cs s ON s.link_code = a.link_code
WHERE l.object_owner = @sys_owner
  AND l.record_type = 'L'
  AND l.[language] = 'cs'
  AND l.who_modified = @sys_owner
  AND EXISTS (
	SELECT l.caption_forward, l.caption_backward, l.description, l.helptext
	EXCEPT
	SELECT s.caption_forward, s.caption_backward, s.description, s.helptext
  );

INSERT INTO meta_link_def (
	uuid, object_owner, original, record_type, approval_status, [language],
	link_code, from_class, to_class,
	caption_forward, caption_backward, description, helptext,
	is_multiple, is_mandatory, leaf_only, link_weight_enabled,
	is_final, is_protected
)
SELECT
	NEWID(), @sys_owner, a.original, 'L', 'A', 'cs',
	a.link_code, a.from_class, a.to_class,
	s.caption_forward, s.caption_backward, s.description, s.helptext,
	a.is_multiple, a.is_mandatory, a.leaf_only, a.link_weight_enabled,
	a.is_final, a.is_protected
FROM meta_link_def a
JOIN @links_cs s ON s.link_code = a.link_code
WHERE a.object_owner = @sys_owner
  AND a.record_type = 'A'
  AND a.removed = 0
  AND NOT EXISTS (
	SELECT 1 FROM meta_link_def l
	WHERE l.original = a.original AND l.object_owner = @sys_owner AND l.record_type = 'L' AND l.[language] = 'cs'
  );
GO