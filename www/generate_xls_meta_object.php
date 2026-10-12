<?php
/**
 * Generátor XLSX šablony pro import systémových objektů.
 * Využívá existující závislost phpoffice/phpspreadsheet.
 */

require_once __DIR__ . '/vendor/autoload.php';

use PhpOffice\PhpSpreadsheet\Spreadsheet;
use PhpOffice\PhpSpreadsheet\Writer\Xlsx;
use PhpOffice\PhpSpreadsheet\Style\Fill;

$spreadsheet = new Spreadsheet();

// 1. Založení a formátování systémové záložky CONTENT_INFO
$sheetInfo = $spreadsheet->getActiveSheet();
$sheetInfo->setTitle('CONTENT_INFO');

// Hlavičky
$sheetInfo->setCellValue('A1', 'package_code');
$sheetInfo->setCellValue('B1', 'description');
$sheetInfo->setCellValue('C1', 'version_date');

// Data
$sheetInfo->setCellValue('A2', 'sys_objects');
$sheetInfo->setCellValue('B2', 'Import základních stránek a systémových objektů do meta_object');
$sheetInfo->setCellValue('C2', date('Y-m-d'));

$sheetInfo->getStyle('A1:C1')->getFont()->setBold(true);
$sheetInfo->getColumnDimension('A')->setWidth(20);
$sheetInfo->getColumnDimension('B')->setWidth(70);
$sheetInfo->getColumnDimension('C')->setWidth(15);

// 2. Založení a formátování datové záložky meta_object
$sheetMeta = $spreadsheet->createSheet();
$sheetMeta->setTitle('meta_object');

$headers = [
	'A1' => 'object_type',
	'B1' => 'builtin_code',
	'C1' => 'system_role',
	'D1' => 'module',
	'E1' => 'caption_cs',
	'F1' => 'description_cs',
	'G1' => 'caption_en',
	'H1' => 'description_en'
];

foreach ($headers as $cell => $val) {
	$sheetMeta->setCellValue($cell, $val);
}

// Obarvení hlavičky pro vizuální odlišení technických dat a překladů
$sheetMeta->getStyle('A1:D1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFE0E0E0');
$sheetMeta->getStyle('E1:F1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFD9EAD3');
$sheetMeta->getStyle('G1:H1')->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FFFCE5CD');
$sheetMeta->getStyle('A1:H1')->getFont()->setBold(true);

// Vzorová data (základní moduly, o kterých jsme se bavili)
$data = [
	['P', 'organization_licence', 'S', '', 'Správa licencí organizací', 'Nástroj pro aktivaci tenantů', 'Org. Licence Management', 'Tool for tenant activation'],
	['P', 'meta_class',           'S', '', 'Správa metadat tříd',       'Definice datového modelu',     'Meta-class Management',   'Data model definitions'],
	['P', 'org_users',            'A', '', 'Správa uživatelů',          'Správa uživatelů tenanta',     'User Management',         'Tenant user management'],
	['P', 'excel_reader',         'S', '', 'Import dat z Excelu',       'Nástroj pro hromadný import',  'Excel Data Import',       'Mass data import tool'],
	['P', 'change_user_context',  'U', '', 'Změna kontextu',            'Přepínání tenantů a rolí',     'Context Switch',          'Tenant and role switching']
];

$row = 2;
foreach ($data as $rowData) {
	$col = 'A';
	foreach ($rowData as $cellData) {
		$sheetMeta->setCellValue($col . $row, $cellData);
		$col++;
	}
	$row++;
}

foreach (range('A', 'H') as $columnID) {
	$sheetMeta->getColumnDimension($columnID)->setAutoSize(true);
}

// Odeslání hlaviček pro přímé stažení vygenerovaného souboru do prohlížeče
header('Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
header('Content-Disposition: attachment;filename="Template_sys_objects.xlsx"');
header('Cache-Control: max-age=0');

$writer = new Xlsx($spreadsheet);
$writer->save('php://output');
exit;