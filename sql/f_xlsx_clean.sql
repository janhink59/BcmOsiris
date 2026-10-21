/* =============================================================================
 * Verze: 2026-10-21 14:25
 * Soubor: f_xlsx_clean.sql
 * Funkce: dbo.f_xlsx_clean
 * Účel:   Pomocná skalární funkce pro očištění hodnot načtených z Excelu (XLSX_*$)
 *         od okrajových mezer a úhlových závorek (<...>) označujících zděděné
 *         hodnoty. V MSSQL 2019 se automaticky inlinuje do dotazu.
 * Vazby:  - Volána z procedury p_xlsx_meta_object (p_xlsx_meta_object.sql)
 *           při přípravě tabulek #clean_page, #clean_phrase, #clean_menu,
 *           #clean_class a #clean_column.
 * Logika: - Pokud je @is_trans = 1 (sloupce druhého jazyka s příponou *_l),
 *           hodnota ponechaná <ve stříškách> znamená dosud nepřeložený zděděný
 *           text a funkce vrátí prázdný řetězec ''.
 *         - Pokud je @is_trans = 0 (primární a technické sloupce), funkce
 *           odstraní vnější stříšky < a > (s výjimkou samotného <svg...></svg>
 *           kódu, pokud není zdvojeně uzavřen jako <<svg...>>).
 * ============================================================================= */

IF OBJECT_ID('f_xlsx_clean', 'FN') IS NOT NULL
	DROP FUNCTION f_xlsx_clean;
GO

CREATE FUNCTION dbo.f_xlsx_clean(
	@val varchar(max),
	@is_trans bit = 0
)
RETURNS varchar(max)
AS
BEGIN
	DECLARE @trimmed varchar(max) = LTRIM(RTRIM(ISNULL(@val, '')));

	IF LEN(@trimmed) >= 2
		AND LEFT(@trimmed, 1) = '<'
		AND RIGHT(@trimmed, 1) = '>'
		AND (LEFT(@trimmed, 4) <> '<svg' OR LEFT(@trimmed, 2) = '<<')
	BEGIN
		IF @is_trans = 1
			RETURN '';

		RETURN SUBSTRING(@trimmed, 2, LEN(@trimmed) - 2);
	END

	RETURN @trimmed;
END
GO