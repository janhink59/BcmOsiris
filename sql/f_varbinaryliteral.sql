/*
	=========================================================
	Funkce: f_varbinaryliteral
	Popis:
		Vytvoří SQL literál typu VARBINARY(MAX), rozdělený 
		na více řádků po 1000 bajtech. 
		Každý řádek začíná prefixem 0x.

		Slouží k exportu binárních dat ve formě vhodné pro 
		přímé použití v SQL skriptech.
	---------------------------------------------------------
	Poznámky:
		- Vrací 'NULL' pokud vstup je NULL.
		- Funguje s libovolnou délkou VARBINARY(MAX).
	=========================================================
*/

CREATE OR ALTER FUNCTION f_varbinaryliteral (
	@vb VARBINARY(MAX)
)
RETURNS VARCHAR(MAX)
AS
BEGIN
	DECLARE @result VARCHAR(MAX) = '';
	DECLARE @block VARBINARY(1000);
	DECLARE @pos INT = 1;
	DECLARE @len INT = DATALENGTH(@vb);

	IF @vb IS NULL
		RETURN 'NULL';

	-- Pro každý blok přidáme nový řádek s prefixem 0x
	WHILE @pos <= @len
	BEGIN
		SET @block = SUBSTRING(@vb, @pos, 1000);

		-- Přidání řádku s + pouze pokud už máme nějaký obsah
		IF @pos = 1
			SET @result = 'convert(varbinary(max),'+CONVERT(VARCHAR(MAX), @block, 1)+')';
		ELSE
			SET @result = @result + CHAR(13) + CHAR(10) + '+' + CONVERT(VARCHAR(MAX), @block, 1);

		SET @pos += 1000;
	END

	RETURN @result;
END;
GO
