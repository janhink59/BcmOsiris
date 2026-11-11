/* =============================================================================
 * Verze: 2026-11-11 22:00
 * Soubor: fillup_meta_link_def.sql
 * Účel:   1. Zajistí v tabulce meta_class existenci bázové třídy 'asset', všech
 *            17 odvozených STI logických tříd aktiv, třídy 'organization_unit'
 *            a třídy 'link_diagram'.
 *         2. Idempotentně naplní tabulku meta_link_def (object_owner = 0x00,
 *            jazyk 'cs', záznamy 'A' a symetrické 'L') všemi předdefinovanými
 *            primárními ('P') i zpětnými ('R') vztahy, vnitrotřídními vztahy
 *            a exkluzivními stromovými vztahy parent_uuid (is_exclusive_parent = 1),
 *            seřazenými abecedně podle link_code.
 * Vazby:  - Vyžaduje tabulky meta_object, meta_class, meta_link_def a funkci
 *           dbo.f_generate_original.
 * ============================================================================= */

SET NOCOUNT ON;
GO

DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);
DECLARE @stg_asset uuid = dbo.f_generate_original('meta_object', @sys_owner, 'T', 'asset');
DECLARE @cls_asset uuid = dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), 'asset', '');
DECLARE @stg_diag uuid = dbo.f_generate_original('meta_object', @sys_owner, 'T', 'link_diagram');
DECLARE @cls_diag uuid = dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), 'link_diagram', '');

-- 1. Zajištění existence fyzického objektu 'asset' a 'link_diagram' v meta_object a bázových tříd v meta_class
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

IF NOT EXISTS (SELECT 1 FROM meta_object WHERE original = @stg_diag AND object_owner = @sys_owner AND record_type = 'A')
BEGIN
	INSERT INTO meta_object (
		uuid, object_owner, original, record_type, approval_status, [language],
		object_type, builtin_code, caption, caption_plural, system_role
	) VALUES (
		@stg_diag, @sys_owner, @stg_diag, 'A', 'A', 'cs',
		'T', 'link_diagram', 'Schéma sítě vztahů', 'Schémata sítí vztahů', 'U'
	);
END

IF NOT EXISTS (SELECT 1 FROM meta_class WHERE original = @cls_diag AND object_owner = @sys_owner AND record_type = 'A')
BEGIN
	INSERT INTO meta_class (
		uuid, object_owner, original, record_type, approval_status, [language],
		class_name, storage_object, ancestor_class, sort_code, caption, caption_plural, is_final, is_protected
	) VALUES (
		@cls_diag, @sys_owner, @cls_diag, 'A', 'A', 'cs',
		'link_diagram', @stg_diag, NULL, '180', 'Schéma sítě vztahů', 'Schémata sítí vztahů', 0, 1
	);
END

-- 2. Registrace specializovaných STI tříd aktiv v meta_class
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

-- 3. Definice předdefinovaných typů vztahů v meta_link_def (seřazeno abecedně podle link_code)
DECLARE @links_cs TABLE (
	link_code varchar(80) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
	reverse_code varchar(80) COLLATE DATABASE_DEFAULT NULL,
	direction_type varchar(1) NOT NULL,
	is_exclusive_parent bit NOT NULL,
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
	link_code, reverse_code, direction_type, is_exclusive_parent,
	from_class_code, to_class_code,
	is_multiple, is_mandatory, leaf_only, link_weight_enabled,
	caption_forward, caption_backward, description, helptext
) VALUES
('app_instance_of_sw','sw_deployed_as_app','P',0,'asset_application','asset_software',1,0,1,1,'Je instalací softwaru (přebírá SW chyby)','Je nasazen jako instalovaná aplikace','Vazba instalované aplikace na vyvíjený nebo nakupovaný softwarový produkt. Přenos softwarových chyb a zranitelností do aplikace.','Vyberte softwarové produkty, ze kterých se instalovaná aplikace skládá.'),
('app_requires_app','app_supports_app','R',0,'asset_application','asset_application',1,0,1,1,'Vyžaduje k provozu jinou aplikaci','Podporuje nadřazenou aplikaci','Zpětný vztah závislosti mezi instalovanými aplikacemi (hlídá se acykličnost přes f_resolve_link_diagram).','Vyberte podřízené aplikace, které tato aplikace ke svému provozu vyžaduje.'),
('app_requires_data','data_used_by_app','P',0,'asset_application','asset_data',1,0,1,1,'Vyžaduje a zpracovává datové aktivum','Je využíváno aplikací (přenáší výpadky, chyby i prozrazení)','Vazba M:N mezi instalovanou aplikací a datovými aktivy. Nedostupnost, nekonzistence/chyby i prozrazení dat se přenášejí na aplikaci a navazující služby.','Určete datová aktiva, která aplikace ke svému běhu čte nebo zapisuje.'),
('app_requires_interface','interface_supports_app','P',0,'asset_application','asset_interface',1,0,1,1,'Vyžaduje komunikační rozhraní (interface)','Zajišťuje komunikaci pro aplikaci','Závislost aplikace na externím či interním rozhraní (internet, API, komunikační linka).','Vyberte rozhraní, bez nichž aplikace nemůže plnohodnotně komunikovat.'),
('app_requires_personnel','personnel_operates_app','P',0,'asset_application','asset_personnel',1,0,1,1,'Vyžaduje personál (správa a obsluha)','Spravuje / obsluhuje aplikaci (zdroj lidských chyb)','Závislost aplikace na klíčovém personálu (administrátoři, garanti). Přenáší riziko nedostupnosti personálu a lidských chyb.','Přiřaďte klíčové role nebo pracovníky zajišťující provoz aplikace.'),
('app_runs_on_host','host_runs_app','P',0,'asset_application','asset_host',1,1,1,1,'Běží na hostitelském počítači / serveru','Hostuje instalovanou aplikaci (přenáší HW výpadky a chyby)','Provozní umístění instalované aplikace na jednom nebo více hostitelských počítačích (serverech). Výpadek nebo HW chyba serveru přímo postihuje aplikaci.','Vyberte jeden nebo více hostitelských počítačů (serverů), na kterých aplikace běží.'),
('app_supports_app','app_requires_app','P',0,'asset_application','asset_application',1,0,1,1,'Podporuje jinou aplikaci (přenáší chyby a výpadky)','Vyžaduje k provozu aplikaci','Vnitrotřídní orientovaný vztah mezi instalovanými aplikacemi (s kontrolou proti zacyklení).','Vyberte navazující aplikace, které jsou touto aplikací podporovány.'),
('app_supports_service','service_requires_app','R',0,'asset_application','asset_service',1,0,1,1,'Podporuje službu (přenáší na ni výpadky a chyby)','Vyžaduje aplikaci (je jí podporována)','Zpětný vztah od instalované aplikace ke službám, které aplikace podporuje.','Přehled služeb závislých na této instalované aplikaci.'),
('asset_additional_class','asset_class_has_asset','P',0,'asset','asset_class',1,0,1,0,'Patří do vedlejší třídy aktiv','Obsahuje aktivum (sekundární zařazení)','Možnost zařadit aktivum kromě primární třídy (primary_asset_class) i do dalších koncových tříd aktiv v katalogu.','Volitelné přiřazení aktiva do dalších kategorií katalogu tříd aktiv.'),
('asset_class_exposed_to_threat','threat_applies_to_asset_class','R',0,'threat','asset_class',1,0,1,0,'Působí na třídu aktiv (dědí se po stromu)','Je vystavena působení hrozby','Zpětný vztah od katalogové hrozby ke třídám aktiv, na které hrozba působí.','Třídy aktiv ohrožované touto hrozbou.'),
('asset_class_has_asset','asset_additional_class','R',0,'asset_class','asset',1,0,1,0,'Obsahuje aktivum (sekundární zařazení)','Patří do vedlejší třídy aktiv','Zpětný vztah od třídy aktiv k sekundárně zařazeným aktivům.','Aktiva sekundárně zařazená do této třídy.'),
('asset_class_uses_countermeasure','countermeasure_applies_to_asset_class','R',0,'countermeasure','asset_class',1,0,1,0,'Je aplikovatelné na třídu aktiv (dědí se po stromu)','Doporučené protiopatření pro třídu aktiv','Zpětný vztah od protiopatření ke třídám aktiv, pro něž je opatření doporučeno.','Třídy aktiv, na které se toto protiopatření vztahuje.'),
('asset_maintained_by_supplier','supplier_maintains_asset','P',0,'asset','asset_supplier',1,0,1,0,'Je dodáváno / servisováno dodavatelem','Dodává / servisuje aktivum','Vazba obecného aktiva (HW, SW, technologie, rozhraní) na externího dodavatele nebo servisního partnera.','Vyberte dodavatele zajišťujícího dodávku, záruku nebo servis aktiva.'),
('asset_managed_by_ou','ou_manages_asset','P',0,'asset','organization_unit',1,0,1,1,'Je spravováno organizační jednotkou (útvarem)','Spravuje / odpovídá za aktivum','Vazba aktiva (aplikace, dat, služby, HW) na organizační jednotku, která jej spravuje (umožňuje přenos rizik až na útvary a personální oddělení).','Vyberte organizační útvar odpovědný za správu tohoto aktiva.'),
('building_contains_cabling','cabling_in_building','R',0,'asset_building','asset_cabling',1,0,1,0,'Obsahuje kabeláž a rozvody','Je instalována v budově','Zpětný vztah od budovy k rozvodům a kabeláži instalované v budově.','Přehled kabeláže instalované v této budově.'),
('building_contains_room','room_in_building','R',0,'asset_building','asset_room',1,0,1,0,'Obsahuje místnost / sál','Nachází se v budově','Zpětný vztah od budovy k místnostem, které se v ní nacházejí.','Místnosti evidované uvnitř této budovy.'),
('building_in_site','site_contains_building','P',0,'asset_building','asset_site',0,0,1,0,'Nachází se v lokalitě / areálu','Obsahuje budovu','Prostorové zařazení budovy do lokality (jsou-li lokality v organizaci definovány).','Pokud evidujete areály či lokality, vyberte lokalitu, v níž budova leží.'),
('cabling_connects_room','room_connected_by_cabling','P',0,'asset_cabling','asset_room',1,0,1,0,'Propojuje místnost','Je propojena kabeláží','Seznam místností v budově, které daná kabeláž nebo rozvod napájí či datově propojuje.','Vyberte místnosti obsluhované touto kabeláží.'),
('cabling_in_building','building_contains_cabling','P',0,'asset_cabling','asset_building',0,1,1,0,'Je instalována v budově','Obsahuje kabeláž a rozvody','Povinné prostorové umístění kabeláže do konkrétní budovy. Poškození budovy se přenáší na kabeláž.','Každá kabeláž musí být přiřazena právě do jedné budovy.'),
('cabling_serves_host','host_uses_cabling','R',0,'asset_cabling','asset_host',1,0,1,0,'Propojuje / napájí hostitelský počítač','Využívá kabeláž a rozvody','Zpětný vztah od kabeláže k připojeným hostitelským počítačům a serverům.','Hostitelské počítače využívající tuto kabeláž.'),
('child_asset','parent_asset','R',1,'asset','asset',1,0,0,0,'Je nadřízeným aktivem / prostorem pro (parent_uuid)','Má nadřízené aktivum / prostor (parent_uuid)','Zpětný směr exkluzivní stromové vazby parent_uuid v tabulce asset.','Podřízené položky v primárním stromu aktiv a prostorů.'),
('child_asset_class','parent_asset_class','R',1,'asset_class','asset_class',1,0,0,0,'Obsahuje podřízenou třídu aktiv (parent_uuid)','Patří pod nadřízenou třídu aktiv (parent_uuid)','Zpětný směr exkluzivní stromové vazby parent_uuid v katalogu tříd aktiv.','Podřízené třídy aktiv ve stromu.'),
('child_countermeasure','parent_countermeasure','R',1,'countermeasure','countermeasure',1,0,0,0,'Obsahuje podřízené protiopatření (parent_uuid)','Patří pod nadřízenou skupinu opatření (parent_uuid)','Zpětný směr exkluzivní stromové vazby parent_uuid v katalogu protiopatření.','Podřízená protiopatření ve stromu.'),
('child_hierarchy_item','parent_hierarchy_item','R',1,'hierarchy_item','hierarchy_item',1,0,0,0,'Obsahuje podřízenou položku hierarchie (parent_uuid)','Patří pod nadřízený uzel hierarchie (parent_uuid)','Zpětný směr exkluzivní stromové vazby parent_uuid v tabulce hierarchy_item.','Podřízené uzly sekundární hierarchie.'),
('child_impact','parent_impact','R',1,'impact','impact',1,0,0,0,'Obsahuje podřízený dopad (parent_uuid)','Patří pod nadřízenou oblast dopadu (parent_uuid)','Zpětný směr exkluzivní stromové vazby parent_uuid v katalogu dopadů.','Podřízené položky dopadů ve stromu.'),
('child_organization_unit','parent_organization_unit','R',1,'organization_unit','organization_unit',1,0,0,0,'Řídí podřízenou organizační jednotku (parent_uuid)','Podléhá nadřízené organizační jednotce (parent_uuid)','Zpětný směr exkluzivní stromové vazby parent_uuid mezi organizačními útvary.','Podřízené organizační jednotky.'),
('child_scenario','parent_scenario','R',1,'scenario','scenario',1,0,0,0,'Obsahuje podřízený scénář (parent_uuid)','Patří pod nadřízenou skupinu scénářů (parent_uuid)','Zpětný směr exkluzivní stromové vazby parent_uuid v katalogu scénářů.','Podřízené rizikové scénáře ve stromu.'),
('child_threat','parent_threat','R',1,'threat','threat',1,0,0,0,'Obsahuje podřízenou hrozbu (parent_uuid)','Patří pod nadřízenou skupinu hrozeb (parent_uuid)','Zpětný směr exkluzivní stromové vazby parent_uuid v katalogu hrozeb.','Podřízené hrozby ve stromu.'),
('city_contains_site','site_in_city','R',0,'asset_city','asset_site',1,0,1,0,'Obsahuje lokalitu / areál','Nachází se ve městě / obci','Zpětný vztah od města k lokalitám a areálům v daném městě.','Lokality a areály nacházející se v tomto městě.'),
('city_in_district','district_contains_city','P',0,'asset_city','asset_district',0,0,1,0,'Leží v okrese / regionu','Obsahuje město / obec','Prostorové zařazení města do okresu (jsou-li okresy v organizaci definovány).','Pokud evidujete okresy, vyberte nadřízený okres.'),
('countermeasure_applies_to_asset_class','asset_class_uses_countermeasure','P',0,'asset_class','countermeasure',1,0,1,0,'Doporučené protiopatření pro třídu aktiv','Je aplikovatelné na třídu aktiv (dědí se po stromu)','Katalogová vazba určující, která protiopatření jsou relevantní pro danou třídu aktiv a její podřízené třídy.','Přiřaďte protiopatření, která se mají nabízet pro aktiva této třídy.'),
('countermeasure_mitigates_scenario','scenario_mitigated_by_cm','P',0,'scenario','countermeasure',1,0,1,1,'Je ošetřen protiopatřením','Snižuje riziko scénáře (reduction_factor / risk_factor)','Metodická vazba mezi rizikovým scénářem a protiopatřeními, která snižují jeho zbytkové riziko nebo stanovují práh rizika při neimplementaci.','Vyberte protiopatření působící proti tomuto rizikovému scénáři.'),
('countermeasure_mitigates_threat','threat_mitigated_by_cm','P',0,'threat','countermeasure',1,0,1,1,'Je potlačována protiopatřením','Působí proti hrozbě','Metodická vazba mezi katalogovou hrozbou a preventivními či detekčními protiopatřeními.','Vyberte protiopatření, která snižují působení této hrozby.'),
('countermeasure_requires_personnel','personnel_operates_cm','P',0,'countermeasure','asset_personnel',1,0,1,0,'Vyžaduje personál k realizaci / provozu','Zajišťuje provoz protiopatření','Lidské zdroje a role nezbytné k tomu, aby bezpečnostní opatření (např. ostraha, dohled SOC, revize) reálně fungovalo.','Určete personál potřebný pro chod tohoto opatření.'),
('data_evaluated_by_impact','impact_evaluates_data','P',0,'asset_data','impact',1,0,1,1,'Má hodnocen dopad v oblasti (prozrazení / chyby / ztráta)','Je oblastí dopadu pro datové aktivum','Hodnocení dopadů prozrazení dat, nekonzistence nebo chyb dat (od drobných chyb po ztrátu od poslední zálohy či úplnou likvidaci) do jednotlivých oblastí.','Ohodnoťte dopady kompromitace nebo ztráty tohoto datového aktiva.'),
('data_in_document','document_contains_data','P',0,'asset_data','asset_document',1,0,1,0,'Je zaznamenáno v dokumentu','Obsahuje datové aktivum','Uložení datového aktiva v listinném nebo řízeném elektronickém dokumentu.','Vyberte dokumenty, ve kterých se tato data nacházejí.'),
('data_on_host','host_stores_data','P',0,'asset_data','asset_host',1,0,1,1,'Je uloženo na hostitelském počítači / serveru','Ukládá datové aktivum (přenáší HW chyby a výpadky)','Fyzické nebo virtuální uložení databáze či souborů na hostitelském počítači. Selhání nebo kompromitace hosta přímo ohrožuje data.','Vyberte hostitelské počítače (servery), na kterých jsou data uložena.'),
('data_on_media','media_carries_data','P',0,'asset_data','asset_media',1,0,1,0,'Je uloženo / zálohováno na médiu','Nese datové aktivum (zálohu / archiv)','Uložení nebo zálohování datového aktiva na přenosném či trezorovém médiu.','Vyberte paměťová média, na nichž jsou uloženy kopie nebo zálohy těchto dat.'),
('data_on_physical','physical_stores_data','P',0,'asset_data','asset_physical',1,0,1,0,'Je uloženo na fyzickém zařízení','Obsahuje datové aktivum','Uložení dat na specializovaném HW zařízení (diskové pole SAN/NAS, koncová stanice, technologický prvek).','Vyberte fyzická zařízení, na kterých se data nacházejí.'),
('data_used_by_app','app_requires_data','R',0,'asset_data','asset_application',1,0,1,1,'Je využíváno aplikací (přenáší výpadky, chyby i prozrazení)','Vyžaduje a zpracovává datové aktivum','Zpětný vztah od datového aktiva k instalovaným aplikacím, které data čtou nebo zapisují (přenos chyb z dat na aplikaci).','Aplikace zpracovávající toto datové aktivum.'),
('diagram_includes_link_def','link_def_in_diagram','P',0,'link_diagram','meta_link_def',1,1,0,1,'Zahrnuje orientovaný vztah (spojnici sítě)','Je součástí schématu sítě (diagramu)','Zařazení orientovaného vztahu z meta_link_def do schématu heterogenní sítě (link_diagram) pro výpočet cest přenosu rizik.','Vyberte orientované vztahy tvořící spojnice tohoto diagramu sítě.'),
('district_contains_city','city_in_district','R',0,'asset_district','asset_city',1,0,1,0,'Obsahuje město / obec','Leží v okrese / regionu','Zpětný vztah od okresu k městům a obcím.','Města a obce evidované v tomto okrese.'),
('document_contains_data','data_in_document','R',0,'asset_document','asset_data',1,0,1,0,'Obsahuje datové aktivum','Je zaznamenáno v dokumentu','Zpětný vztah od dokumentu k datovým aktivům v něm obsaženým.','Datová aktiva zaznamenaná v tomto dokumentu.'),
('document_in_room','room_contains_document','P',0,'asset_document','asset_room',0,1,1,0,'Je uložen v místnosti','Obsahuje dokument','Povinné prostorové umístění dokumentu do konkrétní místnosti (archivu, kanceláře).','Vyberte místnost, ve které je dokument trvale uložen.'),
('host_in_room','room_contains_host','P',0,'asset_host','asset_room',0,1,1,0,'Je umístěn v místnosti','Obsahuje hostitelský počítač / server','Povinné prostorové umístění hostitelského počítače / serveru právě v jedné místnosti (serverovně).','Každý hostitelský počítač musí být umístěn právě v jedné místnosti.'),
('host_runs_app','app_runs_on_host','R',0,'asset_host','asset_application',1,0,1,1,'Hostuje instalovanou aplikaci (přenáší HW výpadky a chyby)','Běží na hostitelském počítači / serveru','Zpětný vztah od hostitelského počítače k instalovaným aplikacím, které na něm běží.','Instalované aplikace provozované na tomto serveru.'),
('host_stores_data','data_on_host','R',0,'asset_host','asset_data',1,0,1,1,'Ukládá datové aktivum (přenáší HW chyby a výpadky)','Je uloženo na hostitelském počítači / serveru','Zpětný vztah od hostitelského počítače k datovým aktivům, která jsou na něm uložena.','Datová aktiva uložená na tomto hostitelském počítači.'),
('host_uses_cabling','cabling_serves_host','P',0,'asset_host','asset_cabling',1,0,1,0,'Využívá kabeláž a rozvody','Propojuje / napájí hostitelský počítač','Závislost serveru na datové a napájecí kabeláži budovy.','Vyberte kabeláž zajišťující konektivitu a napájení tohoto hostitelského počítače.'),
('impact_caused_by_scenario','scenario_causes_impact','R',0,'impact','scenario',1,0,1,1,'Je způsoben rizikovým scénářem','Způsobuje dopad v oblasti','Zpětný vztah od oblasti dopadu k rizikovým scénářům.','Rizikové scénáře vyvolávající dopad v této oblasti.'),
('impact_evaluates_data','data_evaluated_by_impact','R',0,'impact','asset_data',1,0,1,1,'Je oblastí dopadu pro datové aktivum','Má hodnocen dopad v oblasti','Zpětný vztah od oblasti dopadu k hodnoceným datovým aktivům.','Datová aktiva hodnocená v této oblasti dopadu.'),
('impact_evaluates_service','service_evaluated_by_impact','R',0,'impact','asset_service',1,0,1,1,'Slouží k hodnocení dopadu výpadku služby','Má hodnocen výpadek / degradaci v oblasti dopadu','Zpětný vztah od oblasti dopadu ke službám.','Služby hodnocené v této oblasti dopadu.'),
('interface_provided_by_supplier','supplier_provides_interface','P',0,'asset_interface','asset_supplier',1,0,1,1,'Zajišťuje dodavatel (poskytovatel služeb)','Poskytuje službu typu Interface (internet / hlas / video)','Vazba externího rozhraní (internetové přípojky, hlasové/video služby, datového okruhu) na dodavatele.','Vyberte dodavatele (operátora / poskytovatele), který toto rozhraní zajišťuje.'),
('interface_supports_app','app_requires_interface','R',0,'asset_interface','asset_application',1,0,1,1,'Zajišťuje komunikaci pro aplikaci','Vyžaduje komunikační rozhraní (interface)','Zpětný vztah od komunikačního rozhraní k závislým aplikacím.','Aplikace využívající toto komunikační rozhraní.'),
('interface_supports_service','service_requires_interface','R',0,'asset_interface','asset_service',1,0,1,1,'Zajišťuje přenos / rozhraní pro službu','Vyžaduje rozhraní (internet / hlas / video / ext. službu)','Zpětný vztah od služby typu Interface k podporovaným službám.','Služby závislé na tomto komunikačním rozhraní.'),
('link_def_in_diagram','diagram_includes_link_def','R',0,'meta_link_def','link_diagram',1,0,0,0,'Je součástí schématu sítě (diagramu)','Zahrnuje orientovaný vztah (spojnici sítě)','Zpětný vztah od definice vztahu ke schématům sítě, v nichž je vztah použit.','Diagramy sítě obsahující tento vztah.'),
('media_carries_data','data_on_media','R',0,'asset_media','asset_data',1,0,1,0,'Nese datové aktivum (zálohu / archiv)','Je uloženo / zálohováno na médiu','Zpětný vztah od paměťového média k uloženým datovým aktivům.','Datová aktiva uložená nebo zálohovaná na tomto médiu.'),
('media_in_room','room_contains_media','P',0,'asset_media','asset_room',0,1,1,0,'Je uloženo v místnosti','Obsahuje paměťové médium','Povinné prostorové umístění média (nosiče dat) do konkrétní místnosti nebo trezoru.','Vyberte místnost, ve které je paměťové médium uloženo.'),
('ou_employs_personnel','personnel_in_ou','R',0,'organization_unit','asset_personnel',1,0,1,0,'Zahrnuje personál / pracovní role','Je zařazen v organizační jednotce','Zpětný vztah od organizační jednotky k zařazenému personálu.','Pracovníci a role patřící do tohoto útvaru.'),
('ou_manages_asset','asset_managed_by_ou','R',0,'organization_unit','asset',1,0,1,1,'Spravuje / odpovídá za aktivum','Je spravováno organizační jednotkou (útvarem)','Zpětný vztah od organizační jednotky ke spravovaným aktivům.','Aktiva spravovaná touto organizační jednotkou.'),
('parent_asset','child_asset','P',1,'asset','asset',0,0,0,0,'Má nadřízené aktivum / prostor (parent_uuid)','Je nadřízeným aktivem / prostorem pro (parent_uuid)','Exkluzivní stromový vztah parent_uuid v tabulce asset (maximálně 1 rodič, automaticky zrcadleno do link).','Nadřízený uzel ve stromu prostorů nebo aktiv.'),
('parent_asset_class','child_asset_class','P',1,'asset_class','asset_class',0,0,0,0,'Patří pod nadřízenou třídu aktiv (parent_uuid)','Obsahuje podřízenou třídu aktiv (parent_uuid)','Exkluzivní stromový vztah parent_uuid v katalogu tříd aktiv.','Nadřízená složka v katalogu tříd aktiv.'),
('parent_countermeasure','child_countermeasure','P',1,'countermeasure','countermeasure',0,0,0,0,'Patří pod nadřízenou skupinu opatření (parent_uuid)','Obsahuje podřízené protiopatření (parent_uuid)','Exkluzivní stromový vztah parent_uuid v katalogu protiopatření.','Nadřízená skupina v katalogu protiopatření.'),
('parent_hierarchy_item','child_hierarchy_item','P',1,'hierarchy_item','hierarchy_item',0,0,0,0,'Patří pod nadřízený uzel hierarchie (parent_uuid)','Obsahuje podřízenou položku hierarchie (parent_uuid)','Exkluzivní stromový vztah parent_uuid v položkách sekundárních hierarchií.','Nadřízený uzel v sekundární hierarchii.'),
('parent_impact','child_impact','P',1,'impact','impact',0,0,0,0,'Patří pod nadřízenou oblast dopadu (parent_uuid)','Obsahuje podřízený dopad (parent_uuid)','Exkluzivní stromový vztah parent_uuid v katalogu dopadů.','Nadřízená oblast v katalogu dopadů.'),
('parent_organization_unit','child_organization_unit','P',1,'organization_unit','organization_unit',0,0,0,1,'Podléhá nadřízené organizační jednotce (parent_uuid)','Řídí podřízenou organizační jednotku (parent_uuid)','Exkluzivní stromový vztah nadřízenosti mezi organizačními jednotkami (umožňuje přenos rizik hierarchií řízení).','Nadřízený útvar v organizační struktuře.'),
('parent_scenario','child_scenario','P',1,'scenario','scenario',0,0,0,0,'Patří pod nadřízenou skupinu scénářů (parent_uuid)','Obsahuje podřízený scénář (parent_uuid)','Exkluzivní stromový vztah parent_uuid v katalogu rizikových scénářů.','Nadřízená skupina v katalogu scénářů.'),
('parent_threat','child_threat','P',1,'threat','threat',0,0,0,0,'Patří pod nadřízenou skupinu hrozeb (parent_uuid)','Obsahuje podřízenou hrozbu (parent_uuid)','Exkluzivní stromový vztah parent_uuid v katalogu hrozeb.','Nadřízená skupina v katalogu hrozeb.'),
('personnel_in_ou','ou_employs_personnel','P',0,'asset_personnel','organization_unit',1,0,1,1,'Je zařazen v organizační jednotce (útvaru)','Zahrnuje personál / pracovní role','Zařazení klíčového personálu nebo role do organizační jednotky (např. IT oddělení, HR / personální oddělení zajišťující školení).','Vyberte organizační útvar, do kterého pracovník nebo role patří.'),
('personnel_operates_app','app_requires_personnel','R',0,'asset_personnel','asset_application',1,0,1,1,'Spravuje / obsluhuje aplikaci (zdroj lidských chyb)','Vyžaduje personál (správa a obsluha)','Zpětný vztah od personálu k aplikacím, které spravuje nebo obsluhuje.','Aplikace závislé na této pracovní roli či osobě.'),
('personnel_operates_cm','countermeasure_requires_personnel','R',0,'asset_personnel','countermeasure',1,0,1,0,'Zajišťuje provoz protiopatření','Vyžaduje personál k realizaci / provozu','Zpětný vztah od personálu k protiopatřením, jejichž chod zajišťuje.','Protiopatření vyžadující tuto roli nebo osobu.'),
('personnel_supports_service','service_requires_personnel','R',0,'asset_personnel','asset_service',1,0,1,1,'Zajišťuje provoz a obsluhu služby','Vyžaduje personál pro zajištění služby','Zpětný vztah od personálu k podporovaným službám.','Služby závislé na této pracovní roli či osobě.'),
('physical_in_room','room_contains_physical','P',0,'asset_physical','asset_room',0,1,1,0,'Je umístěno v místnosti','Obsahuje fyzické aktivum','Povinné prostorové umístění každého fyzického aktiva právě v jedné místnosti.','Každé fyzické aktivum musí být umístěno právě v jedné místnosti.'),
('physical_stores_data','data_on_physical','R',0,'asset_physical','asset_data',1,0,1,0,'Obsahuje datové aktivum','Je uloženo na fyzickém zařízení','Zpětný vztah od fyzického zařízení k uloženým datovým aktivům.','Datová aktiva uložená na tomto zařízení.'),
('room_connected_by_cabling','cabling_connects_room','R',0,'asset_room','asset_cabling',1,0,1,0,'Je propojena kabeláží','Propojuje místnost','Zpětný vztah od místnosti ke kabeláži, která místnost obsluhuje.','Kabeláž a rozvody propojující tuto místnost.'),
('room_contains_document','document_in_room','R',0,'asset_room','asset_document',1,0,1,0,'Obsahuje dokument','Je uložen v místnosti','Zpětný vztah od místnosti k dokumentům v ní uloženým.','Dokumenty umístěné v této místnosti.'),
('room_contains_host','host_in_room','R',0,'asset_room','asset_host',1,0,1,0,'Obsahuje hostitelský počítač / server','Je umístěn v místnosti','Zpětný vztah od místnosti (serverovny) k umístěným serverům.','Hostitelské počítače a servery umístěné v této místnosti.'),
('room_contains_media','media_in_room','R',0,'asset_room','asset_media',1,0,1,0,'Obsahuje paměťové médium','Je uloženo v místnosti','Zpětný vztah od místnosti k paměťovým médiím v ní uloženým.','Paměťová média uložená v této místnosti.'),
('room_contains_physical','physical_in_room','R',0,'asset_room','asset_physical',1,0,1,0,'Obsahuje fyzické aktivum','Je umístěno v místnosti','Zpětný vztah od místnosti k fyzickým aktivům a technologiím v ní umístěným.','Fyzická aktiva umístěna v této místnosti.'),
('room_in_building','building_contains_room','P',0,'asset_room','asset_building',0,1,1,0,'Nachází se v budově','Obsahuje místnost','Povinné prostorové zařazení místnosti do budovy. Každá místnost musí patřit právě do jedné budovy.','Vyberte budovu, ve které se tato místnost nachází.'),
('scenario_causes_impact','impact_caused_by_scenario','P',0,'scenario','impact',1,0,1,1,'Způsobuje dopad v oblasti','Je způsoben rizikovým scénářem','Určuje, které oblasti dopadů (finanční, pověst, obecné ohrožení, trestní odpovědnost, řízení firmy, zákony) daný scénář vyvolává.','Přiřaďte oblasti dopadů, které tento rizikový scénář ohrožuje.'),
('scenario_mitigated_by_cm','countermeasure_mitigates_scenario','R',0,'countermeasure','scenario',1,0,1,1,'Snižuje riziko scénáře (reduction_factor / risk_factor)','Je ošetřen protiopatřením','Zpětný vztah od protiopatření k rizikovým scénářům, které opatření ošetřuje.','Rizikové scénáře ošetřované tímto protiopatřením.'),
('service_evaluated_by_impact','impact_evaluates_service','P',0,'asset_service','impact',1,0,1,1,'Má hodnocen výpadek / degradaci v oblasti dopadu','Slouží k hodnocení dopadu výpadku služby','Hodnocení dopadů výpadku nebo degradace služby do jednotlivých oblastí (finanční, pověst, obecné ohrožení, trestní odpovědnost, řízení firmy, zákony).','Určete oblasti dopadů a míru závažnosti při výpadku nebo degradaci této služby.'),
('service_requires_app','app_supports_service','P',0,'asset_service','asset_application',1,0,1,1,'Vyžaduje aplikaci (je jí podporována)','Podporuje službu (přenáší na ni výpadky a chyby)','Klíčová vazba M:N mezi službou a podpůrnými aplikacemi. Výpadky aplikací i chyby/prozrazení jejich dat se přenášejí na službu.','Vyberte instalované aplikace, které jsou nezbytné pro poskytování této služby.'),
('service_requires_interface','interface_supports_service','P',0,'asset_service','asset_interface',1,0,1,1,'Vyžaduje rozhraní (internet / hlas / video / ext. službu)','Zajišťuje přenos / rozhraní pro službu','Závislost služby na komunikačním rozhraní nebo jiné dříve definované službě (internet, hlasové či video spojení).','Vyberte služby typu Interface, které tato služba ke svému provozu potřebuje.'),
('service_requires_personnel','personnel_supports_service','P',0,'asset_service','asset_personnel',1,0,1,1,'Vyžaduje personál pro zajištění služby','Zajišťuje provoz a obsluhu služby','Závislost služby na klíčových pracovnících a rolích.','Přiřaďte personál nezbytný pro poskytování této služby.'),
('service_requires_service','service_supports_service','P',0,'asset_service','asset_service',1,0,1,1,'Vyžaduje podřízenou (interní) službu','Podporuje nadřazenou službu (přenáší výpadky)','Vnitrotřídní orientovaný vztah mezi interními podpůrnými službami a koncovými byznys službami (s kontrolou acykličnosti).','Vyberte jiné interní služby, na kterých je tato služba závislá.'),
('service_supports_service','service_requires_service','R',0,'asset_service','asset_service',1,0,1,1,'Podporuje nadřazenou službu (přenáší výpadky)','Vyžaduje podřízenou (interní) službu','Zpětný vnitrotřídní vztah od podpůrné služby k nadřazeným službám.','Nadřazené služby závislé na této službě.'),
('site_contains_building','building_in_site','R',0,'asset_site','asset_building',1,0,1,0,'Obsahuje budovu','Nachází se v lokalitě / areálu','Zpětný vztah od lokality (areálu) k budovám, které se v ní nacházejí.','Budovy evidované v této lokalitě.'),
('site_in_city','city_contains_site','P',0,'asset_site','asset_city',0,0,1,0,'Nachází se ve městě / obci','Obsahuje lokalitu / areál','Prostorové zařazení lokality do města (jsou-li města v organizaci definována).','Pokud evidujete města, vyberte město, v němž se lokalita nachází.'),
('supplier_maintains_asset','asset_maintained_by_supplier','R',0,'asset_supplier','asset',1,0,1,0,'Dodává / servisuje aktivum','Je dodáváno / servisováno dodavatelem','Zpětný vztah od dodavatele k dodávaným nebo servisovaným aktivům.','Aktiva dodávaná nebo servisovaná tímto dodavatelem.'),
('supplier_provides_interface','interface_provided_by_supplier','R',0,'asset_supplier','asset_interface',1,0,1,1,'Poskytuje službu typu Interface (internet / hlas / video)','Zajišťuje dodavatel (poskytovatel služeb)','Zpětný vztah od dodavatele ke komunikačním rozhraním, která provozuje.','Služby typu Interface poskytované tímto dodavatelem.'),
('sw_deployed_as_app','app_instance_of_sw','R',0,'asset_software','asset_application',1,0,1,1,'Je nasazen jako instalovaná aplikace (přenáší SW chyby)','Je instalací softwaru','Zpětný vztah od softwarového produktu k jeho instalovaným instancím (aplikacím).','Instalované instance (aplikace) tohoto softwaru.'),
('threat_applies_to_asset_class','asset_class_exposed_to_threat','P',0,'asset_class','threat',1,0,1,0,'Je vystavena působení hrozby','Působí na třídu aktiv (dědí se po stromu)','Katalogová vazba určující, které hrozby působí na danou třídu aktiv a automaticky se dědí na podřízené třídy.','Přiřaďte hrozby relevantní pro tuto třídu aktiv.'),
('threat_mitigated_by_cm','countermeasure_mitigates_threat','R',0,'countermeasure','threat',1,0,1,1,'Působí proti hrozbě','Je potlačována protiopatřením','Zpětný vztah od protiopatření ke katalogovým hrozbám, které opatření potlačuje.','Hrozby potlačované tímto protiopatřením.');

-- 4. Idempotentní UPDATE existujících hlavních záznamů v meta_link_def (record_type = 'A', language = 'cs')
UPDATE t
SET t.from_class = fc.orig,
	t.to_class = tc.orig,
	t.reverse_link_def = rc.rev_orig,
	t.direction_type = s.direction_type,
	t.is_exclusive_parent = s.is_exclusive_parent,
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
OUTER APPLY (SELECT CASE WHEN s.reverse_code IS NOT NULL THEN dbo.f_generate_original('meta_link_def', @sys_owner, s.reverse_code, '') ELSE NULL END AS rev_orig) rc
WHERE t.object_owner = @sys_owner
  AND t.record_type = 'A'
  AND t.who_modified = @sys_owner
  AND EXISTS (
	SELECT t.from_class, t.to_class, t.reverse_link_def, t.direction_type, t.is_exclusive_parent, t.is_multiple, t.is_mandatory, t.leaf_only, t.link_weight_enabled, t.caption_forward, t.caption_backward, t.description, t.helptext
	EXCEPT
	SELECT fc.orig, tc.orig, rc.rev_orig, s.direction_type, s.is_exclusive_parent, s.is_multiple, s.is_mandatory, s.leaf_only, s.link_weight_enabled, s.caption_forward, s.caption_backward, s.description, s.helptext
  );

-- 5. Idempotentní INSERT chybějících hlavních záznamů v meta_link_def (record_type = 'A', language = 'cs')
INSERT INTO meta_link_def (
	uuid, object_owner, original, record_type, approval_status, [language],
	link_code, from_class, to_class, reverse_link_def, direction_type, is_exclusive_parent,
	caption_forward, caption_backward, description, helptext,
	is_multiple, is_mandatory, leaf_only, link_weight_enabled,
	is_final, is_protected
)
SELECT
	x.orig, @sys_owner, x.orig, 'A', 'A', 'cs',
	s.link_code, fc.orig, tc.orig, rc.rev_orig, s.direction_type, s.is_exclusive_parent,
	s.caption_forward, s.caption_backward, s.description, s.helptext,
	s.is_multiple, s.is_mandatory, s.leaf_only, s.link_weight_enabled,
	1, 1
FROM @links_cs s
CROSS APPLY (SELECT dbo.f_generate_original('meta_link_def', @sys_owner, s.link_code, '') AS orig) x
CROSS APPLY (SELECT dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), s.from_class_code, '') AS orig) fc
CROSS APPLY (SELECT dbo.f_generate_original('meta_class', CAST(@sys_owner AS varchar(36)), s.to_class_code, '') AS orig) tc
OUTER APPLY (SELECT CASE WHEN s.reverse_code IS NOT NULL THEN dbo.f_generate_original('meta_link_def', @sys_owner, s.reverse_code, '') ELSE NULL END AS rev_orig) rc
WHERE NOT EXISTS (
	SELECT 1 FROM meta_link_def t
	WHERE t.original = x.orig AND t.object_owner = @sys_owner AND t.record_type = 'A'
);

-- 6. Idempotentní UPDATE a INSERT symetrických 'L' záznamů pro češtinu (language = 'cs')
UPDATE l
SET l.from_class = a.from_class,
	l.to_class = a.to_class,
	l.reverse_link_def = a.reverse_link_def,
	l.direction_type = a.direction_type,
	l.is_exclusive_parent = a.is_exclusive_parent,
	l.caption_forward = s.caption_forward,
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
	SELECT l.reverse_link_def, l.direction_type, l.is_exclusive_parent, l.caption_forward, l.caption_backward, l.description, l.helptext
	EXCEPT
	SELECT a.reverse_link_def, a.direction_type, a.is_exclusive_parent, s.caption_forward, s.caption_backward, s.description, s.helptext
  );

INSERT INTO meta_link_def (
	uuid, object_owner, original, record_type, approval_status, [language],
	link_code, from_class, to_class, reverse_link_def, direction_type, is_exclusive_parent,
	caption_forward, caption_backward, description, helptext,
	is_multiple, is_mandatory, leaf_only, link_weight_enabled,
	is_final, is_protected
)
SELECT
	NEWID(), @sys_owner, a.original, 'L', 'A', 'cs',
	a.link_code, a.from_class, a.to_class, a.reverse_link_def, a.direction_type, a.is_exclusive_parent,
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