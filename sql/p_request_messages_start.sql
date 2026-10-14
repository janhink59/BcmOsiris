/* =============================================================================
 * Verze: 2026-10-14 12:36
 * Soubor: p_request_messages_start.sql
 * Procedura: p_request_messages_start
 * Popis:   Inicializuje kontext pro ukládání zpráv do tabulky request_message
 *          pod aktuálním @@SPID a volitelně vymaže staré zprávy.
 * Vazby:   - Volána z PHP třídy excel_reader (metoda run_package) před spuštěním
 *            importní procedury p_xlsx_*.
 *          - Volána v závěru distribučních SQL skriptů generovaných v
 *            page_excel_reader.php (metoda process_distribution).
 *          - Manipuluje s tabulkami request_message (má cizí klíč na dbsession.spid)
 *            a dbsession (definována v table_user_session.sql).
 * Změny:   - 2026-10-14: Doplněna podmínka WHERE spid = @@SPID při kontrole
 *            existence záznamu v dbsession.
 *          - 2026-10-14: Odstraněny neexistující sloupce ramses_user a review_type;
 *            INSERT do dbsession upraven podle platného schématu BCM Osiris.
 * ============================================================================= */

execute dropni 'p_request_messages_start'
GO
/*
	Procedura zajistí existenci session záznamu
	Parametr @reset ve výchozím nastavení odstraní dosavadní zprávy
*/
create procedure p_request_messages_start
	@reset bit=1
as
begin
	set nocount on;

	-- Odstranění předchozích zpráv pro aktuální proces (pokud je požadován reset)
	if @reset=1
		delete from request_message where spid=@@SPID;

	-- Pokud pro aktuální @@SPID neexistuje záznam v dbsession (např. při běhu
	-- distribučního skriptu mimo webovou aplikaci), založíme servisní kontext,
	-- aby prošla referenční integrita tabulky request_message (references dbsession).
	if not exists(select 1 from dbsession where spid=@@SPID)
	begin
		insert into dbsession(
			spid,
			wwwsession,
			user_account,
			login_session_uuid,
			user_name,
			organization,
			organization_name,
			display_name,
			[language],
			working_date,
			active_role,
			session_log
		) values (
			@@SPID,                                    -- Aktuální proces SQL Serveru
			'batch_' + convert(varchar(20), @@SPID),   -- Servisní identifikátor relace
			0x00,                                      -- Systémový účet
			0x00,                                      -- Systémová relace pro audit
			'system',                                  -- Technické jméno účtu
			0x00,                                      -- Systémová organizace (0x00)
			'System',                                  -- Název organizace
			'System Batch',                            -- Zobrazované jméno
			'cs',                                      -- Výchozí jazyk
			getdate(),                                 -- Pracovní datum
			'S',                                       -- Role Sysadmin
			0                                          -- Výchozí hodnota session_log
		);
	end
end
GO