/* =============================================================================
 * Verze: 2026-11-09 14:15
 * Soubor: fillup_impact.sql
 * Účel:   Idempotentní prvotní naplnění systémového katalogu oblastí dopadů
 *         v tabulce impact (object_owner = 0x00, jazyk 'cs', záznamy 'A'
 *         a symetrické 'L'), seřazené abecedně podle builtin_code.
 * Vazby:  - Vyžaduje tabulku impact (table_impact.sql) a funkci
 *           dbo.f_generate_original (f_generate_original.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);

DECLARE @imp_cs TABLE (
	builtin_code varchar(80) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
	parent_code varchar(80) COLLATE DATABASE_DEFAULT NULL,
	sort_code varchar(200) NOT NULL,
	is_leaf bit NOT NULL,
	caption varchar(200) NOT NULL,
	shortname varchar(40) NOT NULL,
	description_text varchar(max) NOT NULL,
	svg_icon varchar(max) NOT NULL
);

INSERT INTO @imp_cs (builtin_code, parent_code, sort_code, is_leaf, caption, shortname, description_text, svg_icon) VALUES
('imp_criminal_liability',NULL,'040',1,'Trestní odpovědnost','TREST','Riziko trestního stíhání nebo postihu statutárních orgánů, managementu či odpovědných zaměstnanců v důsledku výpadku služby, prozrazení nebo zničení dat.','<svg viewBox="0 0 24 24" fill="#991B1B"><path d="M12 1L3 5v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V5l-9-4zm1 14h-2v-2h2v2zm0-4h-2V7h2v4z"/></svg>'),
('imp_financial',NULL,'010',1,'Finanční dopad','FIN','Přímé finanční ztráty, náklady na obnovu provozu a dat, smluvní pokuty (SLA) a ušlý zisk při výpadku služby, chybovosti nebo likvidaci dat.','<svg viewBox="0 0 24 24" fill="#D97706"><path d="M11.8 10.9c-2.27-.59-3-1.2-3-2.15 0-1.09 1.01-1.85 2.7-1.85 1.78 0 2.44.85 2.5 2.1h2.21c-.07-1.72-1.12-3.3-3.21-3.81V3h-3v2.16c-1.94.42-3.5 1.68-3.5 3.61 0 2.31 1.91 3.46 4.7 4.13 2.5.6 3 1.48 3 2.41 0 .69-.49 1.79-2.7 1.79-2.06 0-2.87-.92-2.98-2.1h-2.2c.12 2.19 1.76 3.42 3.68 3.83V21h3v-2.15c1.95-.37 3.5-1.5 3.5-3.55 0-2.84-2.43-3.81-4.7-4.4z"/></svg>'),
('imp_general_hazard',NULL,'030',1,'Obecné ohrožení (život, zdraví, bezpečnost)','OHROZ','Ohrožení života a zdraví osob, bezpečnosti práce, veřejného pořádku nebo životního prostředí při selhání služby či nekonzistenci kritických dat.','<svg viewBox="0 0 24 24" fill="#DC2626"><path d="M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z"/></svg>'),
('imp_legal_breach',NULL,'060',1,'Porušení zákonů a regulací','ZAKON','Porušení zákonných a regulatorních povinností (GDPR, zákon o kybernetické bezpečnosti / NIS2, DORA, oborové předpisy), správní sankce a odebrání licencí.','<svg viewBox="0 0 24 24" fill="#7C3AED"><path d="M4 10v7h3v-7H4zm6 0v7h3v-7h-3zM2 22h19v-3H2v3zm14-12v7h3v-7h-3zm-4.5-9L2 6v2h19V6l-9.5-5z"/></svg>'),
('imp_management_disruption',NULL,'050',1,'Narušení řízení firmy','RIZENI','Ochromení vnitřního rozhodování, ztráta přehledu o stavu organizace, nemožnost řízení klíčových procesů v důsledku nedostupnosti nebo chybovosti dat a služeb.','<svg viewBox="0 0 24 24" fill="#2563EB"><path d="M3 13h8V3H3v10zm0 8h8v-6H3v6zm10 0h8V11h-8v10zm0-18v6h8V3h-8z"/></svg>'),
('imp_reputation',NULL,'020',1,'Dopad na pověst a důvěryhodnost','POVEST','Ztráta důvěry zákazníků, partnerů a veřejnosti, negativní medializace a odliv klientů při výpadku služeb nebo prozrazení či ztrátě dat.','<svg viewBox="0 0 24 24" fill="#EA580C"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-2h2v2zm0-4h-2V7h2v6z"/></svg>');

-- 1. Idempotentní UPDATE existujících hlavních záznamů (record_type = 'A', language = 'cs')
UPDATE t
SET t.parent_uuid = p.parent_orig,
	t.sort_code = s.sort_code,
	t.is_leaf = s.is_leaf,
	t.caption = s.caption,
	t.shortname = s.shortname,
	t.description_text = s.description_text,
	t.svg_icon = CASE WHEN ISNULL(t.svg_icon, '') = '' THEN s.svg_icon ELSE t.svg_icon END,
	t.[language] = 'cs',
	t.date_modified = GETDATE()
FROM impact t
JOIN @imp_cs s ON s.builtin_code = t.builtin_code
OUTER APPLY (
	SELECT CASE WHEN s.parent_code IS NOT NULL THEN dbo.f_generate_original('impact', @sys_owner, s.parent_code, '') ELSE NULL END AS parent_orig
) p
WHERE t.object_owner = @sys_owner
  AND t.record_type = 'A'
  AND t.who_modified = @sys_owner
  AND EXISTS (
	SELECT t.parent_uuid, t.sort_code, t.is_leaf, t.caption, t.shortname, t.description_text
	EXCEPT
	SELECT p.parent_orig, s.sort_code, s.is_leaf, s.caption, s.shortname, s.description_text
  );

-- 2. Idempotentní INSERT chybějících hlavních záznamů (record_type = 'A', language = 'cs')
INSERT INTO impact (
	uuid, object_owner, original, record_type, approval_status, [language],
	builtin_code, parent_uuid, sort_code, is_leaf,
	caption, shortname, description_text, svg_icon, is_final, is_protected
)
SELECT
	x.orig, @sys_owner, x.orig, 'A', 'A', 'cs',
	s.builtin_code, p.parent_orig, s.sort_code, s.is_leaf,
	s.caption, s.shortname, s.description_text, s.svg_icon, 0, 1
FROM @imp_cs s
CROSS APPLY (
	SELECT dbo.f_generate_original('impact', @sys_owner, s.builtin_code, '') AS orig
) x
OUTER APPLY (
	SELECT CASE WHEN s.parent_code IS NOT NULL THEN dbo.f_generate_original('impact', @sys_owner, s.parent_code, '') ELSE NULL END AS parent_orig
) p
WHERE NOT EXISTS (
	SELECT 1 FROM impact t
	WHERE t.original = x.orig AND t.object_owner = @sys_owner AND t.record_type = 'A'
);

-- 3. Idempotentní UPDATE a INSERT symetrických 'L' záznamů pro češtinu (language = 'cs')
UPDATE l
SET l.caption = s.caption,
	l.shortname = s.shortname,
	l.description_text = s.description_text,
	l.date_modified = GETDATE()
FROM impact l
JOIN impact a ON a.original = l.original AND a.object_owner = @sys_owner AND a.record_type = 'A'
JOIN @imp_cs s ON s.builtin_code = a.builtin_code
WHERE l.object_owner = @sys_owner
  AND l.record_type = 'L'
  AND l.[language] = 'cs'
  AND l.who_modified = @sys_owner
  AND EXISTS (
	SELECT l.caption, l.shortname, l.description_text
	EXCEPT
	SELECT s.caption, s.shortname, s.description_text
  );

INSERT INTO impact (
	uuid, object_owner, original, record_type, approval_status, [language],
	builtin_code, parent_uuid, sort_code, is_leaf,
	caption, shortname, description_text, svg_icon, is_final, is_protected
)
SELECT
	NEWID(), @sys_owner, a.original, 'L', 'A', 'cs',
	a.builtin_code, a.parent_uuid, a.sort_code, a.is_leaf,
	s.caption, s.shortname, s.description_text, a.svg_icon, a.is_final, a.is_protected
FROM impact a
JOIN @imp_cs s ON s.builtin_code = a.builtin_code
WHERE a.object_owner = @sys_owner
  AND a.record_type = 'A'
  AND a.removed = 0
  AND NOT EXISTS (
	SELECT 1 FROM impact l
	WHERE l.original = a.original AND l.object_owner = @sys_owner AND l.record_type = 'L' AND l.[language] = 'cs'
  );
GO