/* =============================================================================
 * Verze: 2026-11-13 17:30
 * Soubor: table_organization_unit.sql
 * Tabulka: organization_unit (Organizační jednotky a útvary)
 * Popis:   Hierarchický číselník vnitřních organizačních útvarů a oddělení
 *          organizace (např. IT oddělení, HR / personální oddělení).
 * Architektura: RAC (Record & Access Control) + SSC (Schvalovací cyklus)
 * Vazby:   - parent_uuid ukazuje na nadřízený útvar (organization_unit.original).
 *          - Vazby na personál (asset_personnel) a spravovaná aktiva (asset)
 *            se ukládají do tabulky link.
 * Změny:
 * - 2026-11-13 17:30: Doplněna registrace třídy a sloupců do sysinit_class
 *   a sysinit_column.
 * - 2026-11-12 18:30: Doplněny sloupce builtin_code, parent_uuid, sort_code,
 *   is_leaf, svg_icon, is_final, is_protected, draft_author, approval_note,
 *   import_origin a indexy uq_organization_unit_draft a ix_organization_unit_parent_sort.
 * ============================================================================= */

-- Kontrola a odstranění tabulky, pokud pochází ze starého systému (obsahuje guid)
IF EXISTS(SELECT * FROM v_syscolumns WHERE tabname='organization_unit' AND colname='guid')
	EXECUTE dropni 'organization_unit';
GO

IF OBJECT_ID('organization_unit') IS NULL
CREATE TABLE organization_unit (
	-- -------------------------------------------------------------------------
	-- Standardní RAC a SSC sloupce
	-- -------------------------------------------------------------------------
	uuid uuid NOT NULL,
	object_owner uuid NOT NULL DEFAULT 0x00,
	original uuid NOT NULL DEFAULT 0x00,
	record_type varchar(1) NOT NULL DEFAULT 'A',
	approval_status varchar(1) NOT NULL DEFAULT 'A',
	draft_author uuid NOT NULL DEFAULT 0x00,
	approval_note varchar(max) NOT NULL DEFAULT '',
	inactive bit NOT NULL DEFAULT 0,
	removed bit NOT NULL DEFAULT 0,
	language varchar(2) NOT NULL DEFAULT 'cs',
	valid_from date NOT NULL DEFAULT '1970-01-01',
	valid_to date NULL,
	is_template bit NOT NULL DEFAULT 0,
	template uuid NULL,
	import_origin varchar(255) NULL,
	
	-- -------------------------------------------------------------------------
	-- Společné textové a prezentační vlastnosti
	-- -------------------------------------------------------------------------
	builtin_code varchar(80) NOT NULL DEFAULT '',
	caption varchar(200) NOT NULL DEFAULT '',
	shortname varchar(40) NOT NULL DEFAULT '',
	external_code varchar(200) NOT NULL DEFAULT '',
	instance_class_name varchar(80) NOT NULL DEFAULT '',
	description_text varchar(max) NOT NULL DEFAULT '',
	help_text varchar(max) NOT NULL DEFAULT '',
	svg_icon varchar(max) NOT NULL DEFAULT '',
	
	-- -------------------------------------------------------------------------
	-- Auditní stopy
	-- -------------------------------------------------------------------------
	date_created datetime NOT NULL DEFAULT getdate(),
	who_created uuid NOT NULL DEFAULT 0x00,
	date_modified datetime NOT NULL DEFAULT getdate(),
	who_modified uuid NOT NULL DEFAULT 0x00,

	-- -------------------------------------------------------------------------
	-- Stromová struktura a ochrana záznamu
	-- -------------------------------------------------------------------------
	parent_uuid uuid NULL,
	sort_code varchar(200) NOT NULL DEFAULT '',
	is_leaf bit NOT NULL DEFAULT 1,
	builtin bit NOT NULL DEFAULT 0,
	is_final bit NOT NULL DEFAULT 0,
	is_protected bit NOT NULL DEFAULT 0,

	CONSTRAINT pk_organization_unit PRIMARY KEY (uuid)
);
GO

-- -----------------------------------------------------------------------------
-- Zajištění chybějících sloupců pro existující databáze
-- -----------------------------------------------------------------------------
EXEC p_create_missing_column 'organization_unit', 'draft_author', 'uuid NOT NULL DEFAULT 0x00';
EXEC p_create_missing_column 'organization_unit', 'approval_note', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'organization_unit', 'import_origin', 'varchar(255) NULL';
EXEC p_create_missing_column 'organization_unit', 'builtin_code', 'varchar(80) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'organization_unit', 'svg_icon', 'varchar(max) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'organization_unit', 'parent_uuid', 'uuid NULL';
EXEC p_create_missing_column 'organization_unit', 'sort_code', 'varchar(200) NOT NULL DEFAULT ''''';
EXEC p_create_missing_column 'organization_unit', 'is_leaf', 'bit NOT NULL DEFAULT 1';
EXEC p_create_missing_column 'organization_unit', 'is_final', 'bit NOT NULL DEFAULT 0';
EXEC p_create_missing_column 'organization_unit', 'is_protected', 'bit NOT NULL DEFAULT 0';
GO

-- -----------------------------------------------------------------------------
-- Indexy pro zajištění RAC a SSC architektury a průchodu stromem
-- -----------------------------------------------------------------------------
EXEC sp_create_index 
	@tname = 'organization_unit', 
	@iname = 'uq_organization_unit_active', 
	@colnames = 'original, object_owner', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'organization_unit', 
	@iname = 'uq_organization_unit_language', 
	@colnames = 'original, object_owner, language', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''L'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'organization_unit', 
	@iname = 'uq_organization_unit_draft', 
	@colnames = 'original, object_owner, language, draft_author', 
	@uni = 'UNIQUE', 
	@options = 'WHERE record_type = ''D'' AND removed = 0';
GO

EXEC sp_create_index 
	@tname = 'organization_unit', 
	@iname = 'ix_organization_unit_parent_sort', 
	@colnames = 'parent_uuid, sort_code, builtin_code', 
	@uni = '', 
	@options = 'WHERE record_type = ''A'' AND removed = 0';
GO

-- -----------------------------------------------------------------------------
-- Registrace třídy a sloupců do sysinit_class a sysinit_column
-- -----------------------------------------------------------------------------
IF OBJECT_ID('sysinit_class', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_class WHERE class_name = 'organization_unit';

	INSERT INTO sysinit_class (class_name, [language], storage_type, storage_code, caption, caption_plural, description, helptext) VALUES
	('organization_unit','cs','T','organization_unit','Organizační jednotka','Organizační jednotky','Číselník vnitřních organizačních útvarů a oddělení v rámci organizace.','Evidence organizační struktury tenanta.');

	INSERT INTO sysinit_class (class_name, [language], caption, caption_plural, description, helptext) VALUES
	('organization_unit','en','Organizational Unit','Organizational Units','Directory of internal organizational units and departments within an organization.','Registry of the tenant organizational structure.');
END

IF OBJECT_ID('sysinit_column', 'U') IS NOT NULL
BEGIN
	DELETE FROM sysinit_column WHERE table_name = 'organization_unit';

	INSERT INTO sysinit_column (table_name, column_name, [language], caption, label, header, helptext, referenced_class_code) VALUES
	('organization_unit','parent_uuid','cs','Nadřízená položka ve stromu (parent_uuid)','Nadřízená složka / položka','Nadřízený uzel','Odkaz na nadřízený uzel ve stromové hierarchii (prázdné pole znamená kořenovou položku nejvyšší úrovně).','organization_unit');
END
GO