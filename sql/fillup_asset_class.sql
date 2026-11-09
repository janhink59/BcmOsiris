/* =============================================================================
 * Verze: 2026-11-09 14:15
 * Soubor: fillup_asset_class.sql
 * Účel:   Idempotentní prvotní naplnění systémového katalogu tříd aktiv
 *         v tabulce asset_class (object_owner = 0x00, jazyk 'cs', záznamy 'A'
 *         a symetrické 'L'), seřazené abecedně podle builtin_code.
 * Vazby:  - Vyžaduje tabulku asset_class (table_asset_class.sql) a funkci
 *           dbo.f_generate_original (f_generate_original.sql).
 *         - Automaticky zařazeno v BuildListDb.txt přes masku fillup_*.sql.
 * ============================================================================= */

SET NOCOUNT ON;
GO

DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);

DECLARE @ac_cs TABLE (
	builtin_code varchar(80) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
	parent_code varchar(80) COLLATE DATABASE_DEFAULT NULL,
	sort_code varchar(200) NOT NULL,
	is_leaf bit NOT NULL,
	instance_class_name varchar(80) NOT NULL,
	caption varchar(200) NOT NULL,
	shortname varchar(40) NOT NULL,
	description_text varchar(max) NOT NULL,
	svg_icon varchar(max) NOT NULL
);

INSERT INTO @ac_cs (builtin_code, parent_code, sort_code, is_leaf, instance_class_name, caption, shortname, description_text, svg_icon) VALUES
('ac_application','ac_grp_sw_apps','020',1,'asset_application','Aplikace (instalované)','APP','Konkrétní instalované instance aplikačního vybavení provozované na hostitelských počítačích a vyžadující datová aktiva a personál.','<svg viewBox="0 0 24 24" fill="#2563EB"><path d="M19 3H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm0 16H5V8h14v11z"/></svg>'),
('ac_building','ac_grp_space','040',1,'asset_building','Budovy','BLD','Stavební objekty a budovy. V organizaci musí být definována alespoň jedna budova (i fiktivní), do níž se umisťují místnosti a kabeláž.','<svg viewBox="0 0 24 24" fill="#0284C7"><path d="M12 7V3H2v18h20V7H12zM6 19H4v-2h2v2zm0-4H4v-2h2v2zm0-4H4V9h2v2zm0-4H4V5h2v2zm4 12H8v-2h2v2zm0-4H8v-2h2v2zm0-4H8V9h2v2zm0-4H8V5h2v2zm10 12h-8v-2h2v-2h-2v-2h2v-2h-2V9h8v10z"/></svg>'),
('ac_cabling','ac_grp_tech','030',1,'asset_cabling','Kabeláž a rozvody','CAB','Strukturovaná datová kabeláž, optické trasy a silnoproudé rozvody umístěné v budově a propojující místnosti.','<svg viewBox="0 0 24 24" fill="#D97706"><path d="M20 10V8h-4V4h-2v4h-4V4H8v4H4v2h4v4H4v2h4v4h2v-4h4v4h2v-4h4v-2h-4v-4h4zm-6 4h-4v-4h4v4z"/></svg>'),
('ac_city','ac_grp_space','020',1,'asset_city','Města a obce','CITY','Města a obce, ve kterých se nacházejí lokality a budovy organizace (volitelná úroveň prostorové hierarchie).','<svg viewBox="0 0 24 24" fill="#0891B2"><path d="M15 11V5l-3-3-3 3v2H3v14h18V11h-6zm-8 8H5v-2h2v2zm0-4H5v-2h2v2zm0-4H5V9h2v2zm6 8h-2v-2h2v2zm0-4h-2v-2h2v2zm0-4h-2V9h2v2zm0-4h-2V5h2v2zm6 12h-2v-2h2v2zm0-4h-2v-2h2v2z"/></svg>'),
('ac_data','ac_grp_info','010',1,'asset_data','Datová aktiva (Informace a databáze)','DATA','Datová aktiva, databáze a logické informační celky uložené na hostitelských počítačích, médiích nebo v dokumentech.','<svg viewBox="0 0 24 24" fill="#7C3AED"><path d="M12 3C7.58 3 4 4.79 4 7s3.58 4 8 4 8-1.79 8-4-3.58-4-8-4zM4 9v3c0 2.21 3.58 4 8 4s8-1.79 8-4V9c0 2.21-3.58 4-8 4s-8-1.79-8-4zm0 5v3c0 2.21 3.58 4 8 4s8-1.79 8-4v-3c0 2.21-3.58 4-8 4s-8-1.79-8-4z"/></svg>'),
('ac_district','ac_grp_space','010',1,'asset_district','Okresy a regiony','DIST','Územní okresy a regiony představující nejvyšší volitelnou úroveň prostorového členění aktiv.','<svg viewBox="0 0 24 24" fill="#0D9488"><path d="M20.5 3l-.16.03L15 5.1 9 3 3.36 4.9c-.21.07-.36.25-.36.48V20.5c0 .28.22.5.5.5l.16-.03L9 18.9l6 2.1 5.64-1.9c.21-.07.36-.25.36-.48V3.5c0-.28-.22-.5-.5-.5zM15 19l-6-2.11V5l6 2.11V19z"/></svg>'),
('ac_document','ac_grp_info','020',1,'asset_document','Dokumenty','DOC','Řízené listinné i elektronické dokumenty, smlouvy a provozní dokumentace uložená v místnostech a nesoucí informace.','<svg viewBox="0 0 24 24" fill="#9333EA"><path d="M14 2H6c-1.1 0-1.99.9-1.99 2L4 20c0 1.1.89 2 1.99 2H18c1.1 0 2-.9 2-2V8l-6-6zm2 16H8v-2h8v2zm0-4H8v-2h8v2zm-3-5V3.5L18.5 9H13z"/></svg>'),
('ac_grp_info',NULL,'030',0,'','Informace, data, dokumenty a média','INFO','Složka datových aktiv, dokumentů a přenosných či záložních paměťových médií.','<svg viewBox="0 0 24 24" fill="#7C3AED"><path d="M10 4H4c-1.1 0-1.99.9-1.99 2L2 18c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V8c0-1.1-.9-2-2-2h-8l-2-2z"/></svg>'),
('ac_grp_people_ext',NULL,'060',0,'','Personál a externí dodavatelé','PPL','Složka lidských zdrojů, klíčových rolí a externích dodavatelů či servisních partnerů.','<svg viewBox="0 0 24 24" fill="#059669"><path d="M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5c-1.66 0-3 1.34-3 3s1.34 3 3 3zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5C6.34 5 5 6.34 5 8s1.34 3 3 3zm0 2c-2.33 0-7 1.17-7 3.5V19h14v-2.5c0-2.33-4.67-3.5-7-3.5z"/></svg>'),
('ac_grp_services',NULL,'050',0,'','Služby a komunikační rozhraní','SRV','Složka primárních byznys služeb, interních podpůrných služeb a externích/interních rozhraní (interface).','<svg viewBox="0 0 24 24" fill="#EA580C"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 17.93c-3.95-.49-7-3.85-7-7.93 0-.62.08-1.21.21-1.79L9 15v1c0 1.1.9 2 2 2v1.93zm6.9-2.54c-.26-.81-1-1.39-1.9-1.39h-1v-3c0-.55-.45-1-1-1H8v-2h2c.55 0 1-.45 1-1V7h2c1.1 0 2-.9 2-2v-.41c2.93 1.19 5 4.06 5 7.41 0 2.08-.8 3.97-2.1 5.39z"/></svg>'),
('ac_grp_space',NULL,'010',0,'','Prostory a lokality','LOC','Hierarchická složka prostorového umístění aktiv (Okres -> Město -> Lokalita -> Budova -> Místnost).','<svg viewBox="0 0 24 24" fill="#0284C7"><path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z"/></svg>'),
('ac_grp_sw_apps',NULL,'040',0,'','Software a instalované aplikace','SW','Složka vyvíjeného či nakupovaného softwaru a konkrétních instalovaných aplikací.','<svg viewBox="0 0 24 24" fill="#2563EB"><path d="M20 4H4c-1.1 0-1.99.9-1.99 2L2 18c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2zm-5 14H4v-4h11v4zm0-5H4V9h11v4zm5 5h-4V9h4v9z"/></svg>'),
('ac_grp_tech',NULL,'020',0,'','Technická a fyzická aktiva (HW a sítě)','TECH','Složka hmotného vybavení, hostitelských počítačů, serverů, síťových prvků, technologií budov a kabeláže.','<svg viewBox="0 0 24 24" fill="#475569"><path d="M4 6h16v2H4zm0 5h16v2H4zm0 5h16v2H4z"/></svg>'),
('ac_host','ac_grp_tech','020',1,'asset_host','Hostitelské počítače a servery','HOST','Speciální podtřída fyzických aktiv: fyzické i virtuální servery a hostitelské počítače umístěné v místnostech, na kterých běží aplikace a jsou uložena data.','<svg viewBox="0 0 24 24" fill="#1D4ED8"><path d="M20 13H4c-.55 0-1 .45-1 1v6c0 .55.45 1 1 1h16c.55 0 1-.45 1-1v-6c0-.55-.45-1-1-1zM7 19c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2zM20 3H4c-.55 0-1 .45-1 1v6c0 .55.45 1 1 1h16c.55 0 1-.45 1-1V4c0-.55-.45-1-1-1zM7 9c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2z"/></svg>'),
('ac_interface','ac_grp_services','020',1,'asset_interface','Služby typu Interface (Internet, hlas, video)','IFC','Externí nebo interní propojovací a komunikační služby (internetová konektivita, hlasové a video spojení, API rozhraní) vyžadované jinými službami.','<svg viewBox="0 0 24 24" fill="#D97706"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 14H9v-2h2v2zm0-4H9V7h2v5zm4 4h-2v-2h2v2zm0-4h-2V7h2v5z"/></svg>'),
('ac_media','ac_grp_info','030',1,'asset_media','Média a nosiče dat','MED','Přenosná a záložní paměťová média (záložní pásky, externí disky, flash disky, optické nosiče) uložená v místnostech nebo trezorech.','<svg viewBox="0 0 24 24" fill="#DB2777"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 14.5c-2.49 0-4.5-2.01-4.5-4.5S9.51 7.5 12 7.5s4.5 2.01 4.5 4.5-2.01 4.5-4.5 4.5zm0-5.5c-.55 0-1 .45-1 1s.45 1 1 1 1-.45 1-1-.45-1-1-1z"/></svg>'),
('ac_personnel','ac_grp_people_ext','010',1,'asset_personnel','Personál a klíčové role','PERS','Interní i externí pracovníci, administrátoři, operátoři a klíčové pracovní role nezbytné pro provoz aplikací, služeb a realizaci protiopatření.','<svg viewBox="0 0 24 24" fill="#059669"><path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z"/></svg>'),
('ac_physical','ac_grp_tech','010',1,'asset_physical','Fyzická aktiva a hardware','HW','Obecná hmotná a technická aktiva, síťové prvky, koncové stanice, výrobní stroje a podpůrné technologie budov (UPS, klimatizace, EPS/EZS) umístěné v místnostech.','<svg viewBox="0 0 24 24" fill="#475569"><path d="M20 18c1.1 0 1.99-.9 1.99-2L22 6c0-1.1-.9-2-2-2H4c-1.1 0-2 .9-2 2v10c0 1.1.9 2 2 2H0v2h24v-2h-4zM4 6h16v10H4V6z"/></svg>'),
('ac_room','ac_grp_space','050',1,'asset_room','Místnosti a sály','ROOM','Konkrétní místnosti, serverovny, archivy a pracoviště uvnitř budov. Do místností se povinně umisťují fyzická aktiva, hostitelské počítače, dokumenty a média.','<svg viewBox="0 0 24 24" fill="#0369A1"><path d="M19 19V4h-4V3H5v16H3v2h12V6h2v15h4v-2h-2zm-6 0H7V5h6v14zm-3-8h2v2h-2v-2z"/></svg>'),
('ac_service','ac_grp_services','010',1,'asset_service','Služby (interní a zákaznické)','SVC','Hlavní byznys služby a interní podpůrné služby organizace podporované aplikacemi, rozhraními a personálem, u nichž se hodnotí dopady výpadků do jednotlivých oblastí.','<svg viewBox="0 0 24 24" fill="#EA580C"><path d="M12 2l-5.5 9h11L12 2zm0 3.84L13.93 9h-3.87L12 5.84zM17.5 13c-2.49 0-4.5 2.01-4.5 4.5s2.01 4.5 4.5 4.5 4.5-2.01 4.5-4.5-2.01-4.5-4.5-4.5zM3 21.5h8v-8H3v8z"/></svg>'),
('ac_site','ac_grp_space','030',1,'asset_site','Lokality a areály','SITE','Areály, kampusy a pobočky sdružující více budov v rámci města nebo obce (volitelná úroveň prostorové hierarchie).','<svg viewBox="0 0 24 24" fill="#0284C7"><path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7z"/></svg>'),
('ac_software','ac_grp_sw_apps','010',1,'asset_software','Software (vyvíjený a pořizovaný)','SWP','Zdrojové softwarové produkty, interně vyvíjený software a instalační balíky, které mohou být zdrojem softwarových chyb pro instalované aplikace.','<svg viewBox="0 0 24 24" fill="#4F46E5"><path d="M9.4 16.6L4.8 12l4.6-4.6L8 6l-6 6 6 6 1.4-1.4zm5.2 0l4.6-4.6-4.6-4.6L16 6l6 6-6 6-1.4-1.4z"/></svg>'),
('ac_supplier','ac_grp_people_ext','020',1,'asset_supplier','Dodavatelé a externí partneři','SUP','Externí dodavatelé komunikačních rozhraní (interface), cloudových služeb, hardwaru, softwaru a servisní podpory.','<svg viewBox="0 0 24 24" fill="#16A34A"><path d="M20 8h-3V4H3c-1.1 0-2 .9-2 2v11h2c0 1.66 1.34 3 3 3s3-1.34 3-3h6c0 1.66 1.34 3 3 3s3-1.34 3-3h2v-5l-3-4z"/></svg>');

-- 1. Idempotentní UPDATE existujících hlavních záznamů (record_type = 'A', language = 'cs')
UPDATE t
SET t.parent_uuid = p.parent_orig,
	t.sort_code = s.sort_code,
	t.is_leaf = s.is_leaf,
	t.instance_class_name = s.instance_class_name,
	t.caption = s.caption,
	t.shortname = s.shortname,
	t.description_text = s.description_text,
	t.svg_icon = CASE WHEN ISNULL(t.svg_icon, '') = '' THEN s.svg_icon ELSE t.svg_icon END,
	t.[language] = 'cs',
	t.date_modified = GETDATE()
FROM asset_class t
JOIN @ac_cs s ON s.builtin_code = t.builtin_code
OUTER APPLY (
	SELECT CASE WHEN s.parent_code IS NOT NULL THEN dbo.f_generate_original('asset_class', @sys_owner, s.parent_code, '') ELSE NULL END AS parent_orig
) p
WHERE t.object_owner = @sys_owner
  AND t.record_type = 'A'
  AND t.who_modified = @sys_owner
  AND EXISTS (
	SELECT t.parent_uuid, t.sort_code, t.is_leaf, t.instance_class_name, t.caption, t.shortname, t.description_text
	EXCEPT
	SELECT p.parent_orig, s.sort_code, s.is_leaf, s.instance_class_name, s.caption, s.shortname, s.description_text
  );

-- 2. Idempotentní INSERT chybějících hlavních záznamů (record_type = 'A', language = 'cs')
INSERT INTO asset_class (
	uuid, object_owner, original, record_type, approval_status, [language],
	builtin_code, parent_uuid, sort_code, is_leaf, instance_class_name,
	caption, shortname, description_text, svg_icon, is_final, is_protected
)
SELECT
	x.orig, @sys_owner, x.orig, 'A', 'A', 'cs',
	s.builtin_code, p.parent_orig, s.sort_code, s.is_leaf, s.instance_class_name,
	s.caption, s.shortname, s.description_text, s.svg_icon, 0, 1
FROM @ac_cs s
CROSS APPLY (
	SELECT dbo.f_generate_original('asset_class', @sys_owner, s.builtin_code, '') AS orig
) x
OUTER APPLY (
	SELECT CASE WHEN s.parent_code IS NOT NULL THEN dbo.f_generate_original('asset_class', @sys_owner, s.parent_code, '') ELSE NULL END AS parent_orig
) p
WHERE NOT EXISTS (
	SELECT 1 FROM asset_class t
	WHERE t.original = x.orig AND t.object_owner = @sys_owner AND t.record_type = 'A'
);

-- 3. Idempotentní UPDATE a INSERT symetrických 'L' záznamů pro češtinu (language = 'cs')
UPDATE l
SET l.caption = s.caption,
	l.shortname = s.shortname,
	l.description_text = s.description_text,
	l.date_modified = GETDATE()
FROM asset_class l
JOIN asset_class a ON a.original = l.original AND a.object_owner = @sys_owner AND a.record_type = 'A'
JOIN @ac_cs s ON s.builtin_code = a.builtin_code
WHERE l.object_owner = @sys_owner
  AND l.record_type = 'L'
  AND l.[language] = 'cs'
  AND l.who_modified = @sys_owner
  AND EXISTS (
	SELECT l.caption, l.shortname, l.description_text
	EXCEPT
	SELECT s.caption, s.shortname, s.description_text
  );

INSERT INTO asset_class (
	uuid, object_owner, original, record_type, approval_status, [language],
	builtin_code, parent_uuid, sort_code, is_leaf, instance_class_name,
	caption, shortname, description_text, svg_icon, is_final, is_protected
)
SELECT
	NEWID(), @sys_owner, a.original, 'L', 'A', 'cs',
	a.builtin_code, a.parent_uuid, a.sort_code, a.is_leaf, a.instance_class_name,
	s.caption, s.shortname, s.description_text, a.svg_icon, a.is_final, a.is_protected
FROM asset_class a
JOIN @ac_cs s ON s.builtin_code = a.builtin_code
WHERE a.object_owner = @sys_owner
  AND a.record_type = 'A'
  AND a.removed = 0
  AND NOT EXISTS (
	SELECT 1 FROM asset_class l
	WHERE l.original = a.original AND l.object_owner = @sys_owner AND l.record_type = 'L' AND l.[language] = 'cs'
  );
GO