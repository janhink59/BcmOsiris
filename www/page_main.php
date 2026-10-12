<?php
/**
 * =============================================================================
 * Verze: 2026-10-12
 * Stránka: page_main.php
 * Účel: Hlavní rozcestník dynamicky generovaný z databáze metadat.
 * 
 * Změny:
 * 2026-10-12 - Kompletní přechod ze statického HTML na dynamický T-SQL dotaz
 *              do tabulky meta_object s respektováním hierarchie rolí a
 *              jazykových překladů (COALESCE).
 * =============================================================================
 */

declare(strict_types=1);

class page_main extends abstract_page {

	public function __construct() {
		global $dbsession;

		$this->page_title = 'Hlavní panel - BCM Osiris';

		// Zajištění, že nepodepsaný uživatel neuvidí prázdnou stránku
		// (Ačkoliv by ho měl zachytit už initsession v OsirisLib)
		if (!is_array($dbsession) || empty($dbsession['user_account'])) {
			$this->access_denied = true;
		}
	}

	protected function render_body(): void {
		echo <<<HTML
		<h1 class="page-heading">Vítejte v systému BCM Osiris</h1>
		<p>Vyberte požadovanou akci z níže uvedených modulů.</p>
HTML;

		// Dynamický dotaz pro načtení dostupných stránek podle role s využitím STI jazykového fallbacku
		$sql = "
		WITH s AS (
			SELECT language, active_role FROM dbsession WHERE spid = @@SPID
		)
		SELECT 
			mo.builtin_code,
			mo.system_role,
			COALESCE(
				NULLIF(CAST(l.caption AS NVARCHAR(MAX)), ''),
				NULLIF(CAST(mo.caption AS NVARCHAR(MAX)), ''),
				mo.builtin_code
			) AS caption,
			COALESCE(
				NULLIF(CAST(l.description AS NVARCHAR(MAX)), ''),
				NULLIF(CAST(mo.description AS NVARCHAR(MAX)), ''),
				''
			) AS description
		FROM meta_object mo
		CROSS JOIN s
		LEFT JOIN meta_object l ON l.original = mo.original AND l.object_owner = 0x00 AND l.record_type = 'L' AND l.language = s.language AND l.removed = 0
		WHERE mo.object_type = 'P' 
		  AND mo.record_type = 'A' 
		  AND mo.removed = 0
		  AND mo.object_owner = 0x00
		  AND mo.inactive = 0
		  AND mo.builtin_code NOT IN ('main', 'login', 'logout')
		  AND (
			  s.active_role IN ('S', 'D') 
			  OR (s.active_role = 'A' AND mo.system_role IN ('U', 'A'))
			  OR (s.active_role = 'U' AND mo.system_role = 'U')
		  )
		ORDER BY 
			CASE mo.system_role 
				WHEN 'S' THEN 1 
				WHEN 'D' THEN 2 
				WHEN 'A' THEN 3 
				WHEN 'U' THEN 4 
				ELSE 5 
			END, 
			caption
		";

		$q = sqlrun($sql);
		
		$current_role_group = '';
		
		// Vizuální konfigurace pro jednotlivé sekce rolí
		$role_titles = [
			'S' => ['title' => 'Systémová administrace', 'color' => '#b91c1c', 'btn_class' => 'btn-secondary'],
			'D' => ['title' => 'Vývojářské nástroje', 'color' => '#b91c1c', 'btn_class' => 'btn-secondary'],
			'A' => ['title' => 'Správa organizace', 'color' => '#2E7D32', 'btn_class' => 'btn-success'],
			'U' => ['title' => 'Uživatelské moduly', 'color' => '#004488', 'btn_class' => '']
		];

		while ($row = fetch($q)) {
			$role = $row['system_role'];
			
			if ($role !== $current_role_group) {
				if ($current_role_group !== '') {
					echo "</div>"; // Uzavření předchozí skupiny
				}
				$group_title = $role_titles[$role]['title'] ?? 'Ostatní moduly';
				$group_color = $role_titles[$role]['color'] ?? '#333';
				
				echo <<<HTML
				<div style="margin-top: 20px; padding-top: 15px; border-top: 1px solid #eee;">
					<h3 style="margin-top: 0; font-size: 16px; color: {$group_color};">{$group_title}</h3>
HTML;
				$current_role_group = $role;
			}
			
			$code = htmlspecialchars((string)$row['builtin_code']);
			$caption = htmlspecialchars((string)$row['caption']);
			$desc = htmlspecialchars((string)$row['description']);
			
			$title_attr = $desc !== '' ? " title=\"{$desc}\"" : '';
			$btnClass = 'btn ' . ($role_titles[$role]['btn_class'] ?? '');
			
			echo "<a href=\"index.php?page={$code}\" class=\"{$btnClass}\" style=\"margin-right: 10px; margin-bottom: 10px;\"{$title_attr}>{$caption}</a>\n";
		}
		
		free_result($q);
		
		if ($current_role_group !== '') {
			echo "</div>";
		} else {
			echo "<div class='msg-info'>Zatím nemáte přístup k žádným dalším modulům.</div>";
		}
	}
}