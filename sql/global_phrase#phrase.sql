/* =============================================================================
 * Verze: 2026-11-13 16:15
 * Soubor: global_phrase#phrase.sql
 * Účel:   Registrace kontejneru global_phrase do sysinit_object a naplnění
 *         celosystémových českých a anglických frází do sysinit_phrase.
 * Vazby:  Zpracováváno procedurou dbo.p_sysinit_process (p_sysinit_process.sql).
 * ============================================================================= */

SET NOCOUNT ON;
GO

DELETE FROM sysinit_object WHERE object_type = 'P' AND builtin_code = 'global_phrase';
DELETE FROM sysinit_phrase WHERE source_code = 'global_phrase';

INSERT INTO sysinit_object (object_type, builtin_code, [language], system_role, caption, description) VALUES
('P','global_phrase','cs','U','Globální fráze systému','Třída a kontejner pro celosystémové textové fráze a sdílené popisky'),
('P','global_phrase','en','U','System Global Phrases','Class and container for system-wide text phrases and shared labels');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext, css_class) VALUES
('global_phrase','cancel','cs','Storno','',''),
('global_phrase','error','cs','Chyba','',''),
('global_phrase','no','cs','Ne','',''),
('global_phrase','ok','cs','OK','',''),
('global_phrase','warning','cs','Varování','',''),
('global_phrase','yes','cs','Ano','','');

INSERT INTO sysinit_phrase (source_code, builtin_code, [language], caption, helptext) VALUES
('global_phrase','cancel','en','Cancel',''),
('global_phrase','error','en','Error',''),
('global_phrase','no','en','No',''),
('global_phrase','ok','en','OK',''),
('global_phrase','warning','en','Warning',''),
('global_phrase','yes','en','Yes','');
GO