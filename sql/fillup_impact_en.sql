/* =============================================================================
 * Verze: 2026-11-09 14:15
 * Soubor: fillup_impact_en.sql
 * Účel:   Idempotentní nastavení výchozích anglických překladů (jazyk 'en',
 *         record_type = 'L') pro systémový katalog oblastí dopadů v tabulce
 *         impact (object_owner = 0x00), seřazené podle builtin_code.
 * Vazby:  - Navazuje na fillup_impact.sql.
 * ============================================================================= */

SET NOCOUNT ON;
GO

DECLARE @sys_owner uniqueidentifier = CAST(0x00 AS uniqueidentifier);

DECLARE @imp_en TABLE (
	builtin_code varchar(80) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
	caption varchar(200) NOT NULL,
	shortname varchar(40) NOT NULL,
	description_text varchar(max) NOT NULL
);

INSERT INTO @imp_en (builtin_code, caption, shortname, description_text) VALUES
('imp_criminal_liability','Criminal Liability','CRIM','Risk of criminal prosecution or liability of statutory bodies, management, or responsible employees resulting from service outage, data breach, or data destruction.'),
('imp_financial','Financial Impact','FIN','Direct financial losses, recovery and restoration costs, SLA penalties, and lost revenue caused by service outage, data corruption, or data destruction.'),
('imp_general_hazard','General Hazard (Life, Health, Safety)','HAZ','Threat to human life and health, occupational safety, public order, or the environment due to service failure or critical data inconsistency.'),
('imp_legal_breach','Breach of Laws & Regulations','LEGAL','Violation of statutory and regulatory obligations (GDPR, NIS2, DORA, sector regulations), administrative fines, and loss of licences.'),
('imp_management_disruption','Disruption of Company Management','MGMT','Paralysis of internal decision-making, loss of situational awareness, and inability to govern core processes due to unavailability or inaccuracy of data and services.'),
('imp_reputation','Reputation & Trust Impact','REP','Loss of customer, partner, and public trust, negative media coverage, and client churn following service outages or data disclosure/loss.');

-- 1. Hromadný UPDATE existujících anglických 'L' záznamů (language = 'en')
UPDATE l
SET l.caption = s.caption,
	l.shortname = s.shortname,
	l.description_text = s.description_text,
	l.date_modified = GETDATE()
FROM impact l
JOIN impact a ON a.original = l.original AND a.object_owner = @sys_owner AND a.record_type = 'A'
JOIN @imp_en s ON s.builtin_code = a.builtin_code
WHERE l.object_owner = @sys_owner
  AND l.record_type = 'L'
  AND l.[language] = 'en'
  AND l.who_modified = @sys_owner
  AND EXISTS (
	SELECT l.caption, l.shortname, l.description_text
	EXCEPT
	SELECT s.caption, s.shortname, s.description_text
  );

-- 2. Hromadný INSERT chybějících anglických 'L' záznamů (language = 'en')
INSERT INTO impact (
	uuid, object_owner, original, record_type, approval_status, [language],
	builtin_code, parent_uuid, sort_code, is_leaf,
	caption, shortname, description_text, svg_icon, is_final, is_protected
)
SELECT
	NEWID(), @sys_owner, a.original, 'L', 'A', 'en',
	a.builtin_code, a.parent_uuid, a.sort_code, a.is_leaf,
	s.caption, s.shortname, s.description_text, a.svg_icon, a.is_final, a.is_protected
FROM impact a
JOIN @imp_en s ON s.builtin_code = a.builtin_code
WHERE a.object_owner = @sys_owner
  AND a.record_type = 'A'
  AND a.removed = 0
  AND NOT EXISTS (
	SELECT 1 FROM impact l
	WHERE l.original = a.original AND l.object_owner = @sys_owner AND l.record_type = 'L' AND l.[language] = 'en'
  );
GO